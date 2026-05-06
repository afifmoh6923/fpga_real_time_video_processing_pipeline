///////////////////////////////////////////////////////////////////////////////
// ov7670_init.sv
// ECE 385 Final Project - Real-Time FPGA Video Processing Pipeline
// OV7670 CAMERA CONFIGURATION SEQUENCER
// ?????????????????????????????????????????????????????????????????????????????
// On power-up (after reset_n de-asserts) this module:
//   1. Waits ~50 ms for the camera to stabilise
//   2. Issues a software reset (register 0x12 = 0x80)
//   3. Waits ~2 ms for the reset to take effect
//   4. Walks through the ROM table below, sending each {reg, val} pair
//      via ov7670_sccb, pausing ~1 ms between writes
//   5. Asserts config_done and stays there forever
// Camera configured for:
//   Resolution : QVGA 320
//   Format     : RGB565
//   Frame rate : ~30 fps  (24 MHz XCLK, no pre-scaler)
//   PCLK       : free-running (toggles during blanking)
// Register table built from:
//   
// Mike Field's Hamsterworks OV7670 Verilog project
//   
// westonb/OV7670-Verilog (GitHub)
//   
// Linux kernel ov7670.c driver register tables
// Timing constants (all in cam_clk cycles, cam_clk ? 24 MHz):
//   PWRUP_DELAY  = 1_200_000   (~50  ms)
//   RESET_DELAY  =    48_000   (~ 2  ms)
//   REG_DELAY    =    24_000   (~ 1  ms between consecutive writes)
///////////////////////////////////////////////////////////////////////////////
module ov7670_init (
    input  logic clk,           // ~24 MHz cam_clk_int
    input  logic reset_n,       // active-LOW reset
    // SCCB pins (routed through to ov7670_sccb)
    output logic sioc,
    inout  wire  siod,
    output logic config_done
    );    // stays HIGH after all registers written
    // =========================================================================
    // TIMING PARAMETERS
    // =========================================================================
    localparam PWRUP_DELAY = 12_000_000;   // ~50 ms at 24 MHz
    localparam RESET_DELAY =    48_000;   // ~2 ms  at 24 MHz
    localparam REG_DELAY   =    72_000;   // ~1 ms  at 24 MHz
    // =========================================================================
    // REGISTER TABLE  (ROM)
    // =========================================================================
    // Stored as an array of {reg_addr[7:0], reg_data[7:0]} = 16-bit words.
    // Sentinel value 16'hFFFF marks end of table.
    //
    // PSEUDO-CODE table (fill exact values from OV7670 datasheet / reference):
    //
    //   INDEX   REG     VALUE    DESCRIPTION
    //   [0]     0x12    0x80     Software reset  ? sent alone with extra delay
    //   [1]     0x12    0x04     COM7:  RGB mode, QVGA output
    //   [2]     0x11    0x00     CLKRC: no pre-scaler (full 24 MHz)
    //   [3]     0x0C    0x00     COM3:  enable scaling
    //   [4]     0x3E    0x00     COM14: normal PCLK
    //   [5]     0x70    0x3A     SCALING_XSC
    //   [6]     0x71    0x35     SCALING_YSC
    //   [7]     0x72    0x11     SCALING_DCWCTR  (QVGA = /2 in both dimensions)
    //   [8]     0x73    0xF0     SCALING_PCLK_DIV
    //   [9]     0xA2    0x02     SCALING_PCLK_DELAY
    //   [10]    0x15    0x00     COM10: PCLK free-running
    //   [11]    0x40    0xD0     COM15: RGB565 full output range [00..FF]
    //   [12]    0x41    0x08     COM16: de-noise on
    //   [13]    0x42    0x02     COM17: edge enhance on
    //   [14]    0x1E    0x00     MVFP:  no mirror / flip
    //   --- Color-matrix coefficients (critical for correct RGB565 colors) ---
    //   [15]    0x4F    0x80     MTX1
    //   [16]    0x50    0x80     MTX2
    //   [17]    0x51    0x00     MTX3
    //   [18]    0x52    0x22     MTX4
    //   [19]    0x53    0x5E     MTX5
    //   [20]    0x54    0x80     MTX6
    //   [21]    0x58    0x9E     MTXS (sign + auto-contrast)
    //   --- Gamma curve (improves perceived image quality) ---
    //   [22]    0x7A    0x20     SLOP
    //   [23]    0x7B    0x10     GAM1
    //   [24]    0x7C    0x1E     GAM2
    //   [25]    0x7D    0x35     GAM3
    //   [26]    0x7E    0x5A     GAM4
    //   [27]    0x7F    0x69     GAM5
    //   [28]    0x80    0x76     GAM6
    //   [29]    0x81    0x80     GAM7
    //   [30]    0x82    0x88     GAM8
    //   [31]    0x83    0x8F     GAM9
    //   [32]    0x84    0x96     GAM10
    //   [33]    0x85    0xA3     GAM11
    //   [34]    0x86    0xAF     GAM12
    //   [35]    0x87    0xC4     GAM13
    //   [36]    0x88    0xD7     GAM14
    //   [37]    0x89    0xE8     GAM15
    //   --- AWB (auto white balance) ---
    //   [38]    0x13    0xE0     COM8: AGC/AEC off initially, AWB on
    //   [39]    0x00    0x00     GAIN
    //   [40]    0x10    0x00     AECH
    //   [41]    0x0D    0x40     COM4
    //   [42]    0x14    0x18     COM9: max gain 4
    //   [43]    0xA5    0x05     BD50MAX
    //   [44]    0xAB    0x07     BD60MAX
    //   [45]    0x24    0x95     AEW  (AWB stable region upper bound)
    //   [46]    0x25    0x33     AEB  (AWB stable region lower bound)
    //   [47]    0x26    0xE3     VPT
    //   [48]    0x9F    0x78     HAECC1
    //   [49]    0xA0    0x68     HAECC2
    //   [50]    0xA1    0x0B     HAECC3 (reserved, keep at 0x0B)
    //   [51]    0xA6    0xD8     HAECC3
    //   [52]    0xA7    0xD8     HAECC4
    //   [53]    0xA8    0xF0     HAECC5
    //   [54]    0xA9    0x90     HAECC6
    //   [55]    0xAA    0x94     HAECC7
    //   [56]    0x13    0xE5     COM8: enable AGC, AEC, AWB fully
    //   [57]    0x69    0x00     GFIX (gain fix off)
    //   [58]    0x74    0x00     REG74 (digital gain off)
    //   [59]    0xB0    0x84     RSVD (set as per reference)
    //   [60]    0xB1    0x0C     ABLC1
    //   [61]    0xB2    0x0E     RSVD
    //   [62]    0xB3    0x80     THL_ST
    //   [63]    0x59    0x88     AWBC7
    //   [64]    0x5A    0x88     AWBC8
    //   [65]    0x5B    0x44     AWBC9
    //   [66]    0x5C    0x67     AWBC10
    //   [67]    0x5D    0x49     AWBC11
    //   [68]    0x5E    0x0E     AWBC12
    //   [69]    0x6C    0x0A     AWBCTR3
    //   [70]    0x6D    0x55     AWBCTR2
    //   [71]    0x6E    0x11     AWBCTR1
    //   [72]    0x6F    0x9F     AWBCTR0
    //   [73]    0x55    0x00     BRIGHT (brightness = 0, neutral)
    //   [74]    0x56    0x40     CONTRAS (contrast = 0x40, neutral)
    //   [75]    0xFF    0xFF     ? END SENTINEL
    //
    // NOTE: Index [0] (soft-reset 0x12=0x80) is sent first with RESET_DELAY
    //       before the remaining registers.  All others use REG_DELAY.
    localparam ROM_DEPTH = 84;
    logic [15:0] message [0:ROM_DEPTH-1];
    // Initialise ROM  (synthesises as LUT/BRAM-based ROM in Vivado)
    initial begin
        // Software reset - handled separately in state machine, still placed here
        message[0]=16'h12_80;  //reset all register to default values
        message[1]=16'h12_04;  //set output format to RGB
        message[2]=16'h15_20;  //pclk will not toggle during horizontal blank
        message[3]=16'h40_d0;	//RGB565
        
        // These are values scalped from https://github.com/jonlwowski012/OV7670_NEXYS4_Verilog/blob/master/ov7670_registers_verilog.v
        message[4]= 16'h1204; // COM7,     set RGB color output
        message[5]= 16'h1180; // CLKRC     internal PLL matches input clock
        message[6]= 16'h0C00; // COM3,     default settings
        message[7]= 16'h3E00; // COM14,    no scaling, normal pclock
        message[8]= 16'h0400; // COM1,     disable CCIR656
        message[9]= 16'h40d0; //COM15,     RGB565, full output range
        message[10]= 16'h3a04; //TSLB       set correct output data sequence (magic)
        message[11]= 16'h1418; //COM9       MAX AGC value x4 0001_1000
        message[12]= 16'h4F80; //MTX1  - correct OV7670 RGB color matrix
        message[13]= 16'h5080; //MTX2
        message[14]= 16'h5100; //MTX3
        message[15]= 16'h5222; //MTX4
        message[16]= 16'h535E; //MTX5
        message[17]= 16'h5480; //MTX6
        message[18]= 16'h589E; //MTXS - sign bits: MTX5 and MTX4 are negative
        message[19]= 16'h3DC0; //COM13      sets gamma enable, does not preserve reserved bits, may be wrong?
        message[20]= 16'h1714; //HSTART     start high 8 bits
        message[21]= 16'h1802; //HSTOP      stop high 8 bits //these kill the odd colored line
        message[22]= 16'h3280; //HREF       edge offset
        message[23]= 16'h1903; //VSTART     start high 8 bits
        message[24]= 16'h1A7B; //VSTOP      stop high 8 bits
        message[25]= 16'h030A; //VREF       vsync edge offset
        message[26]= 16'h0F41; //COM6       reset timings
        message[27]= 16'h1E00; //MVFP       disable mirror / flip //might have magic value of 03
        message[28]= 16'h330B; //CHLF       //magic value from the internet
        message[29]= 16'h3C78; //COM12      no HREF when VSYNC low
        message[30]= 16'h6900; //GFIX       fix gain control
        message[31]= 16'h7400; //REG74      Digital gain control
        message[32]= 16'hB084; //RSVD       magic value from the internet *required* for good color
        message[33]= 16'hB10c; //ABLC1
        message[34]= 16'hB20e; //RSVD       more magic internet values
        message[35]= 16'hB380; //THL_ST
        //begin mystery scaling numbers
        message[36]= 16'h703a;
        message[37]= 16'h7135;
        message[38]= 16'h7211;
        message[39]= 16'h73f0;
        message[40]= 16'ha202;
        //gamma curve values
        message[41]= 16'h7a20;
        message[42]= 16'h7b10;
        message[43]= 16'h7c1e;
        message[44]= 16'h7d35;
        message[45]= 16'h7e5a;
        message[46]= 16'h7f69;
        message[47]= 16'h8076;
        message[48]= 16'h8180;
        message[49]= 16'h8288;
        message[50]= 16'h838f;
        message[51]= 16'h8496;
        message[52]= 16'h85a3;
        message[53]= 16'h86af;
        message[54]= 16'h87c4;
        message[55]= 16'h88d7;
        message[56]= 16'h89e8;
        //AGC and AEC
        message[57]= 16'h13e0; //COM8: temporarily disable AGC/AEC/AWB to write gain regs cleanly
        message[58]= 16'h0040; //GAIN reg: start at a reasonable mid-level (not 0 = pitch black)
        message[59]= 16'h1000; //set ARCJ reg to 0
        message[60]= 16'h0d40; //magic reserved bit for COM4
        message[61]= 16'h1408; //COM9: 2x max gain ceiling (limits noise in dark scenes)
        message[62]= 16'ha505; // BD50MAX
        message[63]= 16'hab07; //DB60MAX
        message[64]= 16'h2495; //AGC upper limit
        message[65]= 16'h2533; //AGC lower limit
        message[66]= 16'h26e3; //AGC/AEC fast mode op region
        message[67]= 16'h9f78; //HAECC1
        message[68]= 16'ha068; //HAECC2
        message[69]= 16'ha103; //magic
        message[70]= 16'ha6d8; //HAECC3
        message[71]= 16'ha7d8; //HAECC4
        message[72]= 16'ha8f0; //HAECC5
        message[73]= 16'ha990; //HAECC6
        message[74]= 16'haa94; //HAECC7
        message[75]= 16'h13e7; //COM8: AGC+AEC+AWB all ON - AWB adapts to lighting automatically
        message[76]= 16'h1E23; //Mirror Image
        message[77]= 16'h6900; //GFIX = 0x00: no fixed gain bias
        message[78]= 16'h1470; //COM9: max AGC gain = 128x ceiling
        message[79]= 16'h0180; //BLUE gain = 0x80 neutral (AWB adjusts from here)
        message[80]= 16'h0280; //RED  gain = 0x80 neutral (AWB adjusts from here)
        message[81]= 16'h4118; //COM16: enable de-noise auto-adjust (bit4) + AWB gain enable (bit3)
        message[82]= 16'h4C10; //DNSTH: de-noise threshold = 0x10 (moderate, reduces green/blue speckle)
        message[83]= 16'hFFFF; //END SENTINEL
    end
    // =========================================================================
    // STATE MACHINE
    // =========================================================================
    typedef enum logic [2:0] {
        PWRUP,      // wait for camera power-up stabilisation
        SW_RESET,   // send register 0x12 = 0x80 (software reset)
        RST_WAIT,   // wait after software reset
        SW_RESET2,  
        RST_WAIT2,
        SEND_REG,   // send next register from ROM
        REG_WAIT,   // inter-register delay
        CONFIG_DONE // done - stay here
    } init_state_t;
    init_state_t  state;
    logic [20:0]  delay_cnt;        // delay counter (21 bits covers 1.2M cycles)
    logic [6:0]   rom_idx;          // current ROM index (0..75)
    logic         sccb_start;
    logic [7:0]   sccb_reg_addr;
    logic [7:0]   sccb_reg_data;
    logic         sccb_done;
    logic sccb_started;
    // =========================================================================
    // PSEUDO-CODE:
    //
    // PWRUP:
    //   Count PWRUP_DELAY cycles.  When done ? SW_RESET.
    //
    // SW_RESET:
    //   Pulse sccb_start=1 with reg_addr=0x12, reg_data=0x80.
    //   Wait for sccb_done ? RST_WAIT.
    //
    // RST_WAIT:
    //   Count RESET_DELAY cycles.  When done ? SEND_REG with rom_idx=1
    //   (skip index 0 which was the reset command we already sent).
    //
    // SEND_REG:
    //   If rom[rom_idx] == 16'hFFFF ? CONFIG_DONE.
    //   Else extract reg_addr = rom[rom_idx][15:8]
    //              reg_data  = rom[rom_idx][7:0]
    //   Pulse sccb_start=1.  Wait for sccb_done ? REG_WAIT.
    //
    // REG_WAIT:
    //   Count REG_DELAY cycles.
    //   rom_idx++.  ? SEND_REG.
    //
    // CONFIG_DONE:
    //   config_done = 1.  Stay here forever.
    // =========================================================================
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state       <= PWRUP;
            delay_cnt   <= '0;
            rom_idx     <= '0;
            sccb_start  <= 1'b0;
            config_done <= 1'b0;
            sccb_started <= 1'b0;
        end else begin
            sccb_start <= 1'b0;  // default: no transaction
            case (state)
                PWRUP: begin
                    // IMPLEMENT: count PWRUP_DELAY then transition to SW_RESET
                    if (delay_cnt == PWRUP_DELAY - 1) begin
                        delay_cnt <= '0;
                        state     <= SW_RESET;
                    end else begin
                        delay_cnt <= delay_cnt + 1;
                    end
                end
                SW_RESET: begin
                    // IMPLEMENT: send {0x12, 0x80}, wait for sccb_done
                    if (!sccb_started) begin
                        sccb_reg_addr <= 8'h12;
                        sccb_reg_data <= 8'h80;
                        sccb_start    <= 1'b1;
                        sccb_started  <= 1'b1;
                    end
                    if (sccb_done) begin
                        sccb_started <= 1'b0;
                        delay_cnt    <= '0;
                        state        <= RST_WAIT;
                    end
                end
                RST_WAIT: begin
                    if (delay_cnt == RESET_DELAY - 1) begin
                        delay_cnt <= '0;
                        state     <= SW_RESET2;   // ? changed
                    end else
                        delay_cnt <= delay_cnt + 1;
                end
                SW_RESET2: begin
                    if (!sccb_started) begin
                        sccb_reg_addr <= 8'h12;
                        sccb_reg_data <= 8'h80;
                        sccb_start    <= 1'b1;
                        sccb_started  <= 1'b1;
                    end
                    if (sccb_done) begin
                        sccb_started <= 1'b0;
                        delay_cnt    <= '0;
                        state        <= RST_WAIT2;
                    end
                end
                RST_WAIT2: begin
                    if (delay_cnt == RESET_DELAY - 1) begin
                        delay_cnt <= '0;
                        rom_idx   <= 7'd1;
                        state     <= SEND_REG;
                    end else
                        delay_cnt <= delay_cnt + 1;
                end
                SEND_REG: begin
                    // IMPLEMENT: check sentinel, extract reg/data, trigger SCCB
                    if (message[rom_idx] == 16'hFFFF) begin
                        state <= CONFIG_DONE;
                    end else if (!sccb_started) begin
                        sccb_reg_addr <= message[rom_idx][15:8];
                        sccb_reg_data <= message[rom_idx][7:0];
                        sccb_start    <= 1'b1;
                        sccb_started  <= 1'b1;
                    end
                    if (sccb_done) begin
                        sccb_started <= 1'b0;
                        delay_cnt    <= '0;
                        state        <= REG_WAIT;
                    end
                end
                REG_WAIT: begin
                    // IMPLEMENT: count REG_DELAY, then advance rom_idx
                    if (delay_cnt == REG_DELAY - 1) begin
                        delay_cnt <= '0;
                        rom_idx   <= rom_idx + 1;
                        state     <= SEND_REG;
                    end else begin
                        delay_cnt <= delay_cnt + 1;
                    end
                end
                CONFIG_DONE: begin
                    config_done <= 1'b1;
                end
                default: state <= PWRUP;
            endcase
        end
    end
    // =========================================================================
    // SCCB CONTROLLER INSTANTIATION
    // =========================================================================
    ov7670_sccb sccb_ctrl (
        .clk      (clk),
        .reset_n  (reset_n),
        .start    (sccb_start),
        .reg_addr (sccb_reg_addr),
        .reg_data (sccb_reg_data),
        .done     (sccb_done),
        .sioc     (sioc),
        .siod     (siod)
    );
endmodule