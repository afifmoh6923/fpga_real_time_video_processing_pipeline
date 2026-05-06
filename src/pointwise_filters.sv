///////////////////////////////////////////////////////////////////////////////
// grayscale.sv
// ECE 385 Final Project – Real-Time FPGA Video Processing Pipeline
//
// GRAYSCALE CONVERSION  (SW[0])
// ─────────────────────────────────────────────────────────────────────────────
// Converts RGB888 to luminance Y using the BT.601 integer approximation:
//   Y = (77*R + 150*G + 29*B) >> 8
//   Coefficients sum to 256, so the result normalises correctly.
//   Maximum intermediate value: 255*150 = 38250  (fits in 16 bits).
//
// When enabled  : rgb_out = {Y, Y, Y}  (same value for all three channels)
// When disabled : rgb_out = rgb_in      (bypass)
//
// Pipeline depth: 1 clock cycle (registered output).
///////////////////////////////////////////////////////////////////////////////

module grayscale (
    input  logic        clk,
    input  logic        reset,
    input  logic        enable,         // SW[0] – 1 = convert to grayscale

    input  logic        pixel_valid,
    input  logic [23:0] rgb_in,         // {R[7:0], G[7:0], B[7:0]}

    output logic [23:0] rgb_out,
    output logic        pvalid_out
);
    // =========================================================================
    // PSEUDO-CODE:
    //
    // On every rising edge of clk:
    //   Extract R = rgb_in[23:16], G = rgb_in[15:8], B = rgb_in[7:0]
    //
    //   if (enable):
    //       y_raw = (77 * R) + (150 * G) + (29 * B)  // up to 16-bit result
    //       Y     = y_raw[15:8]                        // equivalent to >> 8
    //       rgb_out <= {Y, Y, Y}
    //   else:
    //       rgb_out <= rgb_in
    //
    //   pvalid_out <= pixel_valid
    // =========================================================================

    logic [7:0]  R, G, B;
    logic [15:0] y_raw;
    logic [7:0]  Y;

    assign R = rgb_in[23:16];
    assign G = rgb_in[15:8];
    assign B = rgb_in[7:0];

    // Combinational multiply-add (Vivado infers DSP48 slices automatically)
    assign y_raw = (8'd77 * R) + (8'd150 * G) + (8'd29 * B);
    assign Y     = y_raw[15:8];    // divide by 256 via bit-select

    always_ff @(posedge clk) begin
        if (reset) begin
            rgb_out    <= 24'h0;
            pvalid_out <= 1'b0;
        end else begin
            pvalid_out <= pixel_valid;
            if (enable)
                rgb_out <= {Y, Y, Y};
            else
                rgb_out <= rgb_in;
        end
    end

endmodule


///////////////////////////////////////////////////////////////////////////////
// brightness_contrast.sv
// ECE 385 Final Project – Real-Time FPGA Video Processing Pipeline
//
// BRIGHTNESS AND CONTRAST ADJUSTMENT  (SW[3] = brightness, SW[4] = contrast)
// ─────────────────────────────────────────────────────────────────────────────
// Contrast (SW[4]):
//   Scales each channel by 1.5× using shift-add:  val + (val >> 1)
//   This saturates (clips) bright regions but increases perceptual contrast.
//
// Brightness (SW[3]):
//   Adds a fixed offset of +32 to each channel after contrast.
//   Saturates at 255.
//
// Saturation helper:
//   Uses 9-bit intermediate arithmetic; if the 9th bit is set (overflow)
//   clamp to 8'hFF, else take lower 8 bits.
//
// Pipeline depth: 1 clock cycle.
///////////////////////////////////////////////////////////////////////////////

module brightness_contrast (
    input  logic        clk,
    input  logic        reset,
    input  logic        en_brightness,  // SW[3]
    input  logic        en_contrast,    // SW[4]

    input  logic        pixel_valid,
    input  logic [23:0] rgb_in,

    output logic [23:0] rgb_out,
    output logic        pvalid_out
);
    // =========================================================================
    // PARAMETERS
    // =========================================================================
    localparam [7:0] BRIGHT_OFFSET = 8'd32;

    // =========================================================================
    // PSEUDO-CODE (per channel, shown for R; identical for G and B):
    //
    // Step 1 – Contrast (1.5× scale):
    //   if (en_contrast):
    //       R_c = R + (R >> 1)      // 9-bit: R[7:0] + {1'b0, R[7:1]}
    //       clamp to 255 if overflow
    //   else:
    //       R_c = R
    //
    // Step 2 – Brightness (add offset):
    //   if (en_brightness):
    //       R_b = R_c + BRIGHT_OFFSET   // 9-bit addition
    //       clamp to 255 if overflow
    //   else:
    //       R_b = R_c
    //
    // Output:
    //   rgb_out <= {R_b[7:0], G_b[7:0], B_b[7:0]}
    // =========================================================================

    // ── Contrast stage ───────────────────────────────────────────────────────
    // FIXED: real contrast stretching around the midpoint (128).
    // Formula: out = (in - 128) * 2 + 128  =  in*2 - 128
    // This makes darks darker and brights brighter simultaneously,
    // unlike the old 1.5x scale which just made everything brighter.
    // Using 9-bit signed: range is -128 to +382, clamped to [0,255].
    logic signed [9:0] R_c, G_c, B_c;
    always_comb begin
        if (en_contrast) begin
            // (val - 128) * 2 + 128 = val*2 - 128
            R_c = $signed({2'b0, rgb_in[23:16]}) * 2 - 10'sd128;
            G_c = $signed({2'b0, rgb_in[15:8]})  * 2 - 10'sd128;
            B_c = $signed({2'b0, rgb_in[7:0]})   * 2 - 10'sd128;
        end else begin
            R_c = $signed({2'b0, rgb_in[23:16]});
            G_c = $signed({2'b0, rgb_in[15:8]});
            B_c = $signed({2'b0, rgb_in[7:0]});
        end
    end

    // ── Brightness stage ─────────────────────────────────────────────────────
    // Add fixed offset; use same 10-bit signed intermediate from contrast stage
    logic signed [9:0] R_b, G_b, B_b;
    always_comb begin
        if (en_brightness) begin
            R_b = R_c + $signed({2'b0, BRIGHT_OFFSET});
            G_b = G_c + $signed({2'b0, BRIGHT_OFFSET});
            B_b = B_c + $signed({2'b0, BRIGHT_OFFSET});
        end else begin
            R_b = R_c;
            G_b = G_c;
            B_b = B_c;
        end
    end

    // ── Saturate and register ─────────────────────────────────────────────────
    always_ff @(posedge clk) begin
        if (reset) begin
            rgb_out    <= 24'h0;
            pvalid_out <= 1'b0;
        end else begin
            pvalid_out <= pixel_valid;
            rgb_out    <= {
                (R_b < 0 ? 8'h00 : R_b > 255 ? 8'hFF : R_b[7:0]),
                (G_b < 0 ? 8'h00 : G_b > 255 ? 8'hFF : G_b[7:0]),
                (B_b < 0 ? 8'h00 : B_b > 255 ? 8'hFF : B_b[7:0])
            };
        end
    end

endmodule


///////////////////////////////////////////////////////////////////////////////
// channel_isolate.sv
// ECE 385 Final Project – Real-Time FPGA Video Processing Pipeline
//
// RGB CHANNEL ISOLATION  (SW[5]=Red, SW[6]=Green, SW[7]=Blue)
// ─────────────────────────────────────────────────────────────────────────────
// Passes only the selected channel; zeroes the other two.
// Priority if multiple switches active: R > G > B.
// If no switch active: passthrough (bypass).
//
// Pipeline depth: 1 clock cycle.
///////////////////////////////////////////////////////////////////////////////

module channel_isolate (
    input  logic        clk,
    input  logic        reset,
    input  logic        en_R,           // SW[5] – pass red channel only
    input  logic        en_G,           // SW[6] – pass green channel only
    input  logic        en_B,           // SW[7] – pass blue channel only

    input  logic        pixel_valid,
    input  logic [23:0] rgb_in,

    output logic [23:0] rgb_out,
    output logic        pvalid_out
);
    // =========================================================================
    // PSEUDO-CODE:
    //
    // if (en_R):      rgb_out = {R, 8'h00, 8'h00}
    // else if (en_G): rgb_out = {8'h00, G, 8'h00}
    // else if (en_B): rgb_out = {8'h00, 8'h00, B}
    // else:           rgb_out = rgb_in  (bypass)
    // =========================================================================

    always_ff @(posedge clk) begin
        if (reset) begin
            rgb_out    <= 24'h0;
            pvalid_out <= 1'b0;
        end else begin
            pvalid_out <= pixel_valid;
            if (en_R)
                rgb_out <= {rgb_in[23:16], 16'h0000};
            else if (en_G)
                rgb_out <= {8'h00, rgb_in[15:8], 8'h00};
            else if (en_B)
                rgb_out <= {16'h0000, rgb_in[7:0]};
            else
                rgb_out <= rgb_in;
        end
    end

endmodule


///////////////////////////////////////////////////////////////////////////////
// invert  (NEW — SW[11])
// ─────────────────────────────────────────────────────────────────────────────
// Inverts each colour channel: out = 255 - in
// Creates a photographic negative effect. Very simple but visually striking.
// Pipeline depth: 1 cycle.
///////////////////////////////////////////////////////////////////////////////
module invert (
    input  logic        clk,
    input  logic        reset,
    input  logic        enable,         // SW[11]

    input  logic        pixel_valid,
    input  logic [23:0] rgb_in,

    output logic [23:0] rgb_out,
    output logic        pvalid_out
);
    always_ff @(posedge clk) begin
        if (reset) begin
            rgb_out    <= 24'h0;
            pvalid_out <= 1'b0;
        end else begin
            pvalid_out <= pixel_valid;
            if (enable)
                rgb_out <= {
                    8'hFF - rgb_in[23:16],
                    8'hFF - rgb_in[15:8],
                    8'hFF - rgb_in[7:0]
                };
            else
                rgb_out <= rgb_in;
        end
    end
endmodule