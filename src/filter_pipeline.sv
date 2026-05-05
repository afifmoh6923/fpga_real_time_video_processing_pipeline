///////////////////////////////////////////////////////////////////////////////
// filter_pipeline.sv
// ECE 385 Final Project – Real-Time FPGA Video Processing Pipeline
//
// FILTER PIPELINE ORCHESTRATOR
// ─────────────────────────────────────────────────────────────────────────────
// This module:
//   1. Expands the 16-bit RGB565 frame-buffer pixel to 24-bit RGB888
//   2. Optionally substitutes a colour-bar test pattern (SW[15])
//   3. Chains all filter stages in order:
//        brightness_contrast → channel_isolate → grayscale →
//        box_blur → sharpen → edge_detect
//   4. Generates pixel_advance and row_advance control signals for the
//      neighbourhood filters (line buffers).
//
// Pixel-doubling:
//   Camera QVGA (320×240) is displayed pixel-doubled onto 640×480 VGA.
//   Each camera pixel occupies a 2×2 block of display pixels.
//   The neighbourhood filters must only advance once per camera pixel
//   (not once per display pixel) otherwise they would process each row twice.
//
// pixel_advance:
//   Asserted for ONE pixel_clk cycle when the scan position crosses into a
//   new camera column.  This happens every 2 display pixels horizontally,
//   specifically when drawX transitions from an odd value to an even value
//   (i.e. when drawX[0] == 0, within active video).
//
// row_advance:
//   Asserted for ONE pixel_clk cycle at the first pixel of each new camera
//   row (drawX == 0 and drawY is even and within active video).
//
// Pipeline depth totals:
//   brightness_contrast : 1
//   channel_isolate     : 1
//   grayscale           : 1
//   box_blur            : 2  (BRAM + accumulate)
//   sharpen             : 2
//   edge_detect         : 2
//   Total               : 9 cycles
//
//   At 25 MHz and 640 pixels/row this is 9/25e6 s ≈ 360 ns
//   → sub-pixel delay, acceptable for real-time display.
//   All bypass paths are register-matched inside each module.
///////////////////////////////////////////////////////////////////////////////

