///////////////////////////////////////////////////////////////////////////////
// line_buffer.sv
// ECE 385 Final Project – Real-Time FPGA Video Processing Pipeline
//
// 2-LINE BUFFER  (3×3 neighbourhood access for convolution filters)
// ─────────────────────────────────────────────────────────────────────────────
// Purpose:
//   Stores the previous two rows of camera pixels so that at any column
//   position the caller can simultaneously access:
//     row0  – 2 rows back  (oldest)
//     row1  – 1 row back
//     row2  – current row pixel (registered version of din)
//
// Usage:
//   Instantiated inside box_blur, sharpen, and edge_detect.
//   pixel_advance must be asserted for exactly ONE pixel_clk cycle per camera
//   pixel (every two display pixels due to pixel-doubling in top.sv).
//   row_advance must be asserted for ONE cycle at the start of each new row.
//
// Implementation:
//   Two single-port BRAMs (line_ram_0, line_ram_1), each 320 × DATA_WIDTH.
//   A ping-pong pointer (bank_sel) swaps which BRAM is "newer":
//     bank_sel = 0:  line_ram_0 = current write target  (newest row)
//                    line_ram_1 = read-only             (one row back)
//     bank_sel = 1:  line_ram_1 = current write target
//                    line_ram_0 = read-only
//   A separate read pointer runs one step behind the write pointer so that
//   data written in the current row becomes row1 on the NEXT row.
//
// BRAM latency:
//   Both BRAMs are inferred as synchronous single-port with 1-cycle read
//   latency.  Therefore row0 and row1 outputs are valid ONE cycle after
//   pixel_advance.  din is registered by one cycle to produce row2,
//   keeping all three outputs aligned.
//
// Border conditions:
//   During the first two rows and first column, older rows are invalid
//   (contain stale or zeroed data from initialisation).
//   Downstream filters should ignore or clamp borders – acceptable for a
//   real-time display application.
///////////////////////////////////////////////////////////////////////////////

module line_buffer #(
    parameter  WIDTH      = 320,     // pixels per camera row
    parameter  DATA_WIDTH = 24       // bits per pixel  (RGB888 inside pipeline)
) (
    input  logic                    clk,
    input  logic                    reset,

    input  logic                    pixel_advance,  // 1 cycle per new camera pixel
    input  logic                    row_advance,    // 1 cycle at start of new row

    input  logic [DATA_WIDTH-1:0]   din,            // current row pixel in

    output logic [DATA_WIDTH-1:0]   row0,           // pixel from 2 rows back
    output logic [DATA_WIDTH-1:0]   row1,           // pixel from 1 row back
    output logic [DATA_WIDTH-1:0]   row2            // current pixel (din, 1-cycle delay)
);

    // =========================================================================
    // INTERNAL BRAM ARRAYS
    // =========================================================================
    // In Vivado these will be inferred as Block RAM (RAMB18 / RAMB36).
    // Depth = WIDTH, width = DATA_WIDTH.
    logic [DATA_WIDTH-1:0] line_ram_0 [0:WIDTH-1];
    logic [DATA_WIDTH-1:0] line_ram_1 [0:WIDTH-1];

    // =========================================================================
    // PING-PONG CONTROL
    // =========================================================================
    logic        bank_sel;          // 0 → write ram0; 1 → write ram1
    logic [8:0]  wr_ptr;            // write pointer  0..319
    logic [8:0]  rd_ptr;            // read  pointer  (= wr_ptr, same column)

    // =========================================================================
    // PSEUDO-CODE:
    //
    // On every rising edge of clk:
    //
    //   if (reset):
    //       bank_sel <= 0;  wr_ptr <= 0;  rd_ptr <= 0;
    //       row0 <= 0;  row1 <= 0;  row2 <= 0;
    //
    //   if (row_advance):
    //       // Swap banks: new row will write into the OTHER BRAM
    //       bank_sel <= ~bank_sel;
    //       wr_ptr   <= 0;   // reset column pointer to start of new row
    //       // (rd_ptr will follow wr_ptr)
    //
    //   if (pixel_advance):
    //       rd_ptr <= wr_ptr;    // read at same column position as write
    //
    //       // Write current pixel into the active (write) bank
    //       if (bank_sel == 0):
    //           line_ram_0[wr_ptr] <= din;
    //       else:
    //           line_ram_1[wr_ptr] <= din;
    //
    //       // Read older rows from the inactive (read-only) banks
    //       // row1 = the bank we just stopped writing to (most recent complete row)
    //       // row0 = the other bank (row before that)
    //       if (bank_sel == 0):
    //           row1 <= line_ram_1[rd_ptr];   // one row back  = old write bank
    //           row0 <= line_ram_0[rd_ptr];   // two rows back = current read bank
    //                                          // (contains data from 2 rows ago
    //                                          //  because we overwrote row by row)
    //       else:
    //           row1 <= line_ram_0[rd_ptr];
    //           row0 <= line_ram_1[rd_ptr];
    //
    //       row2 <= din;    // current pixel, registered to match BRAM latency
    //
    //       wr_ptr <= (wr_ptr == WIDTH-1) ? 0 : wr_ptr + 1;
    //
    // NOTE on row0 / row1 interpretation:
    //   When bank_sel=0 the CURRENT writes go into ram_0.
    //   ram_1 contains the PREVIOUS complete row  → row1
    //   ram_0 at this moment contains data from TWO rows ago (before the last
    //   swap) so reading ram_0 gives row0.
    //   After bank swap (row_advance), roles reverse.
    // =========================================================================

    always_ff @(posedge clk) begin
        if (reset) begin
            bank_sel <= 1'b0;
            wr_ptr   <= 9'd0;
            rd_ptr   <= 9'd0;
            row0     <= '0;
            row1     <= '0;
            row2     <= '0;
        end else begin

            // ── Row swap ─────────────────────────────────────────────────────
            if (row_advance) begin
                bank_sel <= ~bank_sel;
                wr_ptr   <= 9'd0;
            end

            // ── Per-pixel operation ──────────────────────────────────────────
            if (pixel_advance) begin
                rd_ptr <= wr_ptr;

                // Write into active bank
                if (!bank_sel) begin
                    line_ram_0[wr_ptr] <= din;
                    // Read older rows from the two banks
                    // IMPLEMENT: row1 from ram_1, row0 from ram_0 (see note above)
                    row1 <= line_ram_1[rd_ptr];   // previous complete row
                    row0 <= line_ram_0[rd_ptr];   // row before that
                end else begin
                    line_ram_1[wr_ptr] <= din;
                    row1 <= line_ram_0[rd_ptr];
                    row0 <= line_ram_1[rd_ptr];
                end

                row2 <= din;    // register din to match 1-cycle BRAM latency

                // Advance write pointer
                wr_ptr <= (wr_ptr == WIDTH - 1) ? 9'd0 : wr_ptr + 1;
            end

        end
    end

endmodule
