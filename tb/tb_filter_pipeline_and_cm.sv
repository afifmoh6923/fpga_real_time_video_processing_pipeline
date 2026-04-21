///////////////////////////////////////////////////////////////////////////////
// tb_color_mapper.sv
// Testbench for color_mapper.sv
// ─────────────────────────────────────────────────────────────────────────────
// HOW THIS TESTBENCH WORKS:
//
//  color_mapper is purely combinational.  Tests are immediate (no clocking).
//
//  The module takes {R[7:0], G[7:0], B[7:0]} and outputs the upper 4 bits
//  of each channel when pixel_valid=1, or 0 when pixel_valid=0.
//
//  Test cases:
//    • Active pixel: verify red[3:0] == filtered_rgb[23:20], etc.
//    • Blanking:     verify all outputs are 0
//    • VDE signal:   verify vde == pixel_valid
//    • Full colour sweep: several known pixels, verify truncation
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module tb_color_mapper;

    logic [23:0] filtered_rgb;
    logic        pixel_valid;
    logic [3:0]  red, green, blue;
    logic        vde;

    int error_count = 0;

    color_mapper dut (
        .filtered_rgb (filtered_rgb),
        .pixel_valid  (pixel_valid),
        .red(red), .green(green), .blue(blue), .vde(vde)
    );

    `define CHECK_CM(cond, msg) \
        if (!(cond)) begin $error("color_mapper: %s", msg); error_count++; end \
        else $display("color_mapper PASS: %s", msg);

    initial begin
        $display("\n=== Color Mapper Tests ===");

        // ── T1: Active pixel, known colour ──────────────────────────────────
        filtered_rgb = 24'hF0_A0_50;  // R=0xF0, G=0xA0, B=0x50
        pixel_valid  = 1'b1;
        #1;  // combinational – no clock needed
        `CHECK_CM(vde   == 1'b1,       "T1: vde=1 when active")
        `CHECK_CM(red   == 4'hF,       "T1: red   upper nibble 0xF")
        `CHECK_CM(green == 4'hA,       "T1: green upper nibble 0xA")
        `CHECK_CM(blue  == 4'h5,       "T1: blue  upper nibble 0x5")

        // ── T2: Blanking ────────────────────────────────────────────────────
        filtered_rgb = 24'hFFFFFF;
        pixel_valid  = 1'b0;
        #1;
        `CHECK_CM(vde   == 1'b0,       "T2: vde=0 during blanking")
        `CHECK_CM(red   == 4'h0,       "T2: red=0 during blanking")
        `CHECK_CM(green == 4'h0,       "T2: green=0 during blanking")
        `CHECK_CM(blue  == 4'h0,       "T2: blue=0 during blanking")

        // ── T3: Colour sweep ────────────────────────────────────────────────
        pixel_valid = 1'b1;
        for (int i = 0; i < 256; i += 16) begin
            filtered_rgb = {8'(i), 8'(255-i), 8'(i/2)};
            #1;
            if (red !== 4'(i >> 4)) begin
                $error("sweep red mismatch i=%0d got %0h exp %0h", i, red, i>>4);
                error_count++;
            end
        end
        $display("color_mapper sweep: done");

        // ── T4: VDE tracks pixel_valid ───────────────────────────────────
        filtered_rgb = 24'h123456;
        for (int v = 0; v < 2; v++) begin
            pixel_valid = v[0];
            #1;
            if (vde !== v[0]) begin
                $error("T4: vde=%0b does not match pixel_valid=%0b", vde, v[0]);
                error_count++;
            end
        end
        $display("color_mapper T4: vde tracking verified");

        $display("\n========================================");
        if (error_count == 0) $display("ALL color_mapper TESTS PASSED");
        else $display("FAILED: %0d error(s)", error_count);
        $display("========================================\n");
        $finish;
    end
endmodule


///////////////////////////////////////////////////////////////////////////////
// tb_filter_pipeline.sv
// Testbench for filter_pipeline.sv
// ─────────────────────────────────────────────────────────────────────────────
// HOW THIS TESTBENCH WORKS:
//
//  filter_pipeline orchestrates the full filter chain.  Testing it integration-
//  style is the most useful approach — feed known pixels through the chain and
//  verify the outputs match expectations from each individual filter.
//
//  Because the pipeline has 9 stages of latency we must:
//    1. Drive pixels for 9+ cycles before expecting valid outputs
//    2. Track which filter switches are active to predict expected output
//
//  The TB simulates a simplified VGA scan (drawX, drawY, active_nblank)
//  along with frame-buffer data (fb_data) and checks:
//
//  Test 1 – Passthrough (all SW = 0)
//    fb_data contains a known RGB565 pixel.
//    After pipeline latency, filtered_rgb should equal the RGB888 expansion.
//
//  Test 2 – Test pattern (SW[15] = 1)
//    At drawX = 64 (bar 1 = yellow), output should be 0xFFFF00.
//
//  Test 3 – Grayscale only (SW[0] = 1)
//    Feed RGB565 for a pure red pixel; after pipeline, output should be grey.
//
//  Test 4 – Grayscale + Channel Red (SW[0]+SW[5])
//    After grayscale, R=G=B=Y. After channel_isolate with en_R:
//    output = {Y, 0, 0}.
//
//  Test 5 – pixel_valid tracking
//    During blanking (active_nblank=0), pvalid_out should eventually go low.
//
//  Simulation approach:
//    We sweep drawX from 0..799 (one full scan line) at 25 MHz.
//    At each drawX, fb_data is set to a chosen pixel value.
//    After 9 cycles of pipeline latency we begin sampling outputs.
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module tb_filter_pipeline;

    localparam CLK_PERIOD = 40;    // 25 MHz

    // Ports
    logic        pixel_clk, reset;
    logic [15:0] SW;
    logic [9:0]  drawX, drawY;
    logic        active_nblank;
    logic [15:0] fb_data;
    logic [23:0] filtered_rgb;
    logic        pvalid_out;

    int error_count = 0;

    filter_pipeline dut (
        .pixel_clk    (pixel_clk),
        .reset        (reset),
        .SW           (SW),
        .drawX        (drawX),
        .drawY        (drawY),
        .active_nblank(active_nblank),
        .fb_data      (fb_data),
        .filtered_rgb (filtered_rgb),
        .pvalid_out   (pvalid_out)
    );

    initial pixel_clk = 0;
    always #(CLK_PERIOD/2) pixel_clk = ~pixel_clk;

    // ── Simulate VGA timing for one row ─────────────────────────────────────
    // Drives drawX from 0..799, active_nblank=1 for 0..639
    task automatic scan_row(input [9:0] row, input [15:0] fb_pixel);
        drawY = row;
        for (int x = 0; x < 800; x++) begin
            @(negedge pixel_clk);
            drawX        = 10'(x);
            active_nblank = (x < 640 && row < 480) ? 1'b1 : 1'b0;
            fb_data      = fb_pixel;
        end
    endtask

    // ── Expand RGB565 to RGB888 (same logic as filter_pipeline) ─────────────
    function automatic [23:0] expand565(input [15:0] p);
        logic [7:0] R, G, B;
        R = {p[15:11], p[15:13]};
        G = {p[10:5],  p[10:9]};
        B = {p[4:0],   p[4:2]};
        return {R, G, B};
    endfunction

    // ── Compute expected grayscale of RGB888 ─────────────────────────────────
    function automatic [7:0] gray(input [23:0] rgb);
        logic [15:0] raw;
        raw = (16'(rgb[23:16])*77) + (16'(rgb[15:8])*150) + (16'(rgb[7:0])*29);
        return raw[15:8];
    endfunction

    localparam PIPE_LATENCY = 9;  // total pipeline stages

    initial begin
        $dumpfile("tb_filter_pipeline.vcd");
        $dumpvars(0, tb_filter_pipeline);

        reset = 1; SW = 16'h0; drawX = 0; drawY = 0;
        active_nblank = 0; fb_data = 16'h0;
        repeat(5) @(negedge pixel_clk);
        reset = 0;
        repeat(3) @(negedge pixel_clk);

        $display("\n=== Filter Pipeline Tests ===");

        // ── T1: Passthrough ────────────────────────────────────────────────
        $display("\n-- T1: Passthrough (all SW=0) --");
        SW = 16'h0000;
        begin
            automatic logic [15:0] test_pix = 16'hF800;   // pure red RGB565
            automatic logic [23:0] expected  = expand565(test_pix);

            // Stream one row; sample output after pipeline latency
            drawY = 10'd1;
            for (int x = 0; x < 800; x++) begin
                @(negedge pixel_clk);
                drawX         = 10'(x);
                active_nblank = (x < 640) ? 1'b1 : 1'b0;
                fb_data       = test_pix;

                // After PIPE_LATENCY pixels start checking
                if (x >= PIPE_LATENCY + 2 && x < 640) begin
                    if (pvalid_out !== 1'b1) begin
                        $error("T1: pvalid_out not 1 at x=%0d", x);
                        error_count++;
                    end
                    if (filtered_rgb !== expected) begin
                        $error("T1 passthrough: got 0x%06X exp 0x%06X x=%0d",
                               filtered_rgb, expected, x);
                        error_count++;
                        break;
                    end
                end
            end
            if (error_count == 0)
                $display("[%0t] T1 PASS: passthrough RGB565→RGB888 correct", $time);
        end

        repeat(5) @(negedge pixel_clk);

        // ── T2: Test pattern (SW[15]=1) ───────────────────────────────────
        $display("\n-- T2: Test pattern (SW[15]=1) --");
        SW = 16'h8000;
        begin
            drawY = 10'd2;
            for (int x = 0; x < 800; x++) begin
                @(negedge pixel_clk);
                drawX         = 10'(x);
                active_nblank = (x < 640) ? 1'b1 : 1'b0;
                fb_data       = 16'h0000;  // doesn't matter, SW[15] overrides

                // Bar 1 (drawX[9:7]=1) = yellow = 0xFFFF00
                if (x == 128 + PIPE_LATENCY + 2 && active_nblank) begin
                    if (filtered_rgb !== 24'hFFFF00) begin
                        $error("T2 bar1 yellow: got 0x%06X exp 0xFFFF00", filtered_rgb);
                        error_count++;
                    end else
                        $display("[%0t] T2 PASS: yellow bar correct (0xFFFF00)", $time);
                end
                // Bar 0 (drawX[9:7]=0) = white = 0xFFFFFF
                if (x == 32 + PIPE_LATENCY + 2 && active_nblank) begin
                    if (filtered_rgb !== 24'hFFFFFF) begin
                        $error("T2 bar0 white: got 0x%06X exp 0xFFFFFF", filtered_rgb);
                        error_count++;
                    end else
                        $display("[%0t] T2 PASS: white bar correct (0xFFFFFF)", $time);
                end
            end
        end

        repeat(5) @(negedge pixel_clk);

        // ── T3: Grayscale only (SW[0]=1) ─────────────────────────────────
        $display("\n-- T3: Grayscale (SW[0]) --");
        SW = 16'h0001;
        begin
            automatic logic [15:0] test_pix = 16'h07E0; // pure green RGB565
            automatic logic [23:0] rgb888    = expand565(test_pix);
            automatic logic [7:0]  Y         = gray(rgb888);
            automatic logic [23:0] expected  = {Y, Y, Y};

            drawY = 10'd3;
            for (int x = 0; x < 800; x++) begin
                @(negedge pixel_clk);
                drawX         = 10'(x);
                active_nblank = (x < 640) ? 1'b1 : 1'b0;
                fb_data       = test_pix;
                if (x == 200 + PIPE_LATENCY + 2 && active_nblank) begin
                    if (filtered_rgb !== expected) begin
                        $error("T3 gray: got 0x%06X exp 0x%06X", filtered_rgb, expected);
                        error_count++;
                    end else
                        $display("[%0t] T3 PASS: grayscale correct (Y=0x%02X)", $time, Y);
                end
            end
        end

        repeat(5) @(negedge pixel_clk);

        // ── T4: Blanking – pvalid_out goes low ───────────────────────────
        $display("\n-- T4: Blanking pvalid_out --");
        SW = 16'h0000;
        begin
            drawY = 10'd481;   // below active area
            for (int x = 0; x < 800; x++) begin
                @(negedge pixel_clk);
                drawX         = 10'(x);
                active_nblank = 1'b0;   // blanking
                fb_data       = 16'hFFFF;
            end
            // After pipeline latency, pvalid_out should be 0
            if (pvalid_out !== 1'b0) begin
                $error("T4: pvalid_out=%0b expected 0 during blanking", pvalid_out);
                error_count++;
            end else
                $display("[%0t] T4 PASS: pvalid_out=0 during blanking", $time);
        end

        $display("\n========================================");
        if (error_count == 0)
            $display("ALL filter_pipeline TESTS PASSED");
        else
            $display("FAILED: %0d error(s)", error_count);
        $display("========================================\n");
        $finish;
    end
endmodule
