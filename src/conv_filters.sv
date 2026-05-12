
// Contains three convolution-based filter modules:
//   1. silhoutte     – strong unsharp mask (8-neighbour, 9× centre)
//   2. edge_detect – Sobel with true luma + threshold for crisp edges
//   3. emboss      – directional emboss effect (NEW, SW[9])
//   4. median_3x3  – noise reduction via median filter (NEW, SW[10])
//
// All modules share the same interface:
//   clk, reset, enable, pixel_advance, row_advance,
//   pixel_valid, rgb_in[23:0], rgb_out[23:0], pvalid_out
//
// All use line_buffer.sv for 3-row neighbourhood access.
// Pipeline depth: 2 clock cycles (matches original).




// silhoutte
module silhoutte (
    input  logic        clk,
    input  logic        reset,
    input  logic        enable,

    input  logic        pixel_advance,
    input  logic        row_advance,

    input  logic        pixel_valid,
    input  logic [23:0] rgb_in,

    output logic [23:0] rgb_out,
    output logic        pvalid_out
);
    logic [23:0] row0, row1, row2;
    line_buffer #(.WIDTH(320), .DATA_WIDTH(24)) lb (
        .clk(clk), .reset(reset),
        .pixel_advance(pixel_advance), .row_advance(row_advance),
        .din(rgb_in), .row0(row0), .row1(row1), .row2(row2)
    );

    logic [23:0] p_r0[0:1], p_r1[0:1], p_r2[0:1];
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

    // Full 3x3 window - all 9 pixels per channel
    // Centre = p_r1[0], 8 neighbours = everything else
    logic [7:0] cR,cG,cB;   // centre
    logic [7:0] n0R,n1R,n2R,n3R,n4R,n5R,n6R,n7R; // 8 neighbours R
    logic [7:0] n0G,n1G,n2G,n3G,n4G,n5G,n6G,n7G;
    logic [7:0] n0B,n1B,n2B,n3B,n4B,n5B,n6B,n7B;

    // Centre
    assign {cR,cG,cB} = p_r1[0];
    // Row above: top-left, top, top-right
    assign {n0R,n0G,n0B} = p_r0[1]; // top-left
    assign {n1R,n1G,n1B} = p_r0[0]; // top
    assign {n2R,n2G,n2B} = row0;    // top-right
    // Same row: left, right
    assign {n3R,n3G,n3B} = p_r1[1]; // left
    assign {n4R,n4G,n4B} = row1;    // right
    // Row below: bottom-left, bottom, bottom-right
    assign {n5R,n5G,n5B} = p_r2[1]; // bottom-left
    assign {n6R,n6G,n6B} = p_r2[0]; // bottom
    assign {n7R,n7G,n7B} = row2;    // bottom-right

    // neighbour sum (max 8*255=2040, 12 bits)
    logic [11:0] sumNR, sumNG, sumNB;
    assign sumNR = n0R+n1R+n2R+n3R+n4R+n5R+n6R+n7R;
    assign sumNG = n0G+n1G+n2G+n3G+n4G+n5G+n6G+n7G;
    assign sumNB = n0B+n1B+n2B+n3B+n4B+n5B+n6B+n7B;

    // 9*centre - sum_neighbours (signed 13-bit: max 9*255=2295, min -2040)
    logic signed [12:0] shR, shG, shB;
    assign shR = $signed({1'b0, cR} * 4'd9) - $signed({1'b0, sumNR});
    assign shG = $signed({1'b0, cG} * 4'd9) - $signed({1'b0, sumNG});
    assign shB = $signed({1'b0, cB} * 4'd9) - $signed({1'b0, sumNB});

    function automatic [7:0] clamp8(input logic signed [12:0] v);
        if (v < 0)        clamp8 = 8'h00;
        else if (v > 255) clamp8 = 8'hFF;
        else              clamp8 = v[7:0];
    endfunction

    logic [23:0] rgb_d1, rgb_d2;
    logic pv_d1,  pv_d2;
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
                rgb_out <= {clamp8(shR), clamp8(shG), clamp8(shB)};
            else
                rgb_out <= rgb_d2;
        end
    end
endmodule



// edge_detect
module edge_detect (
    input  logic        clk,
    input  logic        reset,
    input  logic        enable,

    input  logic        pixel_advance,
    input  logic        row_advance,

    input  logic        pixel_valid,
    input  logic [23:0] rgb_in,

    output logic [23:0] rgb_out,
    output logic        pvalid_out
);
    // Increased threshold to ignore background "static"
    localparam [8:0] THRESHOLD = 9'd180; 

    logic [23:0] row0, row1, row2;
    line_buffer #(.WIDTH(320), .DATA_WIDTH(24)) lb (
        .clk(clk), .reset(reset),
        .pixel_advance(pixel_advance), .row_advance(row_advance),
        .din(rgb_in), .row0(row0), .row1(row1), .row2(row2)
    );

    logic [23:0] p_r0[0:1], p_r1[0:1], p_r2[0:1];
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

    // Weighs Red at 80% to avoid Green/Blue noise sparks
    function automatic [7:0] clean_luma(input logic [23:0] px);
        logic [15:0] y;
        y = (8'd200 * px[23:16])  // 80% Red (Cleanest)
          + (8'd40  * px[15:8])   // 15% Green
          + (8'd16  * px[7:0]);   // 5%  Blue
        clean_luma = y[15:8];
    endfunction

    logic [7:0] g00,g01,g02, g10,g11,g12, g20,g21,g22;
    assign g00 = clean_luma(p_r0[1]); assign g01 = clean_luma(p_r0[0]); assign g02 = clean_luma(row0);
    assign g10 = clean_luma(p_r1[1]); assign g11 = clean_luma(p_r1[0]); assign g12 = clean_luma(row1);
    assign g20 = clean_luma(p_r2[1]); assign g21 = clean_luma(p_r2[0]); assign g22 = clean_luma(row2);

    // Sobel gradients
    logic signed [11:0] Gx, Gy;
    assign Gx = ($signed({4'b0,g02}) - $signed({4'b0,g00}))
              + ($signed({3'b0,g12,1'b1}) - $signed({3'b0,g10,1'b1})) // Weighted center
              + ($signed({4'b0,g22}) - $signed({4'b0,g20}));
    assign Gy = ($signed({4'b0,g20}) - $signed({4'b0,g00}))
              + ($signed({3'b0,g21,1'b1}) - $signed({3'b0,g01,1'b1}))
              + ($signed({4'b0,g22}) - $signed({4'b0,g02}));

    logic [11:0] abs_grad;
    assign abs_grad = (Gx[11] ? (~Gx + 1) : Gx) + (Gy[11] ? (~Gy + 1) : Gy);

    always_ff @(posedge clk) begin
        if (reset) begin
            rgb_out    <= 24'h0;
            pvalid_out <= 1'b0;
        end else begin
            pvalid_out <= pixel_valid;
            if (enable)
                // Draw white only for VERY strong object edges
                rgb_out <= (abs_grad > THRESHOLD) ? 24'hFFFFFF : 24'h000000;
            else
                rgb_out <= rgb_in;
        end
    end
endmodule



// emboss  
// ─────────────────────────────────────────────────────────────────────────────
// Creates a raised 3D relief effect by applying a directional gradient kernel:
//
//   K = [-2 -1  0]
//       [-1  1  1]
//       [ 0  1  2]
//
// Result = K*image + 128  (bias to mid-grey so both directions show)
// Negative result → dark shadow; positive → bright highlight.
// Output is grayscale (luma-based) to emphasise the relief effect.
// Pipeline depth: 2 cycles.
module emboss (
    input  logic        clk,
    input  logic        reset,
    input  logic        enable,         // SW[9]

    input  logic        pixel_advance,
    input  logic        row_advance,

    input  logic        pixel_valid,
    input  logic [23:0] rgb_in,

    output logic [23:0] rgb_out,
    output logic        pvalid_out
);
    logic [23:0] row0, row1, row2;
    line_buffer #(.WIDTH(320), .DATA_WIDTH(24)) lb (
        .clk(clk), .reset(reset),
        .pixel_advance(pixel_advance), .row_advance(row_advance),
        .din(rgb_in), .row0(row0), .row1(row1), .row2(row2)
    );

    logic [23:0] p_r0[0:1], p_r1[0:1], p_r2[0:1];
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

    function automatic [7:0] luma(input logic [23:0] px);
        logic [15:0] y;
        y = (8'd77 * px[23:16]) + (8'd150 * px[15:8]) + (8'd29 * px[7:0]);
        luma = y[15:8];
    endfunction

    logic [7:0] g00,g01,g02, g10,g11,g12, g20,g21,g22;
    assign g00=luma(p_r0[1]); assign g01=luma(p_r0[0]); assign g02=luma(row0);
    assign g10=luma(p_r1[1]); assign g11=luma(p_r1[0]); assign g12=luma(row1);
    assign g20=luma(p_r2[1]); assign g21=luma(p_r2[0]); assign g22=luma(row2);

    // Emboss kernel:  [-2 -1 0 / -1 1 1 / 0 1 2]
    // emb = -2*g00 - g01 - g10 + g11 + g12 + g21 + 2*g22 + 128
    logic signed [11:0] emb;
    assign emb = -$signed({4'b0,g00,1'b0})   // -2*g00
                 - $signed({4'b0,g01})         // -g01
                 - $signed({4'b0,g10})         // -g10
                 + $signed({4'b0,g11})         // +g11
                 + $signed({4'b0,g12})         // +g12
                 + $signed({4'b0,g21})         // +g21
                 + $signed({3'b0,g22,1'b0})    // +2*g22
                 + 12'sd128;                   // bias to mid-grey

    logic [7:0] emb_out;
    assign emb_out = emb[11] ? 8'h00 : (emb > 255 ? 8'hFF : emb[7:0]);

    logic [23:0] rgb_d1, rgb_d2;
    logic        pv_d1,  pv_d2;
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
                rgb_out <= {emb_out, emb_out, emb_out};
            else
                rgb_out <= rgb_d2;
        end
    end
endmodule