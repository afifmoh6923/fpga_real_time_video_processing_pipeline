///////////////////////////////////////////////////////////////////////////////
// box_blur.sv
// ECE 385 Final Project – Real-Time FPGA Video Processing Pipeline
//
// 3×3 BOX (AVERAGE) BLUR  (SW[2])
// ─────────────────────────────────────────────────────────────────────────────
// Applies a uniform 3×3 averaging kernel to each colour channel:
//
//   Kernel =  (1/9) × [1 1 1]
//                      [1 1 1]
//                      [1 1 1]
//
// Division by 9 (integer approximation):
//   result ≈ (sum * 7) >> 6   where 7/64 ≈ 1/9.14  (error < 2%)
//   Or more precisely: (sum * 28) >> 8  (28/256 ≈ 1/9.14)
//   Maximum sum per channel: 255 × 9 = 2295; 2295 * 28 = 64260 < 65536 ✓
//
// 3-row neighbourhood access:
//   Provided by two instances of line_buffer.sv (one buffer per pixel_clk).
//   The 3×3 window is built by additionally storing the previous two columns
//   at each row using 2-deep shift registers (see column_prev signal below).
//
// Pixel-doubling note:
//   pixel_advance is driven HIGH for one pixel_clk every two display pixels
//   (when the display scan crosses to a new camera pixel column).
//   row_advance   is driven HIGH for one pixel_clk at each new camera row.
//   These signals come from filter_pipeline.sv.
//
// Pipeline depth: 2 clock cycles (1 BRAM read + 1 accumulate/register).
// Border pixels (first 2 rows and first 2 cols) output 0 (black).
///////////////////////////////////////////////////////////////////////////////

