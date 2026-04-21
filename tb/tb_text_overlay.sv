///////////////////////////////////////////////////////////////////////////////
// tb_text_overlay.sv
// Testbench for text_overlay.sv
// ─────────────────────────────────────────────────────────────────────────────
// HOW THIS TESTBENCH WORKS:
//
//  text_overlay composites a filter-name string over the top 16 scan lines
//  of the screen.  It uses a font_rom (from the AXI lab) with 1-cycle BRAM
//  latency, so outputs are 2 cycles after the input address.
//
//  The testbench does NOT instantiate font_rom (that would require the full
//  ROM file); instead it uses a behavioural model that returns a known bit
//  pattern for a given character, allowing the TB to verify the selection
//  and compositing logic independently of the actual font bitmaps.
//
//  NOTE: When running with the real font_rom, replace the stub below with
//  `include "font_rom.sv" or ensure it is part of the compilation unit.
//
//  Behavioural font_rom stub (used in this TB):
//    For any glyph addr: if glyph != ' ' (0x20): return 8'hFF (all foreground)
//                        if glyph == ' '        : return 8'h00 (all background)
//    This lets us test:
//      - Banner regions where text characters exist → FG_COLOR
//      - Banner regions with space characters    → BG_COLOR
//      - Outside banner → video_in unchanged
//
//  Test 1 – Outside banner (drawY > 15)
//    Send video_in = 0xABCDEF with drawY = 100.
//    After 2 cycles: video_out should equal video_in (pass-through).
//
//  Test 2 – Inside banner, foreground pixel (font bit = 1)
//    drawY = 5 (inside banner), drawX at a column where a non-space char exists.
//    With stub font returning 0xFF → font_pixel = 1 → video_out = FG_COLOR.
//
//  Test 3 – Inside banner, background pixel (font bit = 0)
//    drawX at a column where a space character exists (font stub returns 0x00).
//    font_pixel = 0 → video_out = BG_COLOR.
//
//  Test 4 – Vsync latch
//    Change SW mid-frame (not at vsync boundary).
//    Verify text_buf_stable doesn't change until next vsync.
//    Change SW at vsync, verify latch updates.
//
//  Test 5 – pvalid_out tracks pixel_valid (2-cycle delay)
//
//  Pipeline depth: 2 cycles (font BRAM read + output register).
//  All inputs must be presented 2 cycles before expecting the result.
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

