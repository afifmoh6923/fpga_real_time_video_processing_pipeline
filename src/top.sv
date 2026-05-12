
// Instantiation order:
//   clk_wiz_0          ? generates pixel_clk (25 MHz), tmds_clk (125 MHz),
//                          cam_clk (~24 MHz)
//   ov7670_init         ? sends SCCB register table to camera on startup
//   ov7670_capture      ? captures RGB565 pixels into frame-buffer write port
//   blk_mem_gen_0       ? dual-port BRAM frame buffer (320?240 ? 16b)
//   sync_flop ?16       ? synchronise SW into pixel_clk domain
//   vga_controller      ? 640?480 @ 60 Hz scan timing
//   filter_pipeline     ? all image-processing stages
//   text_overlay        ? renders active-filter name string
//   color_mapper        ? 24-bit ? 4-bit per channel for HDMI IP
//   hdmi_tx_0           ? Real Digital VGA?HDMI TMDS transmitter


module top (
    output logic [15:0] LED,
    input  logic        Clk,            // 100 MHz Urbana board oscillator
    input  logic        reset_btn,      // e.g. BTNC
    input  logic [15:0] SW,
    input  logic        cam_pclk,       // pixel clock OUT from camera
    output logic        cam_xclk,       // master clock  IN  to camera
    inout  logic        cam_siod,       // SCCB data  (bidirectional / open-drain)
    output logic        cam_sioc,       // SCCB clock
    input  logic        cam_vsync,      // vertical sync   from camera
    input  logic        cam_href,       // horizontal ref  from camera
    input  logic [7:0]  cam_data,       // 8-bit pixel bus from camera
    output logic        hdmi_tmds_clk_n,
    output logic        hdmi_tmds_clk_p,
    output logic [2:0]  hdmi_tmds_data_n,
    output logic [2:0]  hdmi_tmds_data_p
);
logic clk_locked;

    assign LED[1]  = cam_vsync;
    assign LED[2]  = cam_href;
    assign LED[3]  = fb_wr_en;
    assign LED[4] = init_ready;
    assign LED[5] = clk_locked;
    assign LED[6] = init_delay[23];
    assign LED[7] = cam_sioc;
    assign LED[15] = config_done;
    //assign LED[14:7] = cam_data;   // ADD THIS (Debugging Technique)


    // Clocks
    logic pixel_clk;      // 25 MHz  - VGA / filter / BRAM read
    logic tmds_clk;       // 125 MHz - HDMI TMDS
    logic cam_clk_int;    // ~24 MHz - OV7670 XCLK

    // Camera tie-offs
    //assign cam_reset_n = 1'b1;
    //assign cam_pwdn    = 1'b0;
    assign cam_xclk    = cam_clk_int;

    // Switch synchronisation (pixel_clk domain)
    logic [15:0] sw_sync;

    // Frame buffer wires  (write = cam_pclk domain, read = pixel_clk domain)
    logic [16:0] fb_wr_addr;
    logic [15:0] fb_wr_data;
    logic        fb_wr_en;
    logic [16:0] fb_rd_addr;   // registered 1 cycle early for BRAM latency
    logic [15:0] fb_rd_data;   // RGB565 pixel out of BRAM

    // VGA controller outputs
    logic [9:0]  drawX, drawY;
    logic        hs, vs;
    logic        active_nblank;   // HIGH = active video
    logic        sync_unused;

    // Filter pipeline outputs
    logic [23:0] filtered_rgb;
    logic        filtered_valid;

    // Text overlay outputs
    logic [23:0] overlaid_rgb;
    logic        overlaid_valid;

    // Color mapper outputs ? HDMI IP
    logic [3:0]  hdmi_r, hdmi_g, hdmi_b;
    logic        vde;

    // config_done from ov7670_init (unused in logic but useful for debug LED)
    logic        config_done;
    logic cam_pclk_buf;

    // Force the raw camera clock onto the Global Clock Network
    BUFG bufg_cam_pclk (
        .I(cam_pclk),       // Raw, noisy clock coming from the Pmod pin (H16)
        .O(cam_pclk_buf)    // Clean, zero-skew clock to use everywhere else
    );

    clk_wiz_0 clk_gen (
        .clk_in1  (Clk),
        .clk_out1 (pixel_clk),
        .clk_out2 (tmds_clk),
        .clk_out3 (cam_clk_int),
        .reset    (1'b0),
        .locked   (clk_locked)               // tie off or connect to downstream reset
    );

   
    genvar i;
    generate
        for (i = 0; i < 16; i++) begin : sw_sync_gen
            sync_flop sw_sf (
                .clk (pixel_clk),
                .d   (SW[i]),
                .q   (sw_sync[i])
            );
        end
    endgenerate

    logic [23:0] init_delay;
    logic        init_ready;
    always_ff @(posedge cam_clk_int) begin
        if (!clk_locked) begin
            init_delay <= 0;
            init_ready <= 0;
        end else if (!init_ready) begin
            if (init_delay == 24'd16_000_000)  // ~667ms after lock
                init_ready <= 1;
            else
                init_delay <= init_delay + 1;
        end
    end
    
    ov7670_init cam_init (
        .clk         (cam_clk_int),
        .reset_n     (init_ready & ~reset_btn),   // hold camera in reset until init logic is ready 
        .sioc        (cam_sioc),
        .siod        (cam_siod),
        .config_done (config_done)
    );

   
    ov7670_capture capture (
        .cam_pclk  (cam_pclk_buf),
        .cam_vsync (cam_vsync),
        .cam_href  (cam_href),
        .cam_data  (cam_data),
        .wr_addr   (fb_wr_addr),
        .wr_data   (fb_wr_data),
        .wr_en     (fb_wr_en)
    );

   
    logic [9:0] drawX_d, drawY_d;
    always_ff @(posedge pixel_clk) begin
        drawX_d <= drawX;
        drawY_d <= drawY;
    end

    // Use drawX_d/drawY_d (1 cycle early) so BRAM output aligns with drawX/drawY
    always_ff @(posedge pixel_clk) begin
        if (drawX_d >= 10'd160 && drawX_d < 10'd480 && drawY_d >= 10'd120 && drawY_d < 10'd360)
            fb_rd_addr <= (17'(drawY_d - 10'd120) << 8) + (17'(drawY_d - 10'd120) << 6) + 17'(drawX_d - 10'd160);
        else
            fb_rd_addr <= 17'd0;
    end

    blk_mem_gen_0 frame_buffer (
        // Write port - camera clock domain
        .clka  (cam_pclk_buf),
        .wea   (fb_wr_en),
        .addra (fb_wr_addr),
        .dina  (fb_wr_data),
        // Read port - pixel_clk domain (1-cycle registered output)
        .clkb  (pixel_clk),
        .addrb (fb_rd_addr),
        .doutb (fb_rd_data)
    );

    vga_controller vga (
        .pixel_clk    (pixel_clk),
        .reset        (reset_btn),
        .hs           (hs),
        .vs           (vs),
        .active_nblank(active_nblank),
        .sync         (sync_unused),
        .drawX        (drawX),
        .drawY        (drawY)
    );

    filter_pipeline fp (
        .pixel_clk     (pixel_clk),
        .reset         (reset_btn),
        .SW            (sw_sync),
        .drawX         (drawX_d),
        .drawY         (drawY_d),
        .active_nblank (active_nblank),
        .fb_data       (fb_rd_data),
        .filtered_rgb  (filtered_rgb),
        .pvalid_out    (filtered_valid)
    );

   text_overlay txt (
       .pixel_clk   (pixel_clk),
       .reset       (reset_btn),
       .drawX       (drawX),
       .drawY       (drawY),
       .vs          (vs),
       .SW          (sw_sync),
       .video_in    (filtered_rgb),
       .pixel_valid (filtered_valid),
       .video_out   (overlaid_rgb),
       .pvalid_out  (overlaid_valid)
   );

    color_mapper cm (
        .filtered_rgb (overlaid_rgb),
        .pixel_valid  (overlaid_valid),
        .red          (hdmi_r),
        .green        (hdmi_g),
        .blue         (hdmi_b),
        .vde          (vde)
    );

    hdmi_tx_0 hdmi_inst (
        .pix_clk        (pixel_clk),
        .pix_clkx5      (tmds_clk),
        .pix_clk_locked (clk_locked),        // assume locked after clk_wiz stabilises
        .rst            (reset_btn),
        .red            (hdmi_r),
        .green          (hdmi_g),
        .blue           (hdmi_b),
        .hsync          (hs),
        .vsync          (vs),
        .vde            (vde),
        .aux0_din       (4'h0),
        .aux1_din       (4'h0),
        .aux2_din       (4'h0),
        .ade            (1'b0),
        .TMDS_CLK_P     (hdmi_tmds_clk_p),
        .TMDS_CLK_N     (hdmi_tmds_clk_n),
        .TMDS_DATA_P    (hdmi_tmds_data_p),
        .TMDS_DATA_N    (hdmi_tmds_data_n)
    );

endmodule