///////////////////////////////////////////////////////////////////////////////
// text_overlay.sv
// ECE 385 Final Project – Real-Time FPGA Video Processing Pipeline
//
// TEXT OVERLAY ENGINE
// ─────────────────────────────────────────────────────────────────────────────
// Renders the active-filter name string (e.g. "GRAY + EDGE + BLUR") in the
// top-left corner of the HDMI output using a ROM-backed bitmap font.
//
// Font ROM:
//   Copy font_rom.sv directly from the AXI lab into this project.
//   It provides 128 IBM Codepage 437 glyphs, 8 pixels wide × 16 pixels tall.
//   Port: addr[10:4] = glyph index (ASCII), addr[3:0] = row within glyph
//         data[7:0]  = 8 pixels; bit 7 = leftmost pixel; 1 = foreground
//   BRAM-backed: 1-cycle read latency.
//
// Banner geometry:
//   One text row at the very top of the screen.
//   drawY ∈ [0, 15] (16 rows = 1 glyph height).
//   drawX ∈ [0, text_len*8 - 1] (only behind actual characters).
//
// Colors:
//   Foreground : 24'hFFFF00 (yellow)
//   Background : 24'h000080 (dark navy blue)
//   Outside banner: video_in passes unchanged.
//
// Pipeline depth: 2 clock cycles  (1 BRAM read + 1 output register).
//   video_in and pixel_valid must be delayed 2 cycles to align.
//
// Vsync latching:
//   text_buf is rebuilt combinationally from SW every cycle.
//   At each vsync falling edge the combinational result is latched into
//   text_buf_stable so that a full frame always uses a consistent string.
//   This prevents visual tearing when switches toggle mid-frame.
//
// Requires: font_rom.sv from AXI lab copied into project source directory.
///////////////////////////////////////////////////////////////////////////////

