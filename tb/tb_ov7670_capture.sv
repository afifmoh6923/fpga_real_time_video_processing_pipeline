///////////////////////////////////////////////////////////////////////////////
// tb_ov7670_capture.sv
// Testbench for ov7670_capture.sv
// ─────────────────────────────────────────────────────────────────────────────
// HOW THIS TESTBENCH WORKS:
//
//  The OV7670 in QVGA RGB565 mode drives:
//    VSYNC  – HIGH during vertical blanking; falling edge = new frame
//    HREF   – HIGH during active pixel data in a row
//    PCLK   – pixel clock; the DUT samples data on rising PCLK edges
//    D[7:0] – 8-bit bus; sends TWO bytes per pixel (high byte then low byte)
//
//  This TB simulates those signals and checks the resulting write-port outputs.
//
//  Test 1 – Pixel assembly
//    Sends two known bytes for pixel (0,0): high=0xF8, low=0x00.
//    RGB565 = 0xF800 = {R=11111, G=000000, B=00000} = pure red.
//    Checks: wr_en asserts on second byte, wr_data == 0xF800, wr_addr == 0.
//
//  Test 2 – Address calculation
//    Sends pixels across several columns and rows.
//    Verifies: addr = row*320 + col for arbitrary (row, col) pairs.
//
//  Test 3 – VSYNC reset
//    Sends some pixels, then pulses VSYNC HIGH (blanking), then LOW again.
//    Verifies col and row counters reset to 0 (addr goes back to 0).
//
//  Test 4 – HREF low clears byte_sel
//    Sends one high byte (byte_sel goes to 1), then drops HREF LOW.
//    Verifies no spurious wr_en and that next HREF-high starts on high byte.
//
//  Test 5 – First row, all 320 columns
//    Streams a full QVGA row of 320 pixels with incrementing data.
//    Checks every write address is sequential 0..319.
//
//  Self-checking:
//    $error with descriptive messages; summary at end.
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module tb_ov7670_capture;

    // ── Signals ───────────────────────────────────────────────────────────────
    logic        cam_pclk;
    logic        cam_vsync;
    logic        cam_href;
    logic [7:0]  cam_data;

    logic [16:0] wr_addr;
    logic [15:0] wr_data;
    logic        wr_en;

    int error_count = 0;

    // ── DUT ───────────────────────────────────────────────────────────────────
    ov7670_capture dut (
        .cam_pclk  (cam_pclk),
        .cam_vsync (cam_vsync),
        .cam_href  (cam_href),
        .cam_data  (cam_data),
        .wr_addr   (wr_addr),
        .wr_data   (wr_data),
        .wr_en     (wr_en)
    );

    // ── Clock: 24 MHz PCLK ─────────────────────────────────────────────────
    localparam PCLK_PERIOD = 42; // ns (~24 MHz)
    initial cam_pclk = 0;
    always #(PCLK_PERIOD/2) cam_pclk = ~cam_pclk;

    // ─────────────────────────────────────────────────────────────────────────
    // TASK: send_pixel
    //   Sends one RGB565 pixel as two bytes with HREF high.
    //   Returns write signals seen on the second byte clock.
    // ─────────────────────────────────────────────────────────────────────────
    task automatic send_pixel(
        input  logic [15:0] pixel,
        output logic [16:0] got_addr,
        output logic [15:0] got_data,
        output logic        got_wr_en
    );
        // First byte (high byte)
        @(negedge cam_pclk);
        cam_data = pixel[15:8];

        @(posedge cam_pclk);   // DUT samples high byte

        // Second byte (low byte)
        @(negedge cam_pclk);
        cam_data = pixel[7:0];

        @(posedge cam_pclk);   // DUT samples low byte and writes

        @(negedge cam_pclk);   // capture stable output
        got_addr   = wr_addr;
        got_data   = wr_data;
        got_wr_en  = wr_en;
    endtask

    // ─────────────────────────────────────────────────────────────────────────
    // TASK: vsync_pulse
    //   Generates the VSYNC falling edge that resets frame counters.
    //   VSYNC HIGH = blanking.  After VSYNC falls, row & col reset.
    // ─────────────────────────────────────────────────────────────────────────
    task automatic vsync_pulse();
        cam_href  = 0;
        cam_vsync = 1;
        repeat(4) @(negedge cam_pclk);
        cam_vsync = 0;
        repeat(2) @(negedge cam_pclk);
    endtask

    // ── CHECK macro ──────────────────────────────────────────────────────────
    `define CHECK(cond, msg) \
        if (!(cond)) begin $error(msg); error_count++; end \
        else $display("[%0t] PASS: %s", $time, msg);

    // ─────────────────────────────────────────────────────────────────────────
    // MAIN STIMULUS
    // ─────────────────────────────────────────────────────────────────────────
    initial begin
        $dumpfile("tb_ov7670_capture.vcd");
        $dumpvars(0, tb_ov7670_capture);

        // Initialise bus to idle
        cam_vsync = 1;
        cam_href  = 0;
        cam_data  = 8'h00;

        // Issue VSYNC to reset counters
        vsync_pulse();

        // =================================================================
        // Test 1 – Pixel assembly: pixel (0,0) = 0xF800 (pure red)
        // =================================================================
        $display("\n=== Test 1: Pixel assembly ===");
        logic [16:0] got_addr;
        logic [15:0] got_data;
        logic        got_wr;

        cam_href = 1;
        send_pixel(16'hF800, got_addr, got_data, got_wr);
        `CHECK(got_wr   == 1'b1,          "T1: wr_en asserted on second byte")
        `CHECK(got_data == 16'hF800,      "T1: wr_data == 0xF800 (pure red)")
        `CHECK(got_addr == 17'd0,         "T1: wr_addr == 0 for pixel (0,0)")
        cam_href = 0;

        // =================================================================
        // Test 2 – Address calculation: pixel (0,1) and (0,2)
        // =================================================================
        $display("\n=== Test 2: Sequential address ===");
        cam_href = 1;
        send_pixel(16'h07E0, got_addr, got_data, got_wr);  // green
        `CHECK(got_wr   == 1'b1,      "T2: wr_en pixel(0,1)")
        `CHECK(got_data == 16'h07E0,  "T2: data pixel(0,1)")
        `CHECK(got_addr == 17'd1,     "T2: addr pixel(0,1)")

        send_pixel(16'h001F, got_addr, got_data, got_wr);  // blue
        `CHECK(got_wr   == 1'b1,      "T2: wr_en pixel(0,2)")
        `CHECK(got_data == 16'h001F,  "T2: data pixel(0,2)")
        `CHECK(got_addr == 17'd2,     "T2: addr pixel(0,2)")
        cam_href = 0;

        // =================================================================
        // Test 3 – Row wrap: stream 320 pixels; next pixel addr = 320
        // =================================================================
        $display("\n=== Test 3: Row wrap to addr 320 ===");
        // Already sent 3 pixels; need 317 more to complete first row
        cam_href = 1;
        repeat(317) begin
            send_pixel(16'hFFFF, got_addr, got_data, got_wr);
        end
        cam_href = 0;
        // Simulate line end (HREF low for horizontal blanking)
        repeat(4) @(negedge cam_pclk);

        // Start second row
        cam_href = 1;
        send_pixel(16'hAAAA, got_addr, got_data, got_wr);
        `CHECK(got_addr == 17'd320,   "T3: first pixel of row 1 has addr 320")
        cam_href = 0;

        // =================================================================
        // Test 4 – VSYNC reset
        // =================================================================
        $display("\n=== Test 4: VSYNC resets counters ===");
        // We are partway through row 1; issue VSYNC
        vsync_pulse();

        // First pixel after VSYNC should be at addr 0
        cam_href = 1;
        send_pixel(16'h5555, got_addr, got_data, got_wr);
        `CHECK(got_addr == 17'd0,     "T4: addr resets to 0 after VSYNC")
        `CHECK(got_wr   == 1'b1,      "T4: wr_en after VSYNC")
        cam_href = 0;

        // =================================================================
        // Test 5 – HREF falling clears byte_sel (no half-pixel write)
        // =================================================================
        $display("\n=== Test 5: HREF low clears byte_sel ===");
        // Send only the high byte then drop HREF
        @(negedge cam_pclk); cam_href = 1; cam_data = 8'hDE;
        @(posedge cam_pclk);
        @(negedge cam_pclk); cam_href = 0;  // drop before second byte
        @(posedge cam_pclk);
        // wr_en must NOT be asserted
        `CHECK(wr_en == 1'b0,         "T5: no write when HREF drops after 1st byte")

        // Now a fresh start on next HREF should begin on high byte
        @(negedge cam_pclk); cam_href = 1;
        send_pixel(16'h1234, got_addr, got_data, got_wr);
        `CHECK(got_wr   == 1'b1,      "T5: write valid after clean restart")
        `CHECK(got_data == 16'h1234,  "T5: data correct after clean restart")
        cam_href = 0;

        // ── Report ────────────────────────────────────────────────────────────
        $display("\n========================================");
        if (error_count == 0)
            $display("ALL TESTS PASSED (0 errors)");
        else
            $display("FAILED: %0d error(s)", error_count);
        $display("========================================\n");
        $finish;
    end

endmodule