module box_blur (
    input  logic        clk,
    input  logic        reset,
    input  logic        enable,         // SW[2]

    input  logic        pixel_advance,  // 1 cycle per new camera pixel
    input  logic        row_advance,    // 1 cycle at new camera row start

    input  logic        pixel_valid,
    input  logic [23:0] rgb_in,         // {R[7:0], G[7:0], B[7:0]}

    output logic [23:0] rgb_out,
    output logic        pvalid_out
);
    // =========================================================================
    // LINE BUFFER WIRES
    // =========================================================================
    logic [23:0] row0, row1, row2;   // three rows of the 3×3 window (centre col)

    line_buffer #(.WIDTH(320), .DATA_WIDTH(24)) lb (
        .clk           (clk),
        .reset         (reset),
        .pixel_advance (pixel_advance),
        .row_advance   (row_advance),
        .din           (rgb_in),
        .row0          (row0),
        .row1          (row1),
        .row2          (row2)
    );

    // =========================================================================
    // COLUMN SHIFT REGISTERS  (2-deep, one per row)
    // Provide the left two columns of the 3×3 window.
    // ─────────────────────────────────────────────────────────────────────────
    // Layout:
    //   col_prev1_r0[1] col_prev1_r0[0]  row0[current]
    //   col_prev1_r1[1] col_prev1_r1[0]  row1[current]
    //   col_prev1_r2[1] col_prev1_r2[0]  row2[current]
    //
    //   where col_prev_rX[0] = 1 cycle ago  (column - 1)
    //         col_prev_rX[1] = 2 cycles ago (column - 2)
    // =========================================================================
    logic [23:0] p_r0 [0:1];   // previous columns for row0
    logic [23:0] p_r1 [0:1];   // previous columns for row1
    logic [23:0] p_r2 [0:1];   // previous columns for row2

    // =========================================================================
    // PSEUDO-CODE:
    //
    // On every rising edge of clk when pixel_advance = 1:
    //   Shift column registers:
    //     p_r0[1] <= p_r0[0];   p_r0[0] <= row0;
    //     p_r1[1] <= p_r1[0];   p_r1[0] <= row1;
    //     p_r2[1] <= p_r2[0];   p_r2[0] <= row2;
    //
    // 3×3 window (all valid after 2 rows, 2 columns have been scanned):
    //   p00=p_r0[1] p01=p_r0[0] p02=row0
    //   p10=p_r1[1] p11=p_r1[0] p12=row1
    //   p20=p_r2[1] p21=p_r2[0] p22=row2
    //
    // Per channel (R shown):
    //   sum_R = p00_R + p01_R + p02_R
    //         + p10_R + p11_R + p12_R
    //         + p20_R + p21_R + p22_R
    //   avg_R = (sum_R * 28) >> 8      // ≈ sum_R / 9
    //   Clamp avg_R to 255 (overflow guard)
    //
    // if (enable):
    //   rgb_out <= {avg_R[7:0], avg_G[7:0], avg_B[7:0]}
    // else:
    //   rgb_out <= rgb_in  (bypassed, registered to match pipeline depth)
    //
    // pvalid_out <= pixel_valid  (registered twice to match 2-cycle latency)
    // =========================================================================

    // Column shift register update
    always_ff @(posedge clk) begin
        if (reset) begin
            p_r0[0] <= '0; p_r0[1] <= '0;
            p_r1[0] <= '0; p_r1[1] <= '0;
            p_r2[0] <= '0; p_r2[1] <= '0;
        end else if (pixel_advance) begin
            p_r0[1] <= p_r0[0]; p_r0[0] <= row0;
            p_r1[1] <= p_r1[0]; p_r1[0] <= row1;
            p_r2[1] <= p_r2[0]; p_r2[0] <= row2;
        end
    end

    // ── 3×3 window extraction (channel-split) ────────────────────────────────
    // Red channel
    logic [7:0] p00R, p01R, p02R, p10R, p11R, p12R, p20R, p21R, p22R;
    assign {p00R, p01R, p02R} = {p_r0[1][23:16], p_r0[0][23:16], row0[23:16]};
    assign {p10R, p11R, p12R} = {p_r1[1][23:16], p_r1[0][23:16], row1[23:16]};
    assign {p20R, p21R, p22R} = {p_r2[1][23:16], p_r2[0][23:16], row2[23:16]};

    // Green channel
    logic [7:0] p00G, p01G, p02G, p10G, p11G, p12G, p20G, p21G, p22G;
    assign {p00G, p01G, p02G} = {p_r0[1][15:8], p_r0[0][15:8], row0[15:8]};
    assign {p10G, p11G, p12G} = {p_r1[1][15:8], p_r1[0][15:8], row1[15:8]};
    assign {p20G, p21G, p22G} = {p_r2[1][15:8], p_r2[0][15:8], row2[15:8]};

    // Blue channel
    logic [7:0] p00B, p01B, p02B, p10B, p11B, p12B, p20B, p21B, p22B;
    assign {p00B, p01B, p02B} = {p_r0[1][7:0], p_r0[0][7:0], row0[7:0]};
    assign {p10B, p11B, p12B} = {p_r1[1][7:0], p_r1[0][7:0], row1[7:0]};
    assign {p20B, p21B, p22B} = {p_r2[1][7:0], p_r2[0][7:0], row2[7:0]};

    // ── Sum across 9 pixels per channel ──────────────────────────────────────
    // Max sum = 255×9 = 2295, needs 12 bits
    logic [11:0] sum_R, sum_G, sum_B;
    assign sum_R = p00R + p01R + p02R + p10R + p11R + p12R + p20R + p21R + p22R;
    assign sum_G = p00G + p01G + p02G + p10G + p11G + p12G + p20G + p21G + p22G;
    assign sum_B = p00B + p01B + p02B + p10B + p11B + p12B + p20B + p21B + p22B;

    // ── Divide by 9 using multiply-shift: (sum * 28) >> 8 ────────────────────
    // sum_R[11:0] * 28 → max 2295*28=64260, fits in 16 bits
    logic [15:0] avg_R_raw, avg_G_raw, avg_B_raw;
    assign avg_R_raw = (sum_R * 5'd28) >> 8;
    assign avg_G_raw = (sum_G * 5'd28) >> 8;
    assign avg_B_raw = (sum_B * 5'd28) >> 8;

    // ── Pipeline register + bypass delay ─────────────────────────────────────
    // Also register rgb_in and pixel_valid twice to match 2-cycle depth
    logic [23:0] rgb_in_d1, rgb_in_d2;
    logic        pv_d1, pv_d2;

    always_ff @(posedge clk) begin
        if (reset) begin
            rgb_out    <= 24'h0;
            pvalid_out <= 1'b0;
            rgb_in_d1  <= 24'h0;
            rgb_in_d2  <= 24'h0;
            pv_d1      <= 1'b0;
            pv_d2      <= 1'b0;
        end else begin
            // Delay line for bypass path
            rgb_in_d1 <= rgb_in;
            rgb_in_d2 <= rgb_in_d1;
            pv_d1     <= pixel_valid;
            pv_d2     <= pv_d1;

            pvalid_out <= pv_d2;

            if (enable) begin
                rgb_out <= {
                    (avg_R_raw > 16'd255) ? 8'hFF : avg_R_raw[7:0],
                    (avg_G_raw > 16'd255) ? 8'hFF : avg_G_raw[7:0],
                    (avg_B_raw > 16'd255) ? 8'hFF : avg_B_raw[7:0]
                };
            end else begin
                rgb_out <= rgb_in_d2;   // bypass: match pipeline depth
            end
        end
    end

endmodule
