///////////////////////////////////////////////////////////////////////////////
// text_overlay.sv
// ECE 385 Final Project – Real-Time FPGA Video Processing Pipeline
//
// TEXT OVERLAY ENGINE
// ─────────────────────────────────────────────────────────────────────────────
// Renders the active-filter name string (e.g. "GRAY + EDGE + BLUR") in the
// top-left corner of the HDMI output using a ROM-backed bitmap font.
//
// HOW IT WORKS (high level):
//   1. Every frame, a combinational block (always_comb) looks at which switches
//      are ON and assembles a string like "BRIGHT + BLUR + EDGE" into text_buf,
//      a byte array of ASCII character codes.
//
//   2. At the falling edge of vsync, that string is latched into text_buf_stable
//      so the entire frame uses a consistent string even if switches toggle.
//
//   3. For every pixel in the top 16 rows of the screen (the "banner"), the
//      module figures out:
//        - which character in the string this pixel belongs to  (char_col = drawX/8)
//        - which pixel column within that 8-wide glyph           (pixel_col = drawX%8)
//        - which pixel row within the 16-tall glyph              (pixel_row = drawY%16)
//      It looks up the ASCII code for that character, forms a font_rom address,
//      and reads the 8-bit bitmap row from the font ROM.
//
//   4. One cycle later (font ROM has 1-cycle latency), the relevant bit of the
//      8-bit bitmap row is tested.  If it's '1' the pixel is foreground (yellow);
//      if '0' it's background (navy).  Outside the banner, the filtered video
//      passes through unchanged.
//
//   5. video_in is delayed 2 cycles to stay aligned with the 2-cycle pipeline
//      (1 cycle font ROM read + 1 cycle output register).
//
// Font ROM interface (font_rom.sv from AXI lab):
//   addr[10:4] = ASCII code (7 bits, supports 0x00–0x7F)
//   addr[3:0]  = row within glyph (0 = top row, 15 = bottom row)
//   data[7:0]  = 8 pixels; bit[7] is the LEFTMOST pixel; 1 = draw foreground
//   1-cycle synchronous read latency.
///////////////////////////////////////////////////////////////////////////////
 
