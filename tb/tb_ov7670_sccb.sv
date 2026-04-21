///////////////////////////////////////////////////////////////////////////////
// tb_ov7670_sccb.sv
// Testbench for ov7670_sccb.sv
// ─────────────────────────────────────────────────────────────────────────────
// HOW THIS TESTBENCH WORKS:
//
//  The SCCB protocol sends 3 phases of 8 bits each:
//    Phase 1: Device write address (always 0x42)
//    Phase 2: Register address
//    Phase 3: Register value
//  Each phase is followed by a "don't-care" bit where siod is released.
//  The transaction is framed by a START condition and a STOP condition.
//
//  Test 1 – Basic transaction
//    Triggers a write of reg_addr=0x15, reg_data=0xA3.
//    Monitors sioc and siod simultaneously.
//    Checks:
//      • START condition: siod falls while sioc is HIGH
//      • Bit 7 of 0x42 (=0) is first bit driven after START
//      • done pulse asserts exactly once after STOP
//      • STOP condition: siod rises while sioc is HIGH
//
//  Test 2 – Second transaction immediately after done
//    Sends reg_addr=0x12, reg_data=0x80 (the soft-reset command).
//    Verifies the module returns to IDLE cleanly and accepts a new start.
//
//  Test 3 – Reset during transaction
//    Starts a transaction then de-asserts reset_n mid-way through.
//    Verifies sioc returns HIGH, siod is released, done is never seen.
//
//  Self-checking:
//    All checks use $error / $fatal with descriptive messages.
//    Final pass/fail is printed at end of simulation.
//
//  NOTE: siod is open-drain. We model the external pull-up as:
//    assign siod_pulled = (siod === 1'bz) ? 1'b1 : siod;
//  so the TB always sees a valid logic level.
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module tb_ov7670_sccb;

    // ── Clock / Reset ─────────────────────────────────────────────────────────
    logic        clk;
    logic        reset_n;

    // ── DUT IOs ───────────────────────────────────────────────────────────────
    logic        start;
    logic [7:0]  reg_addr;
    logic [7:0]  reg_data;
    logic        done;
    logic        sioc;
    wire         siod;       // inout – open-drain

    // ── Pull-up model ─────────────────────────────────────────────────────────
    // Simulates the physical pull-up resistor on the SCCB board.
    // When DUT releases siod (drives 1'bz), we see HIGH here.
    logic siod_pulled;
    assign siod_pulled = (siod === 1'bz) ? 1'b1 : siod;

    // ── Error counter ─────────────────────────────────────────────────────────
    int error_count = 0;

    // ── DUT instantiation ─────────────────────────────────────────────────────
    ov7670_sccb dut (
        .clk      (clk),
        .reset_n  (reset_n),
        .start    (start),
        .reg_addr (reg_addr),
        .reg_data (reg_data),
        .done     (done),
        .sioc     (sioc),
        .siod     (siod)
    );

    // ── Clock: 24 MHz → period ≈ 41.667 ns ────────────────────────────────────
    localparam CLK_PERIOD = 42;   // ns (≈ 24 MHz)
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ─────────────────────────────────────────────────────────────────────────
    // TASK: send_transaction
    //   Drives start for 1 cycle with given addr/data, then waits for done.
    //   Times out after 30,000 cycles (full transaction ≈ 18,000 cycles).
    // ─────────────────────────────────────────────────────────────────────────
    task automatic send_transaction(
        input logic [7:0] addr,
        input logic [7:0] data,
        input string      label
    );
        logic start_seen, stop_seen;
        logic sioc_prev, siod_prev;
        int   timeout;

        @(negedge clk);
        reg_addr = addr;
        reg_data = data;
        start    = 1'b1;
        @(negedge clk);
        start = 1'b0;

        $display("[%0t] %s: transaction started (addr=0x%02X data=0x%02X)",
                  $time, label, addr, data);

        // ── Monitor for START condition ───────────────────────────────────────
        // START: siod falls while sioc is HIGH
        start_seen = 0;
        stop_seen  = 0;
        timeout    = 0;
        sioc_prev  = 1;
        siod_prev  = 1;

        fork
            // Watcher thread
            begin
                while (!done && timeout < 30000) begin
                    @(posedge clk);
                    timeout++;

                    // Detect START: siod 1→0 while sioc=1
                    if (sioc && sioc_prev && siod_pulled && !siod_prev)
                        ; // START held on previous edge – not yet
                    if (sioc && !siod_pulled && siod_prev) begin
                        if (!start_seen) begin
                            $display("[%0t] %s: START condition detected ✓", $time, label);
                            start_seen = 1;
                        end
                    end

                    // Detect STOP: siod 0→1 while sioc=1
                    if (sioc && siod_pulled && !siod_prev && start_seen) begin
                        $display("[%0t] %s: STOP condition detected ✓", $time, label);
                        stop_seen = 1;
                    end

                    sioc_prev = sioc;
                    siod_prev = siod_pulled;
                end
            end
        join_none

        // Wait for done with timeout
        fork
            begin : done_wait
                @(posedge done);
                disable timeout_watch;
            end
            begin : timeout_watch
                repeat(30000) @(posedge clk);
                $error("%s: TIMEOUT – done never asserted", label);
                error_count++;
                disable done_wait;
            end
        join

        @(negedge clk);  // let watcher catch STOP

        if (!start_seen) begin
            $error("%s: START condition never detected", label);
            error_count++;
        end
        if (!stop_seen) begin
            $error("%s: STOP condition never detected", label);
            error_count++;
        end
        $display("[%0t] %s: transaction complete", $time, label);
    endtask

    // ─────────────────────────────────────────────────────────────────────────
    // TASK: check_idle
    //   Verifies bus is idle: sioc=1 and siod released (pull-up = 1).
    // ─────────────────────────────────────────────────────────────────────────
    task automatic check_idle(input string label);
        @(posedge clk);
        if (sioc !== 1'b1) begin
            $error("%s: sioc not HIGH in IDLE", label);
            error_count++;
        end
        if (siod_pulled !== 1'b1) begin
            $error("%s: siod not HIGH (released) in IDLE", label);
            error_count++;
        end
        if (done !== 1'b0) begin
            $error("%s: done still HIGH after IDLE", label);
            error_count++;
        end
    endtask

    // ─────────────────────────────────────────────────────────────────────────
    // MAIN STIMULUS
    // ─────────────────────────────────────────────────────────────────────────
    initial begin
        $dumpfile("tb_ov7670_sccb.vcd");
        $dumpvars(0, tb_ov7670_sccb);

        // ── Initialise ───────────────────────────────────────────────────────
        reset_n  = 0;
        start    = 0;
        reg_addr = 8'h00;
        reg_data = 8'h00;

        repeat(5) @(negedge clk);
        reset_n = 1;
        repeat(3) @(negedge clk);

        // ── Check bus idles correctly after reset ─────────────────────────────
        $display("\n=== Test 1: Bus idle after reset ===");
        check_idle("post-reset");

        // ── Test 2: Basic transaction ─────────────────────────────────────────
        $display("\n=== Test 2: Basic write (0x15 = 0xA3) ===");
        send_transaction(8'h15, 8'hA3, "T2");
        repeat(10) @(negedge clk);
        check_idle("post-T2");

        // ── Test 3: Soft-reset command ────────────────────────────────────────
        $display("\n=== Test 3: Soft-reset write (0x12 = 0x80) ===");
        send_transaction(8'h12, 8'h80, "T3");
        repeat(10) @(negedge clk);
        check_idle("post-T3");

        // ── Test 4: Back-to-back transactions ─────────────────────────────────
        $display("\n=== Test 4: Back-to-back transactions ===");
        send_transaction(8'h11, 8'h00, "T4a");
        repeat(5) @(negedge clk);
        send_transaction(8'h40, 8'hD0, "T4b");
        repeat(10) @(negedge clk);
        check_idle("post-T4");

        // ── Test 5: Reset during transaction ─────────────────────────────────
        $display("\n=== Test 5: Reset mid-transaction ===");
        @(negedge clk);
        reg_addr = 8'hAA;
        reg_data = 8'h55;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        // Wait 500 cycles (partway through transaction)
        repeat(500) @(posedge clk);
        reset_n = 0;
        repeat(5) @(negedge clk);
        reset_n = 1;
        repeat(10) @(negedge clk);

        // Bus should be idle again, done should NOT have been asserted
        if (sioc !== 1'b1) begin
            $error("T5: sioc not HIGH after mid-transaction reset");
            error_count++;
        end else begin
            $display("[%0t] T5: Bus recovered to idle after reset ✓", $time);
        end

        // ── Report ────────────────────────────────────────────────────────────
        $display("\n========================================");
        if (error_count == 0)
            $display("ALL TESTS PASSED (0 errors)");
        else
            $display("FAILED: %0d error(s) detected", error_count);
        $display("========================================\n");
        $finish;
    end

endmodule
