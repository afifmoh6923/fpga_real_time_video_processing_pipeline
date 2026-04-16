///////////////////////////////////////////////////////////////////////////////
// ov7670_capture.sv
// ECE 385 Final Project – Real-Time FPGA Video Processing Pipeline
//
// OV7670 PIXEL CAPTURE  (cam_pclk clock domain)
// ─────────────────────────────────────────────────────────────────────────────
// The OV7670 in QVGA RGB565 mode outputs:
//   • VSYNC  – goes HIGH during vertical blanking (between frames)
//              falling edge = first HREF of new frame
//   • HREF   – HIGH during active pixel data within a row
//              goes LOW during horizontal blanking
//   • PCLK   – pixel clock; data valid on RISING edge
//   • D[7:0] – 8-bit data bus; sends TWO bytes per pixel
//
// RGB565 byte order on the bus:
//   Byte 0 (first ) : {R[4:0], G[5:3]}     ← high byte
//   Byte 1 (second) : {G[2:0], B[4:0]}     ← low byte
//   Full pixel       : {byte0, byte1} = 16-bit RGB565
//
// QVGA resolution: 320 columns × 240 rows = 76 800 pixels per frame.
//
// Frame-buffer write address:
//   addr = row * 320 + col  (17-bit, max 76 800 – 1)
//   320 = 256 + 64  so multiply as: (row << 8) + (row << 6)
//
// This module runs ENTIRELY in the cam_pclk domain.
// The dual-port frame buffer handles the clock domain crossing to pixel_clk.
///////////////////////////////////////////////////////////////////////////////

module ov7670_capture (
    // Camera signals (cam_pclk domain)
    input  logic        cam_pclk,
    input  logic        cam_vsync,   // HIGH during vertical blanking
    input  logic        cam_href,    // HIGH during active row data
    input  logic [7:0]  cam_data,    // 8-bit pixel bus

    // Frame-buffer write port outputs
    output logic [16:0] wr_addr,     // 17-bit address (0 .. 76799)
    output logic [15:0] wr_data,     // 16-bit RGB565 pixel
    output logic        wr_en        // write enable (1-cycle pulse per pixel)
);

    // =========================================================================
    // INTERNAL SIGNALS
    // =========================================================================
    logic [8:0]  col;           // column counter  0..319
    logic [7:0]  row;           // row    counter  0..239
    logic        byte_sel;      // 0 = waiting for high byte, 1 = got high byte
    logic [7:0]  high_byte;     // latches first  byte of RGB565 pair
    logic        vsync_prev;    // for falling-edge detection

    // =========================================================================
    // PSEUDO-CODE:
    //
    // On every rising edge of cam_pclk:
    //
    //   1. VSYNC FALLING EDGE DETECTION  (new frame starting)
    //      vsync_prev <= cam_vsync
    //      if (vsync_prev == 1 && cam_vsync == 0):   // falling edge
    //          col      <= 0
    //          row      <= 0
    //          byte_sel <= 0
    //          wr_en    <= 0
    //
    //   2. ACTIVE PIXEL DATA  (HREF = 1)
    //      if (cam_href == 1):
    //          if (byte_sel == 0):          // FIRST byte of pixel pair
    //              high_byte <= cam_data    // latch {R[4:0], G[5:3]}
    //              byte_sel  <= 1
    //              wr_en     <= 0           // not ready to write yet
    //          else:                        // SECOND byte of pixel pair
    //              wr_data   <= {high_byte, cam_data}   // assemble RGB565
    //              wr_addr   <= (row << 8) + (row << 6) + col
    //              wr_en     <= 1           // write this pixel
    //              byte_sel  <= 0
    //              // Advance column:
    //              if (col == 319):
    //                  col <= 0
    //                  if (row == 239): row <= 0
    //                  else:           row <= row + 1
    //              else:
    //                  col <= col + 1
    //
    //   3. HORIZONTAL BLANKING  (HREF = 0)
    //      wr_en    <= 0
    //      byte_sel <= 0   // reset so we always start on the high byte
    // =========================================================================

    always_ff @(posedge cam_pclk) begin
        vsync_prev <= cam_vsync;
        wr_en      <= 1'b0;         // default: no write

        // ── New frame: VSYNC falling edge ────────────────────────────────────
        if (vsync_prev && !cam_vsync) begin
            col      <= 9'd0;
            row      <= 8'd0;
            byte_sel <= 1'b0;

        // ── Active row data ───────────────────────────────────────────────────
        end else if (cam_href) begin
            if (!byte_sel) begin
                // First byte of RGB565 pair
                high_byte <= cam_data;
                byte_sel  <= 1'b1;

            end else begin
                // Second byte – assemble and write pixel
                wr_data  <= {high_byte, cam_data};
                // Address: row*320 + col  (320 = 256 + 64)
                wr_addr  <= ({9'b0, row} << 8)
                          + ({9'b0, row} << 6)
                          + {8'b0, col};
                wr_en    <= 1'b1;
                byte_sel <= 1'b0;

                // Advance pixel counter
                if (col == 9'd319) begin
                    col <= 9'd0;
                    row <= (row == 8'd239) ? 8'd0 : row + 1;
                end else begin
                    col <= col + 1;
                end
            end

        // ── Horizontal blanking ───────────────────────────────────────────────
        end else begin
            byte_sel <= 1'b0;
        end
    end

endmodule
