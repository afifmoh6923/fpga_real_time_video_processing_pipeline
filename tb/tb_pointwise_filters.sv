///////////////////////////////////////////////////////////////////////////////
// tb_pointwise_filters.sv
// Testbenches for: grayscale, brightness_contrast, channel_isolate
// ─────────────────────────────────────────────────────────────────────────────
// HOW THESE TESTBENCHES WORK:
//
//  All three modules are pointwise (no line buffers) with 1-cycle pipeline
//  latency.  Each test drives an input pixel and reads the output one clock
//  cycle later.
//
//  GRAYSCALE (tb_grayscale module)
//  ─────────
//  Formula: Y = (77*R + 150*G + 29*B) >> 8
//  Coefficients verified to sum to 256 (correct normalisation).
//
//  Cases tested:
//    • Pure white (R=G=B=255) → Y should be 255
//    • Pure black (R=G=B=0)   → Y should be 0
//    • Pure red   (255,0,0)   → Y = (77*255)>>8 = 76
//    • Pure green (0,255,0)   → Y = (150*255)>>8 = 149
//    • Pure blue  (0,0,255)   → Y = (29*255)>>8  = 28
//    • Mixed      (100,150,200)→ compute expected, compare ±1 (fixed-point)
//    • Bypass (enable=0)      → rgb_out == rgb_in exactly
//    • pixel_valid=0          → pvalid_out should be 0 next cycle
//
//  BRIGHTNESS / CONTRAST (tb_brightness_contrast module)
//  ──────────────────────
//  Contrast: val_out = val_in + (val_in >> 1)   (≈ 1.5×)
//  Brightness: val_out = val_in + 32
//  Saturation: clamp to 255
//
//  Cases tested:
//    • Brightness only: (100,100,100) → (132,132,132) each channel
//    • Contrast only:   (100,100,100) → (150,150,150) each channel
//    • Both:            (100,100,100) → contrast first=150, then +32=182
//    • Saturation:      (240,240,240) + brightness → clamp to 255
//    • Bypass (both disabled) → passthrough
//
//  CHANNEL ISOLATION (tb_channel_isolate module)
//  ──────────────────
//  Cases tested:
//    • en_R only:  output = {R, 0, 0}
//    • en_G only:  output = {0, G, 0}
//    • en_B only:  output = {0, 0, B}
//    • en_R+en_G:  priority R wins → {R, 0, 0}
//    • none:       passthrough
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

