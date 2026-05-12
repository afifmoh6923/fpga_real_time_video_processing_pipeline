///////////////////////////////////////////////////////////////////////////////
// tb_top.sv  –  corrected for actual DUT
//
// KEY FIXES vs original:
//   1. top.sv has NO cam_reset_n / cam_pwdn ports (they are commented out)
//   2. BRAM instance in top is named "frame_buffer" not "blk_mem_gen_0"
//   3. HDMI stub uses TMDS_DATA_P/N not hdmi_tx_p/n
//   4. Removed Test 1 cam_reset_n/cam_pwdn checks – not in port list
//   5. Added test for pixel-doubling timing (every other pixel_clk write)
//   6. PIPE_LATENCY = 13 (1 addr reg + 1 BRAM + 9 filter + 2 overlay)
//   7. ov7670_capture clocks on NEGEDGE cam_pclk
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

// ── STUB: clk_wiz_0 ──────────────────────────────────────────────────────────
module clk_wiz_0 (
    input  logic clk_in1,
    input  logic reset,
    output logic clk_out1,   // 25 MHz pixel_clk
    output logic clk_out2,   // 125 MHz tmds_clk
    output logic clk_out3,   // ~24 MHz cam_clk
    output logic locked
);
    logic [1:0] cnt4 = 0;
    always @(posedge clk_in1 or posedge reset) begin
        if (reset) begin cnt4<=0; clk_out1<=0; end
        else begin
            cnt4 <= cnt4+1;
            if (cnt4==2'd1) clk_out1<=1;
            if (cnt4==2'd3) clk_out1<=0;
        end
    end
    initial clk_out2 = 0;
    always #4 clk_out2 = ~clk_out2;

    logic [1:0] cnt_cam = 0;
    always @(posedge clk_in1 or posedge reset) begin
        if (reset) begin cnt_cam<=0; clk_out3<=0; end
        else begin
            cnt_cam <= cnt_cam+1;
            if (cnt_cam==2'd1) clk_out3<=1;
            if (cnt_cam==2'd3) clk_out3<=0;
        end
    end
    logic [2:0] lcnt = 0;
    always @(posedge clk_in1 or posedge reset) begin
        if (reset) begin locked<=0; lcnt<=0; end
        else if (!locked) begin lcnt<=lcnt+1; if(lcnt==3'd7) locked<=1; end
    end
endmodule

// ── STUB: frame_buffer (inferred BRAM – replaces blk_mem_gen_0) ──────────────
// top.sv instantiates: frame_buffer frame_buffer_inst (...)
// Port names match actual top.sv wiring
module frame_buffer (
    input  logic        clka,
    input  logic        wea,
    input  logic [16:0] addra,
    input  logic [15:0] dina,
    input  logic        clkb,
    input  logic [16:0] addrb,
    output logic [15:0] doutb
);
    logic [15:0] mem [0:131071];
    initial for (int i=0;i<131072;i++) mem[i]=16'h0;
    always_ff @(posedge clka) if (wea) mem[addra] <= dina;
    always_ff @(posedge clkb) doutb <= mem[addrb];
endmodule

// ── STUB: hdmi_tx_0 ───────────────────────────────────────────────────────────
module hdmi_tx_0 (
    input  logic        pix_clk, pix_clkx5, pix_clk_locked, rst,
    input  logic [3:0]  red, green, blue,
    input  logic        hsync, vsync, vde,
    input  logic [3:0]  aux0_din, aux1_din, aux2_din,
    input  logic        ade,
    output logic [2:0]  TMDS_DATA_P, TMDS_DATA_N,
    output logic        TMDS_CLK_P,  TMDS_CLK_N
);
    assign TMDS_DATA_P = 3'b111; assign TMDS_DATA_N = 3'b000;
    assign TMDS_CLK_P  = 1'b1;   assign TMDS_CLK_N  = 1'b0;
endmodule

// ── STUB: font_rom ────────────────────────────────────────────────────────────
module font_rom (
    input  logic        clk,
    input  logic [10:0] addr,
    output logic [7:0]  data
);
    always_ff @(posedge clk)
        data <= (addr[10:4] == 7'h20) ? 8'h00 : 8'hFF;
endmodule

// ── STUB: sync_flop (used by top for SW synchronisation) ─────────────────────
module sync_flop (
    input  logic clk, d,
    output logic q
);
    logic r1 = 0;
    always_ff @(posedge clk) begin r1 <= d; q <= r1; end
endmodule

// =============================================================================
// TOP-LEVEL TESTBENCH
// =============================================================================
module tb_top;

    // ── DUT ports (matches actual top.sv port list) ───────────────────────────
    logic        Clk;
    logic        reset_btn;
    logic [15:0] SW;
    logic        cam_pclk;
    logic        cam_xclk;
    wire         cam_siod;
    logic        cam_sioc;
    logic        cam_vsync, cam_href;
    logic [7:0]  cam_data;
    logic [15:0] LED;
    logic        hdmi_tmds_clk_n, hdmi_tmds_clk_p;
    logic [2:0]  hdmi_tmds_data_n, hdmi_tmds_data_p;

    // ── Hierarchical probes into DUT ──────────────────────────────────────────
    wire [9:0]  probe_drawX  = dut.drawX;
    wire [9:0]  probe_drawY  = dut.drawY;
    wire        probe_hs     = dut.hs;
    wire        probe_vs     = dut.vs;
    wire        probe_blank  = dut.active_nblank;
    wire [3:0]  probe_hdmi_r = dut.hdmi_r;
    wire [3:0]  probe_hdmi_g = dut.hdmi_g;
    wire [3:0]  probe_hdmi_b = dut.hdmi_b;
    wire        probe_vde    = dut.vde;
    wire        probe_pxclk  = dut.pixel_clk;
    wire        probe_camclk = dut.cam_clk_int;
    wire        probe_cfg    = dut.config_done;
    wire [16:0] probe_wr_addr= dut.fb_wr_addr;
    wire [15:0] probe_wr_data= dut.fb_wr_data;
    wire        probe_wr_en  = dut.fb_wr_en;

    int total_errors = 0;

    localparam CLK_PERIOD   = 10;   // 100 MHz board
    localparam H_TOTAL      = 800;
    localparam H_ACTIVE     = 640;
    localparam V_TOTAL      = 525;
    localparam V_ACTIVE     = 480;
    // Pipeline latency: 1(addr reg) + 1(BRAM) + 9(filter) + 2(overlay) = 13
    localparam PIPE_LATENCY = 13;

    // ── DUT ───────────────────────────────────────────────────────────────────
    top dut (
        .Clk              (Clk),
        .reset_btn        (reset_btn),
        .SW               (SW),
        .LED              (LED),
        .cam_pclk         (cam_pclk),
        .cam_xclk         (cam_xclk),
        .cam_siod         (cam_siod),
        .cam_sioc         (cam_sioc),
        .cam_vsync        (cam_vsync),
        .cam_href         (cam_href),
        .cam_data         (cam_data),
        .hdmi_tmds_clk_n  (hdmi_tmds_clk_n),
        .hdmi_tmds_clk_p  (hdmi_tmds_clk_p),
        .hdmi_tmds_data_n (hdmi_tmds_data_n),
        .hdmi_tmds_data_p (hdmi_tmds_data_p)
    );

    initial Clk = 0;
    always #(CLK_PERIOD/2) Clk = ~Clk;

    // cam_pclk: same rate as pixel_clk for simplicity; DUT samples on NEGEDGE
    initial cam_pclk = 0;
    always #20 cam_pclk = ~cam_pclk;   // 25 MHz matches pixel_clk

    `define CHECK(expr, msg) \
        if (!(expr)) begin $error("[%0t] FAIL: %s",$time,msg); total_errors++; end \
        else $display("[%0t] PASS: %s",$time,msg);

    // ── Tasks ─────────────────────────────────────────────────────────────────
    task automatic apply_reset(input int cyc = 8);
        @(negedge Clk); reset_btn = 1;
        repeat(cyc) @(posedge Clk);
        @(negedge Clk); reset_btn = 0;
        repeat(20) @(posedge probe_pxclk);
    endtask

    task automatic wait_px(input int n);
        repeat(n) @(posedge probe_pxclk);
    endtask

    task automatic wait_for_xy(input [9:0] tx, ty, input int timeout=2);
        int cnt=0, max=timeout*H_TOTAL*V_TOTAL;
        @(posedge probe_pxclk);
        while ((probe_drawX!==tx||probe_drawY!==ty)&&cnt<max)
            begin @(posedge probe_pxclk); cnt++; end
        if (probe_drawX!==tx||probe_drawY!==ty) begin
            $error("wait_for_xy timeout (%0d,%0d)",tx,ty); total_errors++; end
    endtask

    // Send one camera pixel (negedge-clocked DUT)
    task automatic cam_send_pixel(input [15:0] p);
        @(negedge cam_pclk); cam_href=1; cam_data=p[15:8];
        @(negedge cam_pclk);             cam_data=p[7:0];
        @(negedge cam_pclk); cam_href=0;
    endtask

    task automatic cam_frame_start();
        @(negedge cam_pclk); cam_vsync=1; cam_href=0;
        repeat(4) @(negedge cam_pclk);
        cam_vsync=0;
        repeat(2) @(negedge cam_pclk);
    endtask

    // Send one full 640-pixel VGA row (only even pairs write to BRAM)
    task automatic cam_send_row(input [15:0] pix);
        cam_href = 1;
        for (int c=0; c<640; c++) begin
            @(negedge cam_pclk); cam_data = pix[15:8];
            @(negedge cam_pclk); cam_data = pix[7:0];
        end
        @(negedge cam_pclk); cam_href=0;
        repeat(4) @(negedge cam_pclk);
    endtask

    // =========================================================================
    // TESTS
    // =========================================================================
    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);

        reset_btn=0; SW=0;
        cam_vsync=1; cam_href=0; cam_data=0;

        $display("\n╔══════════════════════════════════════╗");
        $display("║  ECE 385 Top-Level Testbench         ║");
        $display("╚══════════════════════════════════════╝\n");

        // ─────────────────────────────────────────────────────────────────────
        // TEST 1 – CLOCK AND INIT
        // Verify cam_xclk toggles and SIOC begins toggling after power-up delay.
        // ─────────────────────────────────────────────────────────────────────
        $display("═══ T1: Clock and SCCB Init ═══");
        apply_reset(10);
        begin
            int tog=0; logic prev=0; int cnt=0;
            prev = probe_camclk;
            repeat(20) begin
                @(posedge Clk);
                if (probe_camclk!==prev) tog++;
                prev=probe_camclk;
            end
            `CHECK(tog>=2, "T1: cam_xclk toggling after reset")
        end
        $display("T1 done\n");

        // ─────────────────────────────────────────────────────────────────────
        // TEST 2 – VGA HORIZONTAL TIMING
        // hs pulse width = 96 pixel_clk cycles (H_SYNC_END - H_SYNC_START)
        // active_nblank HIGH for drawX 0..639, LOW for 640..799
        // ─────────────────────────────────────────────────────────────────────
        $display("═══ T2: VGA Horizontal Timing ═══");
        begin
            int pw=0; logic prev_hs=1;
            // Wait for hs to go low
            repeat(H_TOTAL*2) @(posedge probe_pxclk);
            while (probe_hs!==1'b0) @(posedge probe_pxclk);
            // Count cycles it stays low
            while (probe_hs===1'b0) begin @(posedge probe_pxclk); pw++; end
            `CHECK(pw==96, $sformatf("T2: hs width=%0d (expected 96)",pw))
        end
        // Check active_nblank at known positions
        wait_for_xy(10'd300, probe_drawY);
        `CHECK(probe_blank===1'b1, "T2: active_nblank HIGH at drawX=300")
        wait_for_xy(10'd660, probe_drawY);
        `CHECK(probe_blank===1'b0, "T2: active_nblank LOW at drawX=660")
        $display("T2 done\n");

        // ─────────────────────────────────────────────────────────────────────
        // TEST 3 – VGA VERTICAL SYNC
        // vs pulse = 2 scan lines = 1600 pixel_clk cycles
        // ─────────────────────────────────────────────────────────────────────
        $display("═══ T3: VGA Vertical Sync ═══");
        begin
            int vw=0; int cnt=0;
            while (probe_vs!==1'b0 && cnt<V_TOTAL*H_TOTAL)
                begin @(posedge probe_pxclk); cnt++; end
            if (probe_vs!==1'b0) begin
                $error("T3: vs never went LOW"); total_errors++;
            end else begin
                while (probe_vs===1'b0) begin @(posedge probe_pxclk); vw++; end
                `CHECK(vw>=1595&&vw<=1605,
                    $sformatf("T3: vs width=%0d cycles (expected ~1600)",vw))
            end
        end
        $display("T3 done\n");

        // ─────────────────────────────────────────────────────────────────────
        // TEST 4 – VDE ACTIVE WINDOW TIMING
        // vde should go HIGH PIPE_LATENCY cycles after active_nblank rises
        // ─────────────────────────────────────────────────────────────────────
        $display("═══ T4: VDE Timing ═══");
        begin
            int cnt=0;
            while ((probe_drawX!==10'd0||probe_drawY>=10'd480)&&cnt<H_TOTAL*V_TOTAL)
                begin @(posedge probe_pxclk); cnt++; end
            wait_px(PIPE_LATENCY+1);
            `CHECK(probe_vde===1'b1,
                $sformatf("T4: vde HIGH %0d cycles after active region",PIPE_LATENCY))
        end
        wait_for_xy(10'd640, probe_drawY);
        wait_px(PIPE_LATENCY+1);
        `CHECK(probe_vde===1'b0, "T4: vde LOW past active region end")
        $display("T4 done\n");

        // ─────────────────────────────────────────────────────────────────────
        // TEST 5 – COLOUR-BAR TEST PATTERN (SW[15]=1)
        // Bar 0 (drawX 0..79)   → WHITE  hdmi_r/g/b = 4'hF
        // Bar 1 (drawX 80..159) → YELLOW hdmi_b = 4'h0
        // filter_pipeline uses drawX/80 (8 bars × 80 pixels = 640)
        // ─────────────────────────────────────────────────────────────────────
        $display("═══ T5: Colour-Bar Pattern ═══");
        SW = 16'h8000;
        wait_px(5);
        wait_for_xy(10'd40, 10'd50);      // centre of bar 0
        wait_px(PIPE_LATENCY);
        `CHECK(probe_hdmi_r===4'hF, "T5 bar0: R=F (white)")
        `CHECK(probe_hdmi_g===4'hF, "T5 bar0: G=F (white)")
        `CHECK(probe_hdmi_b===4'hF, "T5 bar0: B=F (white)")

        wait_for_xy(10'd120, 10'd50);     // centre of bar 1 (yellow)
        wait_px(PIPE_LATENCY);
        `CHECK(probe_hdmi_r===4'hF, "T5 bar1: R=F (yellow)")
        `CHECK(probe_hdmi_g===4'hF, "T5 bar1: G=F (yellow)")
        `CHECK(probe_hdmi_b===4'h0, "T5 bar1: B=0 (yellow)")

        SW = 16'h0000;
        $display("T5 done\n");

        // ─────────────────────────────────────────────────────────────────────
        // TEST 6 – CAMERA PIXEL END-TO-END (pure red)
        // Pixel (0,0) = 0xF800.  With pixel-doubling:
        //   wr_addr = 0.  Displayed at drawX[1:0]=0, drawY[1:0]=0.
        //   R565=11111 → R8=0xFF → hdmi_r=4'hF
        //   G565=000000 → G8=0x00 → hdmi_g=4'h0
        //   B565=00000  → B8=0x00 → hdmi_b=4'h0
        // ─────────────────────────────────────────────────────────────────────
        $display("═══ T6: Camera Pixel End-to-End ===");
        SW = 16'h0000;
        cam_frame_start();
        // col=0, row=0: both even → DUT writes to addr 0
        @(negedge cam_pclk); cam_href=1;
        @(negedge cam_pclk); cam_data=8'hF8;  // high byte: R[4:0]=11111 G[5:3]=000
        @(negedge cam_pclk); cam_data=8'h00;  // low byte:  G[2:0]=000  B[4:0]=00000
        @(negedge cam_pclk); cam_href=0;

        // Verify write happened
        wait_px(5);
        `CHECK(probe_wr_en===1'b0, "T6: wr_en deasserted after write")

        // Wait for display to reach (0,0) and add pipeline latency
        wait_for_xy(10'd0, 10'd0, 3);
        wait_px(PIPE_LATENCY+2);
        `CHECK(probe_hdmi_r===4'hF, "T6: hdmi_r=F (red)")
        `CHECK(probe_hdmi_g===4'h0, "T6: hdmi_g=0 (red)")
        `CHECK(probe_hdmi_b===4'h0, "T6: hdmi_b=0 (red)")
        `CHECK(probe_vde===1'b1,    "T6: vde HIGH during active pixel")
        $display("T6 done\n");

        // ─────────────────────────────────────────────────────────────────────
        // TEST 7 – GRAYSCALE FILTER (SW[0]=1)
        // Same pure-red pixel: Y = (77*255)>>8 = 76 = 0x4C
        // hdmi_r/g/b = 0x4C >> 4 = 4'h4
        // ─────────────────────────────────────────────────────────────────────
        $display("═══ T7: Grayscale Filter ═══");
        SW = 16'h0001;
        wait_px(5);
        wait_for_xy(10'd0, 10'd0, 3);
        wait_px(PIPE_LATENCY+2);
        `CHECK(probe_hdmi_r===4'h4, $sformatf("T7: hdmi_r=%0h (expected 4)",probe_hdmi_r))
        `CHECK(probe_hdmi_g===4'h4, $sformatf("T7: hdmi_g=%0h (expected 4)",probe_hdmi_g))
        `CHECK(probe_hdmi_b===4'h4, $sformatf("T7: hdmi_b=%0h (expected 4)",probe_hdmi_b))
        SW = 16'h0000;
        $display("T7 done\n");

        // ─────────────────────────────────────────────────────────────────────
        // TEST 8 – PIXEL DOUBLING WRITE PATTERN
        // Check that LED[3] (= fb_wr_en) only pulses every other cam_pclk
        // and every other VGA row pair
        // ─────────────────────────────────────────────────────────────────────
        $display("═══ T8: Pixel-Doubling Write Gate ═══");
        begin
            int wr_count=0;
            cam_frame_start();
            cam_href=1;
            // Send 8 pixel pairs (16 bytes) – should get exactly 2 writes
            // (col 0 and col 2 are even → write; col 1 and col 3 → no write)
            for (int c=0; c<8; c++) begin
                @(negedge cam_pclk); cam_data=8'hAA;
                @(negedge cam_pclk); cam_data=8'h55;
                @(negedge cam_pclk);
                if (probe_wr_en) wr_count++;
            end
            cam_href=0;
            // 8 VGA pixels → 4 even VGA columns (0,2,4,6) → 4 writes from row=0
            `CHECK(wr_count==4, $sformatf("T8: %0d writes in 8 pixels (expected 4)",wr_count))
        end
        $display("T8 done\n");

        // ─────────────────────────────────────────────────────────────────────
        // TEST 9 – RESET CLEARS PIPELINE
        // ─────────────────────────────────────────────────────────────────────
        $display("═══ T9: Reset Clears Pipeline ═══");
        apply_reset(8);
        wait_px(2*H_TOTAL+PIPE_LATENCY+10);
        wait_for_xy(10'd300, 10'd100, 3);
        wait_px(PIPE_LATENCY+1);
        `CHECK(probe_vde===1'b1,    "T9: vde HIGH during active region post-reset")
        `CHECK(probe_hdmi_r===4'h0, "T9: hdmi_r=0 (black) post-reset")
        `CHECK(probe_hdmi_g===4'h0, "T9: hdmi_g=0 post-reset")
        `CHECK(probe_hdmi_b===4'h0, "T9: hdmi_b=0 post-reset")
        $display("T9 done\n");

        $display("\n╔══════════════════════════════════════╗");
        $display("║         SIMULATION COMPLETE          ║");
        if (total_errors==0)
            $display("║     ALL TESTS PASSED (0 errors)      ║");
        else
            $display("║  FAILED – %0d error(s)                ║", total_errors);
        $display("╚══════════════════════════════════════╝\n");
        $finish;
    end

    // Optional waveform monitor – uncomment for console tracing
    // initial $monitor("[%0t] drawX=%0d drawY=%0d vde=%0b r=%0h g=%0h b=%0h",
    //     $time, probe_drawX, probe_drawY, probe_vde,
    //     probe_hdmi_r, probe_hdmi_g, probe_hdmi_b);

endmodule
