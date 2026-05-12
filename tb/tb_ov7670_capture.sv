///////////////////////////////////////////////////////////////////////////////
// tb_ov7670_capture.sv  –  corrected for actual DUT behaviour
//
// KEY FIXES vs original:
//   1. DUT clocks on NEGEDGE cam_pclk  → all sampling uses negedge
//   2. DUT pixel-doubles: only writes when col[0]==0 && row[0]==0
//      Address = (row[9:1])*320 + col[9:1]  (one write per 2×2 block)
//   3. col counts up to 639 (VGA), row up to 479 (VGA)
//   4. Task drive_byte: puts data BEFORE negedge so DUT latches it
//
// RGB565 layout (datasheet Fig 11):
//   Byte 1 (high_byte): D[7:3]=R[4:0]  D[2:0]=G[5:3]
//   Byte 2 (cam_data):  D[7:5]=G[2:0]  D[4:0]=B[4:0]
//   wr_data = {cam_data, high_byte}  (low byte first per current DUT)
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tb_ov7670_capture;

    logic        cam_pclk;
    logic        cam_vsync;
    logic        cam_href;
    logic [7:0]  cam_data;
    logic [16:0] wr_addr;
    logic [15:0] wr_data;
    logic        wr_en;

    int errors = 0;

    ov7670_capture dut (
        .cam_pclk  (cam_pclk),
        .cam_vsync (cam_vsync),
        .cam_href  (cam_href),
        .cam_data  (cam_data),
        .wr_addr   (wr_addr),
        .wr_data   (wr_data),
        .wr_en     (wr_en)
    );

    // 24 MHz PCLK  (DUT samples on NEGEDGE)
    localparam HALF = 21;   // ns
    initial cam_pclk = 0;
    always  #HALF cam_pclk = ~cam_pclk;

    // ── helpers ──────────────────────────────────────────────────────────────
    // Wait for a negedge, put data on the bus, DUT will latch it
    task automatic drive_byte(input [7:0] d);
        @(negedge cam_pclk); cam_data = d;
    endtask

    // Send one RGB565 pixel (two bytes) with HREF asserted.
    // Returns captured outputs AFTER the second byte is latched.
    task automatic send_pixel(
        input  [15:0] pix,
        output [16:0] got_addr,
        output [15:0] got_data,
        output logic  got_wr
    );
        drive_byte(pix[15:8]);   // high byte: DUT latches → high_byte
        drive_byte(pix[7:0]);    // low byte : DUT assembles & may write
        @(negedge cam_pclk);     // one more negedge so outputs are stable
        got_addr = wr_addr;
        got_data = wr_data;
        got_wr   = wr_en;
    endtask

    // Issue VSYNC pulse (HIGH → LOW falling edge resets DUT counters)
    task automatic vsync_frame_start();
        cam_href  = 0;
        cam_vsync = 1;
        repeat(4) @(negedge cam_pclk);
        cam_vsync = 0;
        repeat(2) @(negedge cam_pclk);
    endtask

    // Stream N pixels on one HREF line; returns last captured write outputs
    task automatic stream_n_pixels(
        input int      n,
        input [15:0]   pix_val,
        output [16:0]  last_addr,
        output [15:0]  last_data,
        output logic   last_wr
    );
        logic [16:0] a; logic [15:0] d; logic w;
        for (int i = 0; i < n; i++) begin
            send_pixel(pix_val, a, d, w);
            last_addr = a; last_data = d; last_wr = w;
        end
    endtask

    `define CHECK(cond, msg) \
        if (!(cond)) begin $error("[%0t] FAIL: %s",$time,msg); errors++; end \
        else $display("[%0t] PASS: %s",$time,msg);

    // ── main ─────────────────────────────────────────────────────────────────
    initial begin
        $dumpfile("tb_ov7670_capture.vcd");
        $dumpvars(0, tb_ov7670_capture);

        cam_vsync = 1; cam_href = 0; cam_data = 0;

        // ─── T1: VSYNC resets counters ───────────────────────────────────────
        $display("\n=== T1: VSYNC reset ===");
        vsync_frame_start();
        // First pixel pair of VGA row 0, col 0 → camera row 0, col 0
        // DUT only writes when col[0]==0 && row[0]==0 → SHOULD write here
        begin
            logic [16:0] a; logic [15:0] d; logic w;
            cam_href = 1;
            send_pixel(16'hF800, a, d, w);   // pure red
            // addr = (row>>1)*320 + (col>>1) = 0*320+0 = 0
            `CHECK(w == 1'b1,        "T1: wr_en asserted at (row=0,col=0)")
            `CHECK(a == 17'd0,       "T1: addr=0 for first pixel")
            // wr_data = {cam_data, high_byte} = {8'h00, 8'hF8}
            `CHECK(d == 16'h00F8,    "T1: wr_data = {low,high} = 0x00F8")
            cam_href = 0;
        end

        // ─── T2: pixel-doubling — col=1 (VGA) must NOT write ─────────────────
        // After T1, col=1 inside the DUT (odd column → no write)
        $display("\n=== T2: Pixel doubling – odd column skips write ===");
        begin
            logic [16:0] a; logic [15:0] d; logic w;
            cam_href = 1;
            send_pixel(16'h07E0, a, d, w);   // green – col=1 → odd → no write
            `CHECK(w == 1'b0,  "T2: no write at VGA col=1 (odd – pixel double)")
            cam_href = 0;
        end

        // ─── T3: col=2 (even) DOES write, addr=1 ─────────────────────────────
        $display("\n=== T3: Even column (col=2) writes addr=1 ===");
        begin
            logic [16:0] a; logic [15:0] d; logic w;
            cam_href = 1;
            send_pixel(16'h001F, a, d, w);   // blue – col=2, even → write
            `CHECK(w == 1'b1,    "T3: wr_en at col=2")
            `CHECK(a == 17'd1,   "T3: addr=1 (col>>1=1, row>>1=0)")
            cam_href = 0;
        end

        // ─── T4: HREF falling mid-pair clears byte_sel ───────────────────────
        $display("\n=== T4: HREF drop after first byte – no spurious write ===");
        begin
            vsync_frame_start();   // reset to row=0,col=0
            cam_href = 1;
            @(negedge cam_pclk); cam_data = 8'hDE;   // high byte only
            @(negedge cam_pclk); cam_href = 0;        // drop before second byte
            @(negedge cam_pclk);
            `CHECK(wr_en == 1'b0,  "T4: no write when HREF drops after 1st byte")
            // Fresh restart – next even column pair should write cleanly
            cam_href = 1;
            begin
                logic [16:0] a; logic [15:0] d; logic w;
                send_pixel(16'h1234, a, d, w);
                `CHECK(w == 1'b1,           "T4: write valid after clean restart")
                `CHECK(d == 16'h3412,       "T4: data correct {low,high}")
            end
            cam_href = 0;
        end

        // ─── T5: Row increment after HREF de-asserts ──────────────────────────
        $display("\n=== T5: Row counter increments after HREF line ===");
        begin
            vsync_frame_start();
            // Stream 640 VGA pixels (= one full row) – col goes 0..639
            // Only even-col, even-row pairs write → 320 writes expected
            cam_href = 1;
            for (int c = 0; c < 640; c++) begin
                @(negedge cam_pclk); cam_data = 8'hAA;  // high byte
                @(negedge cam_pclk); cam_data = 8'h55;  // low byte
            end
            cam_href = 0;
            // After HREF falls, DUT increments row to 1
            // Now stream first pixel of next line; col=0,row=1 → odd row → no write
            repeat(2) @(negedge cam_pclk);
            cam_href = 1;
            begin
                logic [16:0] a; logic [15:0] d; logic w;
                send_pixel(16'hBEEF, a, d, w);
                `CHECK(w == 1'b0,  "T5: no write at row=1 (odd row – pixel double)")
            end
            cam_href = 0;
        end

        // ─── T6: row=2 writes at addr=320 (second camera row) ────────────────
        $display("\n=== T6: row=2 writes addr=320 ===");
        begin
            // Still in same frame. row=1 just completed above.
            // Stream another full 640-pixel row to get to row=2
            repeat(2) @(negedge cam_pclk);
            cam_href = 1;
            for (int c = 0; c < 640; c++) begin
                @(negedge cam_pclk); cam_data = 8'hCC;
                @(negedge cam_pclk); cam_data = 8'h33;
            end
            cam_href = 0;
            // Now row=2. Stream first pixel: col=0,row=2 both even → write
            repeat(2) @(negedge cam_pclk);
            cam_href = 1;
            begin
                logic [16:0] a; logic [15:0] d; logic w;
                send_pixel(16'hDEAD, a, d, w);
                // addr = (2>>1)*320 + (0>>1) = 1*320 + 0 = 320
                `CHECK(w == 1'b1,         "T6: write at row=2, col=0")
                `CHECK(a == 17'd320,      "T6: addr=320 (second camera row)")
            end
            cam_href = 0;
        end

        $display("\n========================================");
        if (errors == 0) $display("ALL CAPTURE TESTS PASSED");
        else             $display("FAILED: %0d error(s)", errors);
        $display("========================================\n");
        $finish;
    end

endmodule