module text_overlay (
    input  logic        pixel_clk,
    input  logic        reset,
 
    // VGA scan position
    input  logic [9:0]  drawX,
    input  logic [9:0]  drawY,
    input  logic        vs,             // vsync from vga_controller (active-low)
 
    // Filter switch state (synchronised into pixel_clk domain)
    input  logic [15:0] SW,
 
    // Video pixel coming in from filter_pipeline
    input  logic [23:0] video_in,
    input  logic        pixel_valid,
 
    // Output with text overlaid on top
    output logic [23:0] video_out,
    output logic        pvalid_out
);
 
    // =========================================================================
    // DISPLAY PARAMETERS
    // =========================================================================
    localparam [23:0] FG_COLOR  = 24'hFFFF00;  // Yellow  – foreground (text)
    localparam [23:0] BG_COLOR  = 24'h000000;  // BLACK    – banner background
    localparam        MAX_CHARS = 80;           // maximum characters in one line
    localparam        CHAR_W    = 8;            // glyph width  in pixels
    localparam        CHAR_H    = 16;           // glyph height in pixels
 
    // =========================================================================
    // TEXT BUFFER
    // =========================================================================
    // text_buf       – rebuilt combinationally every cycle from SW
    // text_buf_stable– latched copy used for rendering; only updated at vsync
    //                  so every frame shows a consistent label even if the user
    //                  flips a switch mid-frame
    // text_len / text_len_stable – how many characters are actually in the string
    logic [7:0] text_buf        [0:MAX_CHARS-1];
    logic [7:0] text_buf_stable [0:MAX_CHARS-1];
    logic [6:0] text_len;
    logic [6:0] text_len_stable;
 
    // ── Vsync falling-edge detector ──────────────────────────────────────────
    // vsync is active-low, so a falling edge (1→0) marks the start of vblank.
    // We latch the string at this point so we get a consistent frame.
    logic vs_prev;
    always_ff @(posedge pixel_clk) vs_prev <= vs;
    logic vsync_fall;
    assign vsync_fall = vs_prev & ~vs;   // 1 for exactly one cycle at vsync fall
 
    // ── Latch stable copy at vsync ───────────────────────────────────────────
    // Also initialize to spaces on reset so the banner shows immediately
    // without waiting for the first vsync falling edge.
    always_ff @(posedge pixel_clk) begin
        if (reset) begin
            for (int k = 0; k < MAX_CHARS; k++)
                text_buf_stable[k] <= 8'h20;  // spaces
            text_len_stable <= 7'd0;
        end else if (vsync_fall) begin
            text_buf_stable <= text_buf;
            text_len_stable <= text_len;
        end
    end
 
    // =========================================================================
    // STRING BUILDER  (combinational)
    // =========================================================================
    // We walk through the switches in a fixed display priority order and append
    // a token for each active filter.  Between tokens we insert " + ".
    // If no filter is active we write "PASSTHROUGH".
    //
    // Implementation trick: we use an integer write-pointer 'ptr' that starts
    // at 0 and advances as characters are written.  Because this is always_comb,
    // Vivado sees it as a big mux tree and synthesises it efficiently.
    //
    // ASCII quick-ref for characters used:
    //   ' '=0x20  '+'=0x2B  'A'=0x41  'B'=0x42  'C'=0x43  'D'=0x44
    //   'E'=0x45  'G'=0x47  'H'=0x48  'I'=0x49  'L'=0x4C  'N'=0x4E
    //   'O'=0x4F  'P'=0x50  'R'=0x52  'S'=0x53  'T'=0x54  'U'=0x55
    //   'Y'=0x59
    always_comb begin
        // Default: fill entire buffer with spaces so unused slots are blank
        for (int k = 0; k < MAX_CHARS; k++)
            text_buf[k] = 8'h20;   // ASCII space
        text_len = 7'd1;  // start at 1: index 0 is reserved as leading space
 
        // Helper macro (unrolled inline below):
        //   append_sep  – writes " + " when something was already printed
        //   append_XXXX – writes the token characters and advances text_len
 
        if (SW[8:0] == 9'b0) begin
            // ── No filters active → show "PASSTHROUGH" ────────────────────
            text_buf[1]  = 8'h50; // P
            text_buf[2]  = 8'h41; // A
            text_buf[3]  = 8'h53; // S
            text_buf[4]  = 8'h53; // S
            text_buf[5]  = 8'h54; // T
            text_buf[6]  = 8'h48; // H
            text_buf[7]  = 8'h52; // R
            text_buf[8]  = 8'h4F; // O
            text_buf[9]  = 8'h55; // U
            text_buf[10] = 8'h47; // G
            text_buf[11] = 8'h48; // H
            text_len = 7'd12;
        end else begin
            // ── BRIGHT  (SW[3]) ──────────────────────────────────────────────
            if (SW[3]) begin
                if (text_len > 0) begin
                    text_buf[text_len]   = 8'h20;
                    text_buf[text_len+1] = 8'h2B;
                    text_buf[text_len+2] = 8'h20;
                    text_len = text_len + 3;
                end
                text_buf[text_len]   = 8'h42; // B
                text_buf[text_len+1] = 8'h52; // R
                text_buf[text_len+2] = 8'h49; // I
                text_buf[text_len+3] = 8'h47; // G
                text_buf[text_len+4] = 8'h48; // H
                text_buf[text_len+5] = 8'h54; // T
                text_len = text_len + 6;
            end
 
            // ── CONT  (SW[4]) ────────────────────────────────────────────────
            if (SW[4]) begin
                if (text_len > 0) begin        // separator " + "
                    text_buf[text_len]   = 8'h20; // (space)
                    text_buf[text_len+1] = 8'h2B; // +
                    text_buf[text_len+2] = 8'h20; // (space)
                    text_len = text_len + 3;
                end
                text_buf[text_len]   = 8'h43; // C
                text_buf[text_len+1] = 8'h4F; // O
                text_buf[text_len+2] = 8'h4E; // N
                text_buf[text_len+3] = 8'h54; // T
                text_len = text_len + 4;
            end
 
            // ── RED  (SW[5]) ─────────────────────────────────────────────────
            if (SW[5]) begin
                if (text_len > 0) begin
                    text_buf[text_len]   = 8'h20;
                    text_buf[text_len+1] = 8'h2B;
                    text_buf[text_len+2] = 8'h20;
                    text_len = text_len + 3;
                end
                text_buf[text_len]   = 8'h52; // R
                text_buf[text_len+1] = 8'h45; // E
                text_buf[text_len+2] = 8'h44; // D
                text_len = text_len + 3;
            end
 
            // ── GREEN  (SW[6]) ───────────────────────────────────────────────
            if (SW[6]) begin
                if (text_len > 0) begin
                    text_buf[text_len]   = 8'h20;
                    text_buf[text_len+1] = 8'h2B;
                    text_buf[text_len+2] = 8'h20;
                    text_len = text_len + 3;
                end
                text_buf[text_len]   = 8'h47; // G
                text_buf[text_len+1] = 8'h52; // R
                text_buf[text_len+2] = 8'h45; // E
                text_buf[text_len+3] = 8'h45; // E
                text_buf[text_len+4] = 8'h4E; // N
                text_len = text_len + 5;
            end
 
            // ── BLUE  (SW[7]) ────────────────────────────────────────────────
            if (SW[7]) begin
                if (text_len > 0) begin
                    text_buf[text_len]   = 8'h20;
                    text_buf[text_len+1] = 8'h2B;
                    text_buf[text_len+2] = 8'h20;
                    text_len = text_len + 3;
                end
                text_buf[text_len]   = 8'h42; // B
                text_buf[text_len+1] = 8'h4C; // L
                text_buf[text_len+2] = 8'h55; // U
                text_buf[text_len+3] = 8'h45; // E
                text_len = text_len + 4;
            end
 
            // ── GRAY  (SW[0]) ────────────────────────────────────────────────
            if (SW[11]) begin
                if (text_len > 0) begin
                    text_buf[text_len]   = 8'h20;
                    text_buf[text_len+1] = 8'h2B;
                    text_buf[text_len+2] = 8'h20;
                    text_len = text_len + 3;
                end
                text_buf[text_len]   = 8'h47; // G
                text_buf[text_len+1] = 8'h52; // R
                text_buf[text_len+2] = 8'h41; // A
                text_buf[text_len+3] = 8'h59; // Y
                text_len = text_len + 4;
            end
 
            // ── BLUR  (SW[2]) ────────────────────────────────────────────────
            if (SW[2]) begin
                if (text_len > 0) begin
                    text_buf[text_len]   = 8'h20;
                    text_buf[text_len+1] = 8'h2B;
                    text_buf[text_len+2] = 8'h20;
                    text_len = text_len + 3;
                end
                text_buf[text_len]   = 8'h42; // B
                text_buf[text_len+1] = 8'h4C; // L
                text_buf[text_len+2] = 8'h55; // U
                text_buf[text_len+3] = 8'h52; // R
                text_len = text_len + 4;
            end
 
            // ── SHARP  (SW[8]) ───────────────────────────────────────────────
            if (SW[8]) begin
                if (text_len > 0) begin
                    text_buf[text_len]   = 8'h20;
                    text_buf[text_len+1] = 8'h2B;
                    text_buf[text_len+2] = 8'h20;
                    text_len = text_len + 3;
                end
                text_buf[text_len]   = 8'h53; // S
                text_buf[text_len+1] = 8'h48; // H
                text_buf[text_len+2] = 8'h41; // A
                text_buf[text_len+3] = 8'h52; // R
                text_buf[text_len+4] = 8'h50; // P
                text_len = text_len + 5;
            end
 
            // ── EDGE  (SW[1]) ────────────────────────────────────────────────
            if (SW[1]) begin
                if (text_len > 0) begin
                    text_buf[text_len]   = 8'h20;
                    text_buf[text_len+1] = 8'h2B;
                    text_buf[text_len+2] = 8'h20;
                    text_len = text_len + 3;
                end
                text_buf[text_len]   = 8'h45; // E
                text_buf[text_len+1] = 8'h44; // D
                text_buf[text_len+2] = 8'h47; // G
                text_buf[text_len+3] = 8'h45; // E
                text_len = text_len + 4;
            end
                        // ── EMBOSS (SW[9]) ────────────────────────────────────────────────
            if (SW[9]) begin
                if (text_len > 0) begin
                    text_buf[text_len]   = 8'h20;
                    text_buf[text_len+1] = 8'h2B;
                    text_buf[text_len+2] = 8'h20;
                    text_len = text_len + 3;
                end
                text_buf[text_len]   = 8'h45; // E
                text_buf[text_len+1] = 8'h4D; // M
                text_buf[text_len+2] = 8'h42; // B
                text_buf[text_len+3] = 8'h4F; // O
                text_buf[text_len+4] = 8'h53; // S
                text_buf[text_len+5] = 8'h53; // S
                text_len = text_len + 6;
            end
 
            // ── INVERT (SW[12]) ───────────────────────────────────────────────
            if (SW[12]) begin
                if (text_len > 0) begin
                    text_buf[text_len]   = 8'h20;
                    text_buf[text_len+1] = 8'h2B;
                    text_buf[text_len+2] = 8'h20;
                    text_len = text_len + 3;
                end
                text_buf[text_len]   = 8'h49; // I
                text_buf[text_len+1] = 8'h4E; // N
                text_buf[text_len+2] = 8'h56; // V
                text_buf[text_len+3] = 8'h45; // E
                text_buf[text_len+4] = 8'h52; // R
                text_buf[text_len+5] = 8'h54; // T
                text_len = text_len + 6;
            end
        end
    end
 
    // =========================================================================
    // FONT ROM LOOKUP
    // =========================================================================
    // For any pixel in the top 16 rows and within the text region:
    //   char_col  = which character in the string (drawX / 8)
    //   pixel_col = which bit within the 8-pixel-wide glyph (drawX % 8)
    //   pixel_row = which of the 16 rows within the glyph (drawY % 16 = drawY[3:0])
    //
    // font_addr = {ASCII_code[6:0], pixel_row[3:0]}  (11 bits total)
    // The font ROM returns an 8-bit value where bit[7] is the leftmost pixel.
    //
    // in_banner is true when drawX is within the rendered text width.
    // We multiply text_len_stable by 8 by shifting left 3 (each char is 8px wide).
    logic        in_banner;
    logic [6:0]  char_col;    // character index (0..79)
    logic [2:0]  pixel_col;   // pixel column within glyph (0..7)
    logic [3:0]  pixel_row;   // pixel row within glyph (0..15)
    logic [7:0]  cur_glyph;   // ASCII code of the character at char_col
    logic [10:0] font_addr;   // address into font ROM
    logic [7:0]  font_bits;   // 8-pixel bitmap row from font ROM (1-cycle latency)
 
    // in_banner covers the full top 16 rows across the entire screen width.
    // The navy background fills all of it; text glyphs only render where
    // char_col < text_len_stable (handled in font lookup via space character 0x20).
    logic [9:0] banner_width;
    logic [9:0] drawX_next;
    assign drawX_next  = drawX;  // no offset needed - leading space in string handles alignment
    assign banner_width = {3'b0, text_len_stable, 3'b0}; // text_len * 8 (never 0 since text_len starts at 1)
    assign in_banner = (drawY <= 10'd15) && (drawX_next < banner_width);
    assign char_col  = drawX_next[9:3];   // (drawX+1) / 8
    assign pixel_col = drawX_next[2:0];   // (drawX+1) % 8// drawX % 8  (lower 3 bits)
    assign pixel_row = drawY[3:0];   // drawY % 16 (lower 4 bits; same as drawY since drawY<=15)
    // Use space (0x20) for any column beyond text_len_stable so extra area shows as blank navy
    assign cur_glyph = (char_col < text_len_stable) ? text_buf_stable[char_col] : 8'h20;
    assign font_addr = {cur_glyph[6:0], pixel_row};  // 7-bit ASCII + 4-bit row = 11 bits
 
    // Font ROM from AXI lab – must be included in project sources
    font_rom font_rom_inst (
        .addr (font_addr),
        .data (font_bits)
    );
 
    // =========================================================================
    // DELAY REGISTERS
    // =========================================================================
    // font_rom is purely combinational (assign data = ROM[addr]) so font_bits
    // is valid the SAME cycle as font_addr - zero latency.
    // The only pipeline stage is the output register below (1 cycle).
    // Delay video_in and pixel_valid by 1 cycle to align with output register.
    // Use in_banner and pixel_col DIRECTLY - no extra delay needed.
    logic [23:0] video_in_d1;
    logic        pv_d1;

    always_ff @(posedge pixel_clk) begin
        video_in_d1 <= video_in;
        pv_d1       <= pixel_valid;
    end

    // =========================================================================
    // OUTPUT COMPOSITOR
    // =========================================================================
    // font_bits[7] is the leftmost pixel; font_bits[0] is the rightmost.
    // font_pixel = font_bits[7 - pixel_col] picks the correct column bit.
    //
    // In banner (top 16 rows): yellow text on navy background.
    // Outside banner: pass video_in through unchanged (1-cycle delayed to match).
    logic font_pixel;
    assign font_pixel = font_bits[3'd7 - pixel_col];

    always_ff @(posedge pixel_clk) begin
        if (reset) begin
            video_out  <= 24'h0;
            pvalid_out <= 1'b0;
        end else begin
            pvalid_out <= pv_d1;
            if (in_banner)
                video_out <= font_pixel ? FG_COLOR : BG_COLOR;
            else
                video_out <= video_in_d1;
        end
    end
 
endmodule