// =============================================================================
// GRAYSCALE TESTBENCH
// =============================================================================
module tb_grayscale;

    localparam CLK_PERIOD = 40;
    logic        clk, reset, enable, pixel_valid, pvalid_out;
    logic [23:0] rgb_in, rgb_out;
    int error_count = 0;

    grayscale dut (
        .clk(clk), .reset(reset), .enable(enable),
        .pixel_valid(pixel_valid), .rgb_in(rgb_in),
        .rgb_out(rgb_out), .pvalid_out(pvalid_out)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ── Helper: expected Y from BT.601 integer formula ─────────────────────
    function automatic [7:0] expected_Y(input [7:0] r, input [7:0] g, input [7:0] b);
        logic [15:0] raw;
        raw = (16'(r) * 77) + (16'(g) * 150) + (16'(b) * 29);
        return raw[15:8];   // >> 8
    endfunction

    // ── Helper: drive one pixel and read result after 1 cycle ─────────────
    task automatic drive_and_check(
        input [7:0]   r, g, b,
        input         en,
        input [23:0]  expected,
        input string  label
    );
        @(negedge clk);
        rgb_in       = {r, g, b};
        enable       = en;
        pixel_valid  = 1'b1;
        @(posedge clk);
        @(negedge clk);   // outputs are registered; stable after negedge
        if (rgb_out !== expected) begin
            $error("grayscale %s: got 0x%06X expected 0x%06X", label, rgb_out, expected);
            error_count++;
        end else
            $display("[%0t] grayscale PASS: %s → 0x%06X", $time, label, rgb_out);
        if (pvalid_out !== 1'b1) begin
            $error("grayscale %s: pvalid_out not asserted", label);
            error_count++;
        end
    endtask

    initial begin
        reset = 1; enable = 1; pixel_valid = 0; rgb_in = 24'h0;
        repeat(4) @(negedge clk);
        reset = 0;
        repeat(2) @(negedge clk);

        $display("\n=== Grayscale Tests ===");

        // White
        begin automatic logic [7:0] y = expected_Y(255,255,255);
        drive_and_check(255,255,255, 1, {y,y,y}, "white"); end

        // Black
        drive_and_check(0,0,0, 1, 24'h0, "black");

        // Pure red
        begin automatic logic [7:0] y = expected_Y(255,0,0);
        drive_and_check(255,0,0, 1, {y,y,y}, "pure red"); end

        // Pure green
        begin automatic logic [7:0] y = expected_Y(0,255,0);
        drive_and_check(0,255,0, 1, {y,y,y}, "pure green"); end

        // Pure blue
        begin automatic logic [7:0] y = expected_Y(0,0,255);
        drive_and_check(0,0,255, 1, {y,y,y}, "pure blue"); end

        // Mixed
        begin automatic logic [7:0] y = expected_Y(100,150,200);
        drive_and_check(100,150,200, 1, {y,y,y}, "mixed"); end

        // Bypass (enable=0): output must equal input exactly
        drive_and_check(180,90,45, 0, 24'h{8'd180,8'd90,8'd45}, "bypass");

        // pixel_valid=0: pvalid_out must be 0
        @(negedge clk);
        pixel_valid = 0; rgb_in = 24'hFFFFFF; enable = 1;
        @(posedge clk);
        @(negedge clk);
        if (pvalid_out !== 1'b0) begin
            $error("grayscale: pvalid_out should be 0 when pixel_valid=0");
            error_count++;
        end else
            $display("[%0t] grayscale PASS: pvalid_out=0 when invalid", $time);

        $display("Grayscale: %0d error(s)", error_count);
        $finish;
    end
endmodule


// =============================================================================
// BRIGHTNESS / CONTRAST TESTBENCH
// =============================================================================
module tb_brightness_contrast;

    localparam CLK_PERIOD = 40;
    logic        clk, reset, en_brightness, en_contrast, pixel_valid, pvalid_out;
    logic [23:0] rgb_in, rgb_out;
    int error_count = 0;

    brightness_contrast dut (
        .clk(clk), .reset(reset),
        .en_brightness(en_brightness), .en_contrast(en_contrast),
        .pixel_valid(pixel_valid), .rgb_in(rgb_in),
        .rgb_out(rgb_out), .pvalid_out(pvalid_out)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Compute expected value: contrast then brightness, with clamp
    function automatic [7:0] expected_ch(
        input [7:0] v,
        input       do_contrast,
        input       do_bright
    );
        logic [8:0] tmp;
        tmp = {1'b0, v};
        if (do_contrast) tmp = tmp + {2'b0, v[7:1]};        // +v/2 (1.5x)
        if (tmp > 9'd255) tmp = 9'd255;
        if (do_bright)   tmp = tmp + 9'd32;
        if (tmp > 9'd255) tmp = 9'd255;
        return tmp[7:0];
    endfunction

    task automatic drive_check(
        input [7:0] r, g, b,
        input       ec, eb,
        input string label
    );
        logic [23:0] exp;
        exp = {expected_ch(r,ec,eb), expected_ch(g,ec,eb), expected_ch(b,ec,eb)};
        @(negedge clk);
        rgb_in = {r,g,b}; en_contrast=ec; en_brightness=eb; pixel_valid=1;
        @(posedge clk); @(negedge clk);
        if (rgb_out !== exp) begin
            $error("bc %s: got 0x%06X expected 0x%06X (r=%0d,g=%0d,b=%0d ec=%0b eb=%0b)",
                   label, rgb_out, exp, r, g, b, ec, eb);
            error_count++;
        end else
            $display("[%0t] bc PASS: %s", $time, label);
    endtask

    initial begin
        reset=1; en_brightness=0; en_contrast=0; pixel_valid=0; rgb_in=24'h0;
        repeat(4) @(negedge clk); reset=0; repeat(2) @(negedge clk);

        $display("\n=== Brightness/Contrast Tests ===");

        drive_check(100,100,100, 0,1, "brightness only");
        drive_check(100,100,100, 1,0, "contrast only");
        drive_check(100,100,100, 1,1, "both");
        drive_check(240,240,240, 0,1, "brightness saturation clamp");
        drive_check(200,200,200, 1,0, "contrast saturation clamp");
        drive_check(128, 64, 32, 0,0, "bypass");

        // Asymmetric channels
        drive_check(200, 50, 10, 1,1, "asymmetric both");
        drive_check(0,   0,  0,  1,1, "black both enabled");
        drive_check(255,255,255, 1,1, "white both enabled – full clamp");

        $display("Brightness/Contrast: %0d error(s)", error_count);
        $finish;
    end
endmodule


// =============================================================================
// CHANNEL ISOLATION TESTBENCH
// =============================================================================
module tb_channel_isolate;

    localparam CLK_PERIOD = 40;
    logic        clk, reset, en_R, en_G, en_B, pixel_valid, pvalid_out;
    logic [23:0] rgb_in, rgb_out;
    int error_count = 0;

    channel_isolate dut (
        .clk(clk), .reset(reset),
        .en_R(en_R), .en_G(en_G), .en_B(en_B),
        .pixel_valid(pixel_valid), .rgb_in(rgb_in),
        .rgb_out(rgb_out), .pvalid_out(pvalid_out)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    task automatic test_iso(
        input [7:0]  r, g, b,
        input        er, eg, eb,
        input [23:0] expected,
        input string label
    );
        @(negedge clk);
        rgb_in = {r,g,b}; en_R=er; en_G=eg; en_B=eb; pixel_valid=1;
        @(posedge clk); @(negedge clk);
        if (rgb_out !== expected) begin
            $error("iso %s: got 0x%06X exp 0x%06X", label, rgb_out, expected);
            error_count++;
        end else
            $display("[%0t] iso PASS: %s → 0x%06X", $time, label, rgb_out);
    endtask

    initial begin
        reset=1; en_R=0; en_G=0; en_B=0; pixel_valid=0; rgb_in=24'h0;
        repeat(4) @(negedge clk); reset=0; repeat(2) @(negedge clk);

        $display("\n=== Channel Isolation Tests ===");

        test_iso(180, 90, 45,  1,0,0,  24'hB4_00_00,  "R only");
        test_iso(180, 90, 45,  0,1,0,  24'h00_5A_00,  "G only");
        test_iso(180, 90, 45,  0,0,1,  24'h00_00_2D,  "B only");
        test_iso(180, 90, 45,  0,0,0,  24'hB4_5A_2D,  "bypass (none)");
        // Priority: R > G when both set
        test_iso(180, 90, 45,  1,1,0,  24'hB4_00_00,  "R+G → R wins");
        test_iso(180, 90, 45,  0,1,1,  24'h00_5A_00,  "G+B → G wins");
        test_iso(180, 90, 45,  1,0,1,  24'hB4_00_00,  "R+B → R wins");
        test_iso(180, 90, 45,  1,1,1,  24'hB4_00_00,  "all → R wins");
        // Edge: zero values
        test_iso(0,   0,  0,  1,0,0,  24'h000000,    "R only, black");
        test_iso(255,255,255, 0,1,0,  24'h00FF00,    "G only, white");

        $display("Channel Isolation: %0d error(s)", error_count);
        $finish;
    end
endmodule