module filter_pipeline (
    input  logic        pixel_clk,
    input  logic        reset,

    input  logic [15:0] SW,             // synchronised switch bus

    // VGA scan position (from vga_controller – note lowercase signal names)
    input  logic [9:0]  drawX,
    input  logic [9:0]  drawY,
    input  logic        active_nblank,  // HIGH = active video

    // Frame-buffer read data (RGB565, 1-cycle BRAM latency already applied)
    input  logic [15:0] fb_data,

    // Filtered output
    output logic [23:0] filtered_rgb,
    output logic        pvalid_out
);


    // =========================================================================
    // STEP 2 – RGB565 → RGB888 EXPANSION
    // =========================================================================
    // RGB565 layout: [15:11]=R5  [10:5]=G6  [4:0]=B5
    // Expand to 8-bit per channel by replicating the MSBs:
    //   R8 = {R5, R5[4:2]}   (replicate top 3 bits of R5)
    //   G8 = {G6, G6[5:4]}   (replicate top 2 bits of G6)
    //   B8 = {B5, B5[4:2]}   (replicate top 3 bits of B5)
    //
    // PSEUDO-CODE:
    //   R8 = {fb_data[15:11], fb_data[15:13]}
    //   G8 = {fb_data[10:5],  fb_data[10:9]}
    //   B8 = {fb_data[4:0],   fb_data[4:2]}
    //   rgb888 = {R8, G8, B8}
    logic [7:0] R8, G8, B8;
    assign R8 = {fb_data[15:11], fb_data[15:13]};
    assign G8 = {fb_data[10:5],  fb_data[10:9]};
    assign B8 = {fb_data[4:0],   fb_data[4:2]};

    logic [23:0] rgb888;
    assign rgb888 = {R8, G8, B8};

    // =========================================================================
    // STEP 3 – TEST PATTERN OVERRIDE (SW[15])
    // =========================================================================
    // 8 vertical colour bars based on drawX[9:7] (upper 3 display bits)
    // PSEUDO-CODE:
    //   case (drawX[9:7]):
    //     0: White   (FFFFFF)
    //     1: Yellow  (FFFF00)
    //     2: Cyan    (00FFFF)
    //     3: Green   (00FF00)
    //     4: Magenta (FF00FF)
    //     5: Red     (FF0000)
    //     6: Blue    (0000FF)
    //     7: Black   (000000)
    logic [23:0] test_pattern;
    always_comb begin
        case (drawX/80)
            3'd0: test_pattern = 24'hFFFFFF;
            3'd1: test_pattern = 24'hFFFF00;
            3'd2: test_pattern = 24'h00FFFF;
            3'd3: test_pattern = 24'h00FF00;
            3'd4: test_pattern = 24'hFF00FF;
            3'd5: test_pattern = 24'hFF0000;
            3'd6: test_pattern = 24'h0000FF;
            3'd7: test_pattern = 24'h000000;
            default: test_pattern = 24'h000000;
        endcase
    end

    // =========================================================================
    // STEP 1 – CONTROL SIGNAL GENERATION
    // =========================================================================
    
    // Define the centered 320x240 boundary
    logic in_window;
    assign in_window = (drawX >= 10'd160) && (drawX < 10'd480) && 
                       (drawY >= 10'd120) && (drawY < 10'd360);

    // Tell the filters to advance every single pixel, but ONLY inside the window
    logic pixel_advance;
    logic row_advance;

    assign pixel_advance = active_nblank && in_window;
    
    // Pulse once at the exact start of the active camera row (Column 160)
    assign row_advance   = active_nblank && in_window && (drawX == 10'd160);

    // ... (Keep STEP 2 and the test_pattern case statement exactly the same) ...

    // Update STEP 3: Draw black if we are outside the 320x240 window
    logic [23:0] source_rgb;
    assign source_rgb = SW[15] ? (active_nblank ? test_pattern : 24'h000000) : 
                                 (in_window ? rgb888 : 24'h000000);
    // pixel_valid: active video indicator
    logic pixel_valid;
    assign pixel_valid = active_nblank;

    // =========================================================================
    // STEP 4 – FILTER CHAIN INSTANTIATION
    // =========================================================================
    // Stage outputs wired in series: s1_out → s2_out → ... → s6_out

    // ── Stage 1: Brightness / Contrast ───────────────────────────────────────
    logic [23:0] s1_out; logic s1_valid;
    brightness_contrast s1 (
        .clk          (pixel_clk),  .reset        (reset),
        .en_brightness(SW[3]),      .en_contrast  (SW[4]),
        .pixel_valid  (pixel_valid),.rgb_in       (source_rgb),
        .rgb_out      (s1_out),     .pvalid_out   (s1_valid)
    );

    // ── Stage 2: Channel Isolation ────────────────────────────────────────────
    logic [23:0] s2_out; logic s2_valid;
    channel_isolate s2 (
        .clk        (pixel_clk),  .reset      (reset),
        .en_R       (SW[5]),      .en_G       (SW[6]),     .en_B(SW[7]),
        .pixel_valid(s1_valid),   .rgb_in     (s1_out),
        .rgb_out    (s2_out),     .pvalid_out (s2_valid)
    );

    // ── Stage 3: Grayscale ───────────────────────────────────────────────────
    logic [23:0] s3_out; logic s3_valid;
    grayscale s3 (
        .clk        (pixel_clk),  .reset      (reset),
        .enable     (1'b0),
        .pixel_valid(s2_valid),   .rgb_in     (s2_out),
        .rgb_out    (s3_out),     .pvalid_out (s3_valid)
    );

    // ── Stage 4: Box Blur ─────────────────────────────────────────────────────
    logic [23:0] s4_out; logic s4_valid;
    box_blur s4 (
        .clk          (pixel_clk), .reset        (reset),
        .enable       (SW[2]),
        .pixel_advance(pixel_advance), .row_advance(row_advance),
        .pixel_valid  (s3_valid),  .rgb_in       (s3_out),
        .rgb_out      (s4_out),    .pvalid_out   (s4_valid)
    );

    // ── Stage 5: Sharpen ──────────────────────────────────────────────────────
    logic [23:0] s5_out; logic s5_valid;
    sharpen s5 (
        .clk          (pixel_clk), .reset        (reset),
        .enable       (SW[8]),
        .pixel_advance(pixel_advance), .row_advance(row_advance),
        .pixel_valid  (s4_valid),  .rgb_in       (s4_out),
        .rgb_out      (s5_out),    .pvalid_out   (s5_valid)
    );

    // ── Stage 6: Edge Detection ───────────────────────────────────────────────
    logic [23:0] s6_out; logic s6_valid;
    edge_detect s6 (
        .clk          (pixel_clk), .reset        (reset),
        .enable       (SW[1]),
        .pixel_advance(pixel_advance), .row_advance(row_advance),
        .pixel_valid  (s5_valid),  .rgb_in       (s5_out),
        .rgb_out      (s6_out),    .pvalid_out   (s6_valid)
    );

    // =========================================================================
    // STEP 5 – OUTPUT ASSIGNMENT
    // =========================================================================
    logic [8:0] in_window_pipe;
    
    always_ff @(posedge pixel_clk) begin
        if (reset) begin
            in_window_pipe <= 9'b0;
        end else begin
            in_window_pipe <= {in_window_pipe[7:0], in_window};
        end
    end

    // Force perfectly black pixels outside the window
    assign filtered_rgb = in_window_pipe[8] ? s6_out : 24'h000000;
    assign pvalid_out   = s6_valid;

endmodule
