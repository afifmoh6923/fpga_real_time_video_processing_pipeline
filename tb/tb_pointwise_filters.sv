///////////////////////////////////////////////////////////////////////////////
// tb_pointwise_filters.sv  –  corrected
//
// KEY FIXES vs original:
//   1. Removed illegal literal syntax: 24'h{8'd180,8'd90,8'd45}
//      → replaced with {8'd180,8'd90,8'd45}
//   2. channel_isolate priority verified against actual sv (R>G>B)
//   3. All tasks use posedge clk (modules use posedge clk)
//   4. Grayscale Y formula uses >> 8 (same as actual module)
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

// =============================================================================
// GRAYSCALE
// =============================================================================
module tb_grayscale;
    localparam CLK_PERIOD = 40;
    logic clk=0, reset, enable, pixel_valid, pvalid_out;
    logic [23:0] rgb_in, rgb_out;
    int errors=0;

    grayscale dut(.clk,.reset,.enable,.pixel_valid,.rgb_in,.rgb_out,.pvalid_out);
    always #(CLK_PERIOD/2) clk=~clk;

    function automatic [7:0] Y(input [7:0] r,g,b);
        return ((16'(r)*77)+(16'(g)*150)+(16'(b)*29)) >> 8;
    endfunction

    task automatic check(input [7:0] r,g,b, input en, input [23:0] exp, input string lbl);
        @(negedge clk); rgb_in={r,g,b}; enable=en; pixel_valid=1;
        @(posedge clk); @(negedge clk);
        if (rgb_out!==exp) begin
            $error("gray %s: got 0x%06X exp 0x%06X",lbl,rgb_out,exp); errors++; end
        else $display("[%0t] gray PASS: %s → 0x%06X",$time,lbl,rgb_out);
        if (pvalid_out!==1'b1) begin
            $error("gray %s: pvalid_out not 1",lbl); errors++; end
    endtask

    initial begin
        $dumpfile("tb_pointwise_filters.vcd"); $dumpvars(0,tb_grayscale);
        reset=1; enable=1; pixel_valid=0; rgb_in=0;
        repeat(4) @(negedge clk); reset=0; repeat(2) @(negedge clk);
        $display("\n=== Grayscale Tests ===");

        // Enabled cases
        begin automatic logic [7:0] y=Y(255,255,255);
            check(255,255,255, 1, {y,y,y}, "white"); end
        check(0,0,0, 1, 24'h0, "black");
        begin automatic logic [7:0] y=Y(255,0,0);
            check(255,0,0, 1, {y,y,y}, "pure red"); end
        begin automatic logic [7:0] y=Y(0,255,0);
            check(0,255,0, 1, {y,y,y}, "pure green"); end
        begin automatic logic [7:0] y=Y(0,0,255);
            check(0,0,255, 1, {y,y,y}, "pure blue"); end
        begin automatic logic [7:0] y=Y(100,150,200);
            check(100,150,200, 1, {y,y,y}, "mixed"); end

        // Bypass (enable=0): output = input
        check(180,90,45, 0, {8'd180,8'd90,8'd45}, "bypass");

        // pixel_valid=0 → pvalid_out=0
        @(negedge clk); pixel_valid=0; rgb_in=24'hFFFFFF; enable=1;
        @(posedge clk); @(negedge clk);
        if (pvalid_out!==1'b0) begin
            $error("gray: pvalid_out should be 0 when pixel_valid=0"); errors++; end
        else $display("[%0t] gray PASS: pvalid=0 propagated",$time);

        $display("Grayscale: %0d error(s)",errors); $finish;
    end
endmodule


// =============================================================================
// BRIGHTNESS / CONTRAST
// =============================================================================
module tb_brightness_contrast;
    localparam CLK_PERIOD = 40;
    logic clk=0, reset, en_brightness, en_contrast, pixel_valid, pvalid_out;
    logic [23:0] rgb_in, rgb_out;
    int errors=0;

    brightness_contrast dut(.clk,.reset,.en_brightness,.en_contrast,
                             .pixel_valid,.rgb_in,.rgb_out,.pvalid_out);
    always #(CLK_PERIOD/2) clk=~clk;

    function automatic [7:0] exp_ch(input [7:0] v, input do_c, do_b);
        logic [8:0] t;
        t = {1'b0, v};
        if (do_c) begin t = t + {2'b0, v[7:1]}; if(t>255) t=255; end
        if (do_b) begin t = t + 9'd32;           if(t>255) t=255; end
        return t[7:0];
    endfunction

    task automatic check(input [7:0] r,g,b, input ec,eb, input string lbl);
        automatic logic [23:0] exp = {exp_ch(r,ec,eb),exp_ch(g,ec,eb),exp_ch(b,ec,eb)};
        @(negedge clk); rgb_in={r,g,b}; en_contrast=ec; en_brightness=eb; pixel_valid=1;
        @(posedge clk); @(negedge clk);
        if (rgb_out!==exp) begin
            $error("bc %s: got 0x%06X exp 0x%06X",lbl,rgb_out,exp); errors++; end
        else $display("[%0t] bc PASS: %s",$time,lbl);
    endtask

    initial begin
        reset=1; en_brightness=0; en_contrast=0; pixel_valid=0; rgb_in=0;
        repeat(4) @(negedge clk); reset=0; repeat(2) @(negedge clk);
        $display("\n=== Brightness/Contrast Tests ===");

        check(100,100,100, 0,1, "brightness only");
        check(100,100,100, 1,0, "contrast only");
        check(100,100,100, 1,1, "both");
        check(240,240,240, 0,1, "brightness saturation");
        check(200,200,200, 1,0, "contrast saturation");
        check(128, 64, 32, 0,0, "bypass");
        check(200, 50, 10, 1,1, "asymmetric both");
        check(  0,  0,  0, 1,1, "black both");
        check(255,255,255, 1,1, "white both – full clamp");

        $display("Brightness/Contrast: %0d error(s)",errors); $finish;
    end
endmodule


// =============================================================================
// CHANNEL ISOLATION
// =============================================================================
module tb_channel_isolate;
    localparam CLK_PERIOD = 40;
    logic clk=0, reset, en_R, en_G, en_B, pixel_valid, pvalid_out;
    logic [23:0] rgb_in, rgb_out;
    int errors=0;

    channel_isolate dut(.clk,.reset,.en_R,.en_G,.en_B,
                        .pixel_valid,.rgb_in,.rgb_out,.pvalid_out);
    always #(CLK_PERIOD/2) clk=~clk;

    task automatic check(
        input [7:0] r,g,b, input er,eg,eb,
        input [23:0] exp, input string lbl
    );
        @(negedge clk); rgb_in={r,g,b}; en_R=er; en_G=eg; en_B=eb; pixel_valid=1;
        @(posedge clk); @(negedge clk);
        if (rgb_out!==exp) begin
            $error("iso %s: got 0x%06X exp 0x%06X",lbl,rgb_out,exp); errors++; end
        else $display("[%0t] iso PASS: %s → 0x%06X",$time,lbl,rgb_out);
    endtask

    initial begin
        reset=1; en_R=0; en_G=0; en_B=0; pixel_valid=0; rgb_in=0;
        repeat(4) @(negedge clk); reset=0; repeat(2) @(negedge clk);
        $display("\n=== Channel Isolation Tests ===");

        // Single channel
        check(180,90,45, 1,0,0, {8'd180,8'd0, 8'd0 }, "R only");
        check(180,90,45, 0,1,0, {8'd0,  8'd90,8'd0 }, "G only");
        check(180,90,45, 0,0,1, {8'd0,  8'd0, 8'd45}, "B only");

        // Bypass (no channel selected = passthrough)
        check(180,90,45, 0,0,0, {8'd180,8'd90,8'd45}, "bypass");

        // Priority: R > G > B
        check(180,90,45, 1,1,0, {8'd180,8'd0,8'd0}, "R+G → R wins");
        check(180,90,45, 0,1,1, {8'd0,8'd90,8'd0},  "G+B → G wins");
        check(180,90,45, 1,0,1, {8'd180,8'd0,8'd0}, "R+B → R wins");
        check(180,90,45, 1,1,1, {8'd180,8'd0,8'd0}, "all → R wins");

        // Edge values
        check(  0,  0,  0, 1,0,0, 24'h000000, "R only black");
        check(255,255,255, 0,1,0, 24'h00FF00, "G only white");
        check(255,  0,255, 0,0,1, 24'h0000FF, "B only magenta");

        // pvalid_out propagation
        @(negedge clk); rgb_in={8'd10,8'd20,8'd30}; en_R=1; pixel_valid=0;
        @(posedge clk); @(negedge clk);
        if (pvalid_out!==1'b0) begin
            $error("iso: pvalid_out should be 0"); errors++; end
        else $display("[%0t] iso PASS: pvalid=0 propagated",$time);

        $display("Channel Isolation: %0d error(s)",errors); $finish;
    end
endmodule