module text_overlay (
    input  logic        pixel_clk,
    input  logic        reset,

    // VGA scan position
    input  logic [9:0]  drawX,
    input  logic [9:0]  drawY,
    input  logic        vs,             // vsync from vga_controller (active-low)

    // Filter switch state (synchronised)
    input  logic [15:0] SW,

    // Video pixel from filter_pipeline
    input  logic [23:0] video_in,
    input  logic        pixel_valid,

    // Output with text overlaid
    output logic [23:0] video_out,
    output logic        pvalid_out
);

    // =========================================================================
    // PARAMETERS
    // =========================================================================
    localparam [23:0] FG_COLOR = 24'hFFFF00;   // Yellow text
    localparam [23:0] BG_COLOR = 24'h000080;   // Dark navy banner
    localparam        MAX_CHARS = 40;
    localparam        CHAR_W    = 8;
    localparam        CHAR_H    = 16;

    // =========================================================================
    // STRING TOKEN LOCALPARMS
    // =========================================================================
    // Each token is a packed byte array of its ASCII characters.
    // Assembling these into text_buf happens in the always_comb block below.
    //
    // PSEUDO-CODE for tokens (implement as localparam byte arrays):
    //   T_GRAY   = "GRAY"          (4 chars)
    //   T_EDGE   = "EDGE"          (4 chars)
    //   T_BLUR   = "BLUR"          (4 chars)
    //   T_SHARP  = "SHARP"         (5 chars)
    //   T_BRIGHT = "BRIGHT"        (6 chars)
    //   T_CONT   = "CONT"          (4 chars)
    //   T_RED    = "RED"           (3 chars)
    //   T_GREEN  = "GREEN"         (5 chars)
    //   T_BLUE   = "BLUE"          (4 chars)
    //   T_SEP    = " + "           (3 chars)
    //   T_PASS   = "PASSTHROUGH"   (11 chars)

    // =========================================================================
    // TEXT BUFFER  (combinational, then latched at vsync)
    // =========================================================================
    logic [7:0] text_buf       [0:MAX_CHARS-1];  // combinational assembly
    logic [7:0] text_buf_stable[0:MAX_CHARS-1];  // vsync-latched stable copy
    logic [5:0] text_len;
    logic [5:0] text_len_stable;

    // ── Vsync falling-edge detector ───────────────────────────────────────────
    logic vs_prev;
    logic vsync_fall;
    always_ff @(posedge pixel_clk) vs_prev <= vs;
    assign vsync_fall = vs_prev & ~vs;    // vsync is active-low: fall = 1→0

    // ── Latch stable copy at vsync ────────────────────────────────────────────
    always_ff @(posedge pixel_clk) begin
        if (vsync_fall) begin
            text_buf_stable <= text_buf;
            text_len_stable <= text_len;
        end
    end

    // =========================================================================
    // STRING BUILDER  (always_comb)
    // =========================================================================
    // PSEUDO-CODE:
    //
    // Always fill text_buf with spaces (0x20) first, then overwrite with tokens.
    // Use a write pointer (ptr) that increments as tokens are appended.
    //
    // Macro-style helper (unroll manually in real SV):
    //   task append(input byte chars[], input int n):
    //       for i in 0..n-1:
    //           text_buf[ptr + i] = chars[i]
    //       ptr += n
    //
    // if (SW[9:0] == 0):
    //   append(T_PASS, 11)          → "PASSTHROUGH"
    // else:
    //   any_printed = 0
    //   if (SW[3]): if(any_printed): append(T_SEP,3)
    //               append(T_BRIGHT,6); any_printed=1
    //   if (SW[4]): if(any_printed): append(T_SEP,3)
    //               append(T_CONT,4);  any_printed=1
    //   if (SW[5]): if(any_printed): append(T_SEP,3)
    //               append(T_RED,3);   any_printed=1
    //   if (SW[6]): if(any_printed): append(T_SEP,3)
    //               append(T_GREEN,5); any_printed=1
    //   if (SW[7]): if(any_printed): append(T_SEP,3)
    //               append(T_BLUE,4);  any_printed=1
    //   if (SW[0]): if(any_printed): append(T_SEP,3)
    //               append(T_GRAY,4);  any_printed=1
    //   if (SW[2]): if(any_printed): append(T_SEP,3)
    //               append(T_BLUR,4);  any_printed=1
    //   if (SW[8]): if(any_printed): append(T_SEP,3)
    //               append(T_SHARP,5); any_printed=1
    //   if (SW[1]): if(any_printed): append(T_SEP,3)
    //               append(T_EDGE,4);  any_printed=1
    //   text_len = ptr
    //
    // NOTE: In synthesisable SystemVerilog, the "task" above must be unrolled
    // into explicit index assignments.  Use a local integer ptr and write each
    // character as: text_buf[ptr] = 8'h??; ptr = ptr + 1; within always_comb.
    // Vivado will optimise the resulting mux tree efficiently.
    always_comb begin
        // Default: fill with spaces
        for (int k = 0; k < MAX_CHARS; k++)
            text_buf[k] = 8'h20;
        text_len = 6'd0;

        // IMPLEMENT: unrolled string concatenation as described above
        // Example snippet for one token (GRAY, SW[0]):
        //
        // if (SW[0]) begin
        //     if (text_len > 0) begin            // separator
        //         text_buf[text_len]   = 8'h20;  // ' '
        //         text_buf[text_len+1] = 8'h2B;  // '+'
        //         text_buf[text_len+2] = 8'h20;  // ' '
        //         text_len = text_len + 3;
        //     end
        //     text_buf[text_len]   = 8'h47;      // 'G'
        //     text_buf[text_len+1] = 8'h52;      // 'R'
        //     text_buf[text_len+2] = 8'h41;      // 'A'
        //     text_buf[text_len+3] = 8'h59;      // 'Y'
        //     text_len = text_len + 4;
        // end
        //
        // Repeat for every token in the priority order above.
        // The PASSTHROUGH case when no switches are on:
        // if (SW[8:0] == 9'b0) begin
        //     text_buf[0]="P"; text_buf[1]="A"; text_buf[2]="S";
        //     text_buf[3]="S"; text_buf[4]="T"; text_buf[5]="H";
        //     text_buf[6]="R"; text_buf[7]="O"; text_buf[8]="U";
        //     text_buf[9]="G"; text_buf[10]="H";
        //     text_len = 11;
        // end
    end

    // =========================================================================
    // FONT ROM LOOKUP
    // =========================================================================
    // Determine if the current scan position is inside the text banner.
    logic        in_banner;
    logic [5:0]  char_col;    // which character (0..39)
    logic [2:0]  pixel_col;   // pixel within character horizontally (0..7)
    logic [3:0]  pixel_row;   // pixel row within character (0..15)
    logic [7:0]  cur_glyph;
    logic [10:0] font_addr;
    logic [7:0]  font_bits;   // output from font_rom (1-cycle latency)

    assign in_banner  = (drawY <= 10'd15) && (drawX < {4'b0, text_len_stable, 3'b0});
    assign char_col   = drawX[8:3];      // drawX / 8
    assign pixel_col  = drawX[2:0];      // drawX % 8
    assign pixel_row  = drawY[3:0];      // drawY % 16
    assign cur_glyph  = text_buf_stable[char_col];
    assign font_addr  = {cur_glyph[6:0], pixel_row};

    // Reuse font_rom.sv from the AXI lab (copy into project)
    font_rom font_rom_inst (
        .clk  (pixel_clk),
        .addr (font_addr),
        .data (font_bits)
    );

    // =========================================================================
    // PIPELINE REGISTERS  (compensate for 1-cycle BRAM latency)
    // =========================================================================
    logic        in_banner_d;
    logic [2:0]  pixel_col_d;
    logic [23:0] video_in_d1, video_in_d2;
    logic        pv_d1, pv_d2;

    always_ff @(posedge pixel_clk) begin
        in_banner_d  <= in_banner;
        pixel_col_d  <= pixel_col;
        video_in_d1  <= video_in;
        video_in_d2  <= video_in_d1;
        pv_d1        <= pixel_valid;
        pv_d2        <= pv_d1;
    end

    // =========================================================================
    // OUTPUT COMPOSITOR
    // =========================================================================
    // PSEUDO-CODE:
    //   font_pixel = font_bits[7 - pixel_col_d]  (MSB = leftmost)
    //
    //   if (in_banner_d && pv_d2):
    //       if (font_pixel): video_out = FG_COLOR  (yellow text)
    //       else:            video_out = BG_COLOR  (navy banner)
    //   else:
    //       video_out = video_in_d2  (pass filtered video through)
    logic font_pixel;
    assign font_pixel = font_bits[3'd7 - pixel_col_d];

    always_ff @(posedge pixel_clk) begin
        if (reset) begin
            video_out  <= 24'h0;
            pvalid_out <= 1'b0;
        end else begin
            pvalid_out <= pv_d2;
            if (in_banner_d && pv_d2)
                video_out <= font_pixel ? FG_COLOR : BG_COLOR;
            else
                video_out <= video_in_d2;
        end
    end

endmodule
