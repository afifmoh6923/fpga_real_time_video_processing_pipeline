///////////////////////////////////////////////////////////////////////////////
// tb_line_buffer.sv
// Testbench for line_buffer.sv
// ─────────────────────────────────────────────────────────────────────────────
// HOW THIS TESTBENCH WORKS:
//
//  The line_buffer stores the previous two rows of pixels.
//  At any column position the caller can read:
//    row0 = pixel from 2 rows ago  (oldest)
//    row1 = pixel from 1 row ago
//    row2 = current pixel (registered, 1-cycle delayed version of din)
//
//  Each camera row = 320 pixels.  Between rows: row_advance pulses.
//  Between pixels within a row: pixel_advance pulses.
//
//  Strategy:
//    Feed rows with deterministic values:
//      Row 0: pixel[col] = 24'h010101 * col   (col=0..319)
//      Row 1: pixel[col] = 24'h020202 * col
//      Row 2: pixel[col] = 24'h030303 * col
//    Then check at each column of Row 2 that:
//      row2 == Row2[col]
//      row1 == Row1[col]
//      row0 == Row0[col]
//
//  Test 1 – First two rows (row0/row1 contain zeros – not yet valid)
//    Streams rows 0 and 1 and records outputs.
//    After row 1, at column 0 of row 2 check row1 == Row1[0].
//
//  Test 2 – Full 3-row neighbourhood
//    At every column of Row 2, verifies all three outputs match the
//    expected values from the deterministic pattern.
//
//  Test 3 – Row counter wrap
//    Streams a 4th row and checks that row0 now contains Row1 data
//    (oldest row was evicted).
//
//  Test 4 – Reset
//    Asserts reset mid-stream; checks all outputs go to zero.
//
//  Timing note:
//    BRAM read latency = 1 cycle.  row0/row1 are valid ONE cycle AFTER
//    pixel_advance.  row2 = din registered by 1 cycle.
//    The TB reads outputs on the clock cycle AFTER pixel_advance.
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module tb_line_buffer;

    // ── Parameters ────────────────────────────────────────────────────────────
    localparam WIDTH      = 320;
    localparam DATA_WIDTH = 24;
    localparam CLK_PERIOD = 40;    // 25 MHz pixel_clk

    // ── Signals ───────────────────────────────────────────────────────────────
    logic                    clk;
    logic                    reset;
    logic                    pixel_advance;
    logic                    row_advance;
    logic [DATA_WIDTH-1:0]   din;
    logic [DATA_WIDTH-1:0]   row0, row1, row2;

    int error_count = 0;

    // ── DUT ───────────────────────────────────────────────────────────────────
    line_buffer #(.WIDTH(WIDTH), .DATA_WIDTH(DATA_WIDTH)) dut (
        .clk           (clk),
        .reset         (reset),
        .pixel_advance (pixel_advance),
        .row_advance   (row_advance),
        .din           (din),
        .row0          (row0),
        .row1          (row1),
        .row2          (row2)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ─────────────────────────────────────────────────────────────────────────
    // FUNCTION: expected_pixel
    //   Returns the deterministic test value for (row_num, col).
    //   row_num 0 → base=0x010101, row_num 1 → base=0x020202, etc.
    // ─────────────────────────────────────────────────────────────────────────
    function automatic logic [23:0] expected_pixel(input int row_num, input int col);
        logic [7:0] base;
        base = 8'(row_num + 1);
        return {base, base, base} + 24'(col);
    endfunction

    // ─────────────────────────────────────────────────────────────────────────
    // TASK: stream_row
    //   Streams one complete row of WIDTH pixels into the line buffer.
    //   Does NOT pulse row_advance at the end (caller does that).
    // ─────────────────────────────────────────────────────────────────────────
    task automatic stream_row(input int row_num);
        for (int col = 0; col < WIDTH; col++) begin
            @(negedge clk);
            din           = expected_pixel(row_num, col);
            pixel_advance = 1'b1;
            @(posedge clk);
            @(negedge clk);
            pixel_advance = 1'b0;
        end
    endtask

    // ─────────────────────────────────────────────────────────────────────────
    // TASK: stream_row_and_check
    //   Streams one row and simultaneously checks row0/row1/row2 outputs
    //   against expected values for rows (current-2, current-1, current).
    //   Skips checking for first 2 rows (outputs not yet valid).
    // ─────────────────────────────────────────────────────────────────────────
    task automatic stream_row_and_check(
        input int row_num,           // row being written (0-indexed)
        input bit check_outputs      // 0 = stream only, 1 = also verify
    );
        for (int col = 0; col < WIDTH; col++) begin
            @(negedge clk);
            din           = expected_pixel(row_num, col);
            pixel_advance = 1'b1;
            @(posedge clk);
            @(negedge clk);
            pixel_advance = 1'b0;

            // Outputs are valid ONE cycle after pixel_advance
            @(posedge clk);
            if (check_outputs && col >= 1) begin
                // row2 should equal what we JUST wrote (registered 1 cycle)
                if (row2 !== expected_pixel(row_num, col - 1)) begin
                    $error("Row %0d col %0d: row2=0x%06X expected 0x%06X",
                           row_num, col-1, row2, expected_pixel(row_num, col-1));
                    error_count++;
                end
                // row1 = previous row, same col
                if (row_num >= 1 && row1 !== expected_pixel(row_num-1, col-1)) begin
                    $error("Row %0d col %0d: row1=0x%06X expected 0x%06X",
                           row_num, col-1, row1, expected_pixel(row_num-1, col-1));
                    error_count++;
                end
                // row0 = two rows back, same col
                if (row_num >= 2 && row0 !== expected_pixel(row_num-2, col-1)) begin
                    $error("Row %0d col %0d: row0=0x%06X expected 0x%06X",
                           row_num, col-1, row0, expected_pixel(row_num-2, col-1));
                    error_count++;
                end
            end
        end
    endtask

    // ─────────────────────────────────────────────────────────────────────────
    // MAIN STIMULUS
    // ─────────────────────────────────────────────────────────────────────────
    initial begin
        $dumpfile("tb_line_buffer.vcd");
        $dumpvars(0, tb_line_buffer);

        // Initialise
        reset         = 1;
        pixel_advance = 0;
        row_advance   = 0;
        din           = 24'h0;

        repeat(4) @(negedge clk);
        reset = 0;
        repeat(2) @(negedge clk);

        // ── Test 1: Stream Row 0 (outputs not yet meaningful) ─────────────────
        $display("\n=== Test 1: Stream Row 0 ===");
        stream_row(0);

        // Issue row_advance between rows
        @(negedge clk);
        row_advance = 1;
        @(posedge clk);
        @(negedge clk);
        row_advance = 0;

        // ── Test 2: Stream Row 1 (row1 becomes Row0, row0 stale) ─────────────
        $display("\n=== Test 2: Stream Row 1 ===");
        stream_row(1);

        @(negedge clk);
        row_advance = 1;
        @(posedge clk);
        @(negedge clk);
        row_advance = 0;

        // ── Test 3: Stream Row 2 and verify full 3×1 neighbourhood ───────────
        $display("\n=== Test 3: Stream Row 2 and verify row0/row1/row2 ===");
        // From column 1 onward, all three outputs should be valid
        stream_row_and_check(2, 1'b1);
        $display("[%0t] Row 2 neighbourhood check done (errors so far: %0d)",
                  $time, error_count);

        @(negedge clk);
        row_advance = 1;
        @(posedge clk);
        @(negedge clk);
        row_advance = 0;

        // ── Test 4: Row 3 – verify oldest row evicted ─────────────────────────
        $display("\n=== Test 4: Row 3 – Row0 should now be Row1 data ===");
        // After writing row 3, row0 should be row1 data (row 1), row1 = row 2
        stream_row_and_check(3, 1'b1);
        $display("[%0t] Row 3 eviction check done", $time);

        @(negedge clk);
        row_advance = 1;
        @(posedge clk);
        @(negedge clk);
        row_advance = 0;

        // ── Test 5: Reset clears outputs ──────────────────────────────────────
        $display("\n=== Test 5: Reset mid-stream ===");
        // Start sending row 4
        @(negedge clk);
        din           = 24'hABCDEF;
        pixel_advance = 1'b1;
        @(posedge clk);
        @(negedge clk);
        pixel_advance = 0;

        // Assert reset
        reset = 1;
        repeat(3) @(negedge clk);
        reset = 0;
        @(posedge clk);

        // Outputs should be zero
        if (row0 !== 24'h0 || row1 !== 24'h0 || row2 !== 24'h0) begin
            $error("T5: Outputs not zeroed after reset (row0=%06X row1=%06X row2=%06X)",
                   row0, row1, row2);
            error_count++;
        end else begin
            $display("[%0t] T5: All outputs zero after reset ✓", $time);
        end

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