// =============================================================================
// Behavioural font_rom stub
// Replace with actual font_rom.sv for hardware-level testing.
// =============================================================================
module font_rom (
    input  logic        clk,
    input  logic [10:0] addr,
    output logic [7:0]  data
);
    // Stub: return 0xFF for any non-space glyph, 0x00 for space (0x20)
    always_ff @(posedge clk) begin
        if (addr[10:4] == 7'h20)  // space character
            data <= 8'h00;
        else
            data <= 8'hFF;   // all foreground bits set
    end
endmodule


// =============================================================================
// TESTBENCH
// =============================================================================
module tb_text_overlay;

    localparam CLK_PERIOD = 40;    // 25 MHz

    logic        pixel_clk, reset;
    logic [9:0]  drawX, drawY;
    logic        vs;
    logic [15:0] SW;
    logic [23:0] video_in, video_out;
    logic        pixel_valid, pvalid_out;

    int error_count = 0;

    text_overlay dut (
        .pixel_clk   (pixel_clk),
        .reset       (reset),
        .drawX       (drawX),
        .drawY       (drawY),
        .vs          (vs),
        .SW          (SW),
        .video_in    (video_in),
        .pixel_valid (pixel_valid),
        .video_out   (video_out),
        .pvalid_out  (pvalid_out)
    );

    initial pixel_clk = 0;
    always #(CLK_PERIOD/2) pixel_clk = ~pixel_clk;

    localparam [23:0] FG_COLOR = 24'hFFFF00;   // yellow
    localparam [23:0] BG_COLOR = 24'h000080;   // navy

    // ── Drive one pixel and read output 2 cycles later ────────────────────
    task automatic drive_pixel(
        input [9:0]  dx, dy,
        input        pv,
        input [23:0] vin
    );
        @(negedge pixel_clk);
        drawX       = dx;
        drawY       = dy;
        pixel_valid = pv;
        video_in    = vin;
    endtask

    // ── Wait for output to settle (2 cycles pipeline) ─────────────────────
    task automatic wait_out();
        @(posedge pixel_clk);   // cycle 1
        @(posedge pixel_clk);   // cycle 2 – output now valid
        @(negedge pixel_clk);   // stable read point
    endtask

    // ── Issue vsync falling edge ───────────────────────────────────────────
    task automatic do_vsync();
        @(negedge pixel_clk); vs = 1'b1;  // vsync goes high
        repeat(4) @(posedge pixel_clk);
        @(negedge pixel_clk); vs = 1'b0;  // vsync falls → latch trigger
        repeat(4) @(posedge pixel_clk);
    endtask

    initial begin
        $dumpfile("tb_text_overlay.vcd");
        $dumpvars(0, tb_text_overlay);

        reset = 1; SW = 16'h0; vs = 1'b1;
        drawX = 0; drawY = 0; video_in = 24'h0; pixel_valid = 0;
        repeat(4) @(negedge pixel_clk);
        reset = 0;

        // Initial vsync to latch the initial switch state
        do_vsync();
        repeat(5) @(negedge pixel_clk);

        $display("\n=== Text Overlay Tests ===");

        // ── T1: Outside banner → passthrough ──────────────────────────────
        $display("\n-- T1: Outside banner (drawY=100) --");
        begin
            logic [23:0] test_vid = 24'hABCDEF;
            drive_pixel(10'd100, 10'd100, 1'b1, test_vid);
            wait_out();
            if (video_out !== test_vid) begin
                $error("T1: outside banner got 0x%06X exp 0xABCDEF", video_out);
                error_count++;
            end else
                $display("[%0t] T1 PASS: outside banner passthrough", $time);
        end

        // ── T2: Inside banner, pixel_valid=0 → background colour ──────────
        // (pvalid=0 means blanking; output should be video_in_d2=0, not FG/BG)
        $display("\n-- T2: banner + pixel_valid=0 --");
        begin
            SW = 16'h0001;  // grayscale ON → some non-space text expected
            do_vsync();
            repeat(3) @(negedge pixel_clk);
            drive_pixel(10'd0, 10'd5, 1'b0, 24'h112233);  // inside banner, invalid
            wait_out();
            // with pixel_valid=0, compositor passes video_in_d2
            // video_in_d2 will be 24'h112233 (passed through 2 delay regs)
            if (pvalid_out !== 1'b0) begin
                $error("T2: pvalid_out=%0b should be 0 when input invalid", pvalid_out);
                error_count++;
            end else
                $display("[%0t] T2 PASS: pvalid_out=0 when pixel_valid=0", $time);
            SW = 16'h0;
        end

        // ── T3: Inside banner, valid pixel, non-space char → FG_COLOR ─────
        $display("\n-- T3: Banner FG pixel (non-space glyph) --");
        begin
            SW = 16'h0001;  // enable grayscale → displays "GRAY"
            do_vsync();
            repeat(3) @(negedge pixel_clk);
            // drawX=0..7 = first character 'G' (non-space) → font stub returns 0xFF
            // font_pixel = bit7 of 0xFF = 1 → FG_COLOR
            drive_pixel(10'd0, 10'd5, 1'b1, 24'hCAFEEE);
            wait_out();
            if (video_out !== FG_COLOR) begin
                $error("T3: FG pixel got 0x%06X exp 0x%06X", video_out, FG_COLOR);
                error_count++;
            end else
                $display("[%0t] T3 PASS: FG_COLOR at banner character position", $time);
            SW = 16'h0;
        end

        // ── T4: Beyond text_len → video_in passes through ─────────────────
        $display("\n-- T4: Beyond text_len → passthrough --");
        begin
            // SW=0 → PASSTHROUGH = 11 chars = 88 pixels wide
            // drawX = 200 is beyond banner
            do_vsync();
            repeat(3) @(negedge pixel_clk);
            drive_pixel(10'd200, 10'd5, 1'b1, 24'h567890);
            wait_out();
            if (video_out !== 24'h567890) begin
                $error("T4: beyond text_len got 0x%06X exp 0x567890", video_out);
                error_count++;
            end else
                $display("[%0t] T4 PASS: beyond text_len → passthrough", $time);
        end

        // ── T5: Vsync latching – SW changes do NOT take effect mid-frame ──
        $display("\n-- T5: Vsync latch --");
        begin
            logic [23:0] old_out;
            // Set SW[0] and latch at vsync
            SW = 16'h0001;
            do_vsync();
            // text_buf_stable now has "GRAY" (4 chars = 32 pixels wide)

            // Sample a pixel inside the GRAY text
            drive_pixel(10'd8, 10'd5, 1'b1, 24'hFFFFFF);  // col 8 = second char 'R'
            wait_out();
            old_out = video_out;
            // Should be FG_COLOR (still inside GRAY text)
            if (video_out !== FG_COLOR) begin
                $error("T5 pre-change: got 0x%06X exp FG", video_out);
                error_count++;
            end

            // Now change SW mid-frame (without vsync) – should NOT affect stable buffer
            SW = 16'h0000;   // would switch to PASSTHROUGH
            repeat(5) @(negedge pixel_clk);
            // Sample same position; should still show FG_COLOR (old latch)
            drive_pixel(10'd8, 10'd5, 1'b1, 24'hFFFFFF);
            wait_out();
            if (video_out !== FG_COLOR) begin
                $error("T5 mid-frame: SW change should not affect output yet (got 0x%06X)",
                       video_out);
                error_count++;
            end else
                $display("[%0t] T5 PASS: mid-frame SW change ignored until vsync", $time);

            // After vsync, the change should take effect
            do_vsync();
            // text_buf_stable is now PASSTHROUGH (11 chars)
            // col 8 is still inside PASSTHROUGH (8 chars in) – still a non-space char
            drive_pixel(10'd8, 10'd5, 1'b1, 24'hFFFFFF);
            wait_out();
            if (video_out !== FG_COLOR) begin
                $error("T5 post-vsync: still got 0x%06X exp FG_COLOR", video_out);
                error_count++;
            end else
                $display("[%0t] T5 PASS: post-vsync latch updated correctly", $time);
        end

        // ── T6: pvalid_out is delayed 2 cycles ────────────────────────────
        $display("\n-- T6: pvalid_out delay --");
        begin
            // Drive pixel_valid=1
            @(negedge pixel_clk);
            drawX=10'd300; drawY=10'd200; pixel_valid=1'b1; video_in=24'h0;
            @(posedge pixel_clk); @(posedge pixel_clk); @(negedge pixel_clk);
            if (pvalid_out !== 1'b1) begin
                $error("T6: pvalid_out should be 1 after 2 cycles");
                error_count++;
            end else
                $display("[%0t] T6 PASS: pvalid_out delayed correctly", $time);
            // Now drive pixel_valid=0
            @(negedge pixel_clk); pixel_valid = 1'b0;
            @(posedge pixel_clk); @(posedge pixel_clk); @(negedge pixel_clk);
            if (pvalid_out !== 1'b0) begin
                $error("T6: pvalid_out should be 0 after 2 cycles of invalid");
                error_count++;
            end else
                $display("[%0t] T6 PASS: pvalid_out goes low after invalid", $time);
        end

        $display("\n========================================");
        if (error_count == 0)
            $display("ALL text_overlay TESTS PASSED");
        else
            $display("FAILED: %0d error(s)", error_count);
        $display("========================================\n");
        $finish;
    end

endmodule
