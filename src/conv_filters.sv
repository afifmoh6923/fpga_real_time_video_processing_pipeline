///////////////////////////////////////////////////////////////////////////////
// sharpen.sv
// ECE 385 Final Project – Real-Time FPGA Video Processing Pipeline
//
// LAPLACIAN SHARPENING FILTER  (SW[8])
// ─────────────────────────────────────────────────────────────────────────────
// Applies the following 3×3 kernel to each colour channel:
//
//   K = [ 0  -1   0]
//       [-1  +5  -1]
//       [ 0  -1   0]
//
// This is an unsharp-mask approximation: K = Identity + Laplacian.
// Result: sharp_X = 5*centre - top - left - right - bottom
//
// Intermediate arithmetic: signed 11-bit
//   max = 5*255 = 1275;  min = 5*255 - 4*255 = 255  (can't go negative if
//   centre is largest) but worst case can go below 0 → use signed arithmetic
//   and clamp to [0, 255].
//
// Same line_buffer + column shift register pattern as box_blur.
// Pipeline depth: 2 clock cycles.
///////////////////////////////////////////////////////////////////////////////

module sharpen (
    input  logic        clk,
    input  logic        reset,
    input  logic        enable,         // SW[8]

    input  logic        pixel_advance,
    input  logic        row_advance,

    input  logic        pixel_valid,
    input  logic [23:0] rgb_in,

    output logic [23:0] rgb_out,
    output logic        pvalid_out
);
    // ── Line buffer ───────────────────────────────────────────────────────────
    logic [23:0] row0, row1, row2;

    line_buffer #(.WIDTH(320), .DATA_WIDTH(24)) lb (
        .clk(clk), .reset(reset),
        .pixel_advance(pixel_advance), .row_advance(row_advance),
        .din(rgb_in), .row0(row0), .row1(row1), .row2(row2)
    );

    // ── Column shift registers (previous 2 columns per row) ──────────────────
    logic [23:0] p_r0 [0:1];
    logic [23:0] p_r1 [0:1];
    logic [23:0] p_r2 [0:1];

    always_ff @(posedge clk) begin
        if (reset) begin
            p_r0[0]<='0; p_r0[1]<='0;
            p_r1[0]<='0; p_r1[1]<='0;
            p_r2[0]<='0; p_r2[1]<='0;
        end else if (pixel_advance) begin
            p_r0[1]<=p_r0[0]; p_r0[0]<=row0;
            p_r1[1]<=p_r1[0]; p_r1[0]<=row1;
            p_r2[1]<=p_r2[0]; p_r2[0]<=row2;
        end
    end

    // =========================================================================
    // PSEUDO-CODE  (all channels identical; shown for R):
    //
    // 3×3 window:
    //   _   p01R  _       (row0: only centre column matters for cross kernel)
    //   p10R p11R p12R    (row1: all three)
    //   _   p21R  _       (row2: only centre column matters)
    //
    // where:
    //   p11R = p_r1[0][23:16]   (row1, 1 column back = kernel centre)
    //   p01R = p_r0[0][23:16]   (row0, 1 column back = top)
    //   p21R = p_r2[0][23:16]   (row2, 1 column back = bottom)
    //   p10R = p_r1[1][23:16]   (row1, 2 columns back = left)
    //   p12R = row1[23:16]      (row1, current col = right)
    //
    // Signed sharpening:
    //   sharp_R = 5*p11R - p01R - p10R - p12R - p21R
    //
    // Clamp to [0, 255]:
    //   if (sharp_R < 0)   → 0
    //   if (sharp_R > 255) → 255
    //   else               → sharp_R[7:0]
    //
    // if (enable): rgb_out = {clamp(R), clamp(G), clamp(B)}
    // else:        rgb_out = rgb_in (delayed to match depth)
    // =========================================================================

    // ── Channel extraction ────────────────────────────────────────────────────
    // Centre (row1, col-1): kernel centre after 1-cycle BRAM latency
    logic [7:0] cR, cG, cB;   // centre pixel
    logic [7:0] tR, tG, tB;   // top    (row0, same col as centre)
    logic [7:0] bR, bG, bB;   // bottom (row2, same col as centre)
    logic [7:0] lR, lG, lB;   // left   (row1, 2 cols back)
    logic [7:0] rR, rG, rB;   // right  (row1, current)

    assign {cR,cG,cB} = {p_r1[0][23:16], p_r1[0][15:8], p_r1[0][7:0]};
    assign {tR,tG,tB} = {p_r0[0][23:16], p_r0[0][15:8], p_r0[0][7:0]};
    assign {bR,bG,bB} = {p_r2[0][23:16], p_r2[0][15:8], p_r2[0][7:0]};
    assign {lR,lG,lB} = {p_r1[1][23:16], p_r1[1][15:8], p_r1[1][7:0]};
    assign {rR,rG,rB} = {row1[23:16],    row1[15:8],     row1[7:0]};

    // ── Signed arithmetic ─────────────────────────────────────────────────────
    // 5*centre fits in 11 bits (max 1275); sum of 4 neighbours max 1020
    logic signed [11:0] shR, shG, shB;
    assign shR = {4'b0, cR}*4'd5 - {4'b0, tR} - {4'b0, lR} - {4'b0, rR} - {4'b0, bR};
    assign shG = {4'b0, cG}*4'd5 - {4'b0, tG} - {4'b0, lG} - {4'b0, rG} - {4'b0, bG};
    assign shB = {4'b0, cB}*4'd5 - {4'b0, tB} - {4'b0, lB} - {4'b0, rB} - {4'b0, bB};

    // ── Clamp helper ──────────────────────────────────────────────────────────
    function automatic [7:0] clamp8 (input logic signed [11:0] v);
        if (v < 0)         clamp8 = 8'h00;
        else if (v > 255)  clamp8 = 8'hFF;
        else               clamp8 = v[7:0];
    endfunction

    // ── Bypass delay + register ───────────────────────────────────────────────
    logic [23:0] rgb_d1, rgb_d2;
    logic        pv_d1, pv_d2;

    always_ff @(posedge clk) begin
        if (reset) begin
            rgb_out <= 24'h0; pvalid_out <= 1'b0;
            rgb_d1  <= 24'h0; rgb_d2     <= 24'h0;
            pv_d1   <= 1'b0;  pv_d2      <= 1'b0;
        end else begin
            rgb_d1 <= rgb_in; rgb_d2 <= rgb_d1;
            pv_d1  <= pixel_valid; pv_d2 <= pv_d1;
            pvalid_out <= pv_d2;
            if (enable)
                rgb_out <= {clamp8(shR), clamp8(shG), clamp8(shB)};
            else
                rgb_out <= rgb_d2;
        end
    end

endmodule


///////////////////////////////////////////////////////////////////////////////
// edge_detect.sv
// ECE 385 Final Project – Real-Time FPGA Video Processing Pipeline
//
// SOBEL EDGE DETECTION  (SW[1])
// ─────────────────────────────────────────────────────────────────────────────
// Applies the Sobel operator.  Best used AFTER the grayscale filter so that
// only one channel carries luminance information.  If the input is colour,
// the green channel is used as the luminance proxy.
//
// Sobel kernels:
//   Gx = [-1  0 +1]      Gy = [-1 -2 -1]
//        [-2  0 +2]           [ 0  0  0]
//        [-1  0 +1]           [+1 +2 +1]
//
// Gradient magnitude (approximate to avoid square root):
//   |Gx| + |Gy|  →  clamp to [0, 255]
//
// Output: grayscale edge map {mag, mag, mag}.
// When disabled: pass rgb_in through (delayed to match depth).
//
// Pipeline depth: 2 clock cycles.
// Intermediate precision: signed 13-bit (max |Gx| or |Gy| = 4×255 = 1020).
///////////////////////////////////////////////////////////////////////////////

module edge_detect (
    input  logic        clk,
    input  logic        reset,
    input  logic        enable,         // SW[1]

    input  logic        pixel_advance,
    input  logic        row_advance,

    input  logic        pixel_valid,
    input  logic [23:0] rgb_in,         // use green channel as luma

    output logic [23:0] rgb_out,
    output logic        pvalid_out
);
    // ── Line buffer ───────────────────────────────────────────────────────────
    logic [23:0] row0, row1, row2;

    line_buffer #(.WIDTH(320), .DATA_WIDTH(24)) lb (
        .clk(clk), .reset(reset),
        .pixel_advance(pixel_advance), .row_advance(row_advance),
        .din(rgb_in), .row0(row0), .row1(row1), .row2(row2)
    );

    // ── Column shift registers ────────────────────────────────────────────────
    logic [23:0] p_r0 [0:1];
    logic [23:0] p_r1 [0:1];
    logic [23:0] p_r2 [0:1];

    always_ff @(posedge clk) begin
        if (reset) begin
            p_r0[0]<='0; p_r0[1]<='0;
            p_r1[0]<='0; p_r1[1]<='0;
            p_r2[0]<='0; p_r2[1]<='0;
        end else if (pixel_advance) begin
            p_r0[1]<=p_r0[0]; p_r0[0]<=row0;
            p_r1[1]<=p_r1[0]; p_r1[0]<=row1;
            p_r2[1]<=p_r2[0]; p_r2[0]<=row2;
        end
    end

    // =========================================================================
    // PSEUDO-CODE:
    //
    // 3×3 window (use GREEN channel [15:8] as luma):
    //   g00 = p_r0[1][15:8]   g01 = p_r0[0][15:8]   g02 = row0[15:8]
    //   g10 = p_r1[1][15:8]   g11 = p_r1[0][15:8]   g12 = row1[15:8]
    //   g20 = p_r2[1][15:8]   g21 = p_r2[0][15:8]   g22 = row2[15:8]
    //
    // Sobel X gradient  (signed):
    //   Gx = (-g00 + g02) + 2*(-g10 + g12) + (-g20 + g22)
    //      = (g02 - g00) + 2*(g12 - g10) + (g22 - g20)
    //   Max |Gx| = 4 * 255 = 1020  → needs 11-bit signed result
    //
    // Sobel Y gradient  (signed):
    //   Gy = (-g00 - 2*g01 - g02) + (g20 + 2*g21 + g22)
    //      = (g20 - g00) + 2*(g21 - g01) + (g22 - g02)
    //   Max |Gy| = 1020
    //
    // Magnitude (approximate):
    //   mag_raw = |Gx| + |Gy|        // max = 2040, needs 12 bits
    //   mag     = (mag_raw > 255) ? 8'hFF : mag_raw[7:0]
    //
    // if (enable):   rgb_out = {mag, mag, mag}  (edge image in gray)
    // else:          rgb_out = rgb_in  (delayed 2 cycles for bypass)
    // =========================================================================

    // ── Luma extraction ───────────────────────────────────────────────────────
    logic [7:0] g00,g01,g02,g10,g11,g12,g20,g21,g22;
    assign g00 = p_r0[1][15:8]; assign g01 = p_r0[0][15:8]; assign g02 = row0[15:8];
    assign g10 = p_r1[1][15:8]; assign g11 = p_r1[0][15:8]; assign g12 = row1[15:8];
    assign g20 = p_r2[1][15:8]; assign g21 = p_r2[0][15:8]; assign g22 = row2[15:8];

    // ── Sobel gradients ───────────────────────────────────────────────────────
    logic signed [11:0] Gx, Gy;
    assign Gx = ($signed({4'b0, g02}) - $signed({4'b0, g00}))
              + ($signed({3'b0, g12, 1'b0}) - $signed({3'b0, g10, 1'b0}))
              + ($signed({4'b0, g22}) - $signed({4'b0, g20}));

    assign Gy = ($signed({4'b0, g20}) - $signed({4'b0, g00}))
              + ($signed({3'b0, g21, 1'b0}) - $signed({3'b0, g01, 1'b0}))
              + ($signed({4'b0, g22}) - $signed({4'b0, g02}));

    // ── Magnitude ─────────────────────────────────────────────────────────────
    logic [11:0] abs_Gx, abs_Gy;
    logic [11:0] mag_raw;
    logic [7:0]  mag;

    assign abs_Gx  = Gx[11] ? (~Gx + 1) : Gx;   // absolute value
    assign abs_Gy  = Gy[11] ? (~Gy + 1) : Gy;
    assign mag_raw = abs_Gx + abs_Gy;
    assign mag     = (mag_raw > 12'd255) ? 8'hFF : mag_raw[7:0];

    // ── Bypass delay + register ───────────────────────────────────────────────
    logic [23:0] rgb_d1, rgb_d2;
    logic        pv_d1, pv_d2;

    always_ff @(posedge clk) begin
        if (reset) begin
            rgb_out<=24'h0; pvalid_out<=1'b0;
            rgb_d1<=24'h0; rgb_d2<=24'h0;
            pv_d1<=1'b0; pv_d2<=1'b0;
        end else begin
            rgb_d1<=rgb_in; rgb_d2<=rgb_d1;
            pv_d1<=pixel_valid; pv_d2<=pv_d1;
            pvalid_out<=pv_d2;
            if (enable)
                rgb_out <= {mag, mag, mag};
            else
                rgb_out <= rgb_d2;
        end
    end

endmodule
