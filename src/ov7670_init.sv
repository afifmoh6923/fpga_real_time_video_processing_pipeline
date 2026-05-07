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
    localparam RESET_DELAY = 1_200_000;   // ~50 ms  at 24 MHz
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
    localparam ROM_DEPTH = 95;
    logic [15:0] message [0:ROM_DEPTH-1];
    // Initialise ROM  (synthesises as LUT/BRAM-based ROM in Vivado)
    initial begin
        message[0]  = 16'h1280;  // COM7:    Software reset
        message[1]  = 16'h1204; // COM7:    Enable VGA and RGB mode (Bit 4 removed to disable QVGA!)
        message[2]  = 16'h40D0; // COM15:   RGB565 format, full output range
        message[3]  = 16'h8C00; // RGB444:  Disabled
        message[4]  = 16'h1510; // COM10:   PCLK free-running
        message[5]  = 16'h1100; // CLKRC:   Prescaler divide by 2 (keeps data eye wide)
        message[6]  = 16'h0C00; // COM3:    Disable scaling completely!
        message[7]  = 16'h3E00; // COM14:   Normal PCLK, no manual scaling
        message[8]  = 16'h0400;  // COM1:    Disable CCIR656
        message[9]  = 16'h3A04;  // TSLB:    Correct RGB byte output sequence
        message[10] = 16'h0901;  // COM2:    4x I/O drive strength
 
        // Color matrix
        message[11] = 16'h4F98;  // MTX1
        message[12] = 16'h5068;  // MTX2
        message[13] = 16'h5108;  // MTX3
        message[14] = 16'h5216;  // MTX4
        message[15] = 16'h5310;  // MTX5
        message[16] = 16'h5476;  // MTX6
        message[17] = 16'h589E;  // MTXS:    
 
        // Window / timing
        message[18] = 16'h3D80;  // COM13:   on
        message[19] = 16'h1716;  // HSTART
        message[20] = 16'h1804;  // HSTOP
        message[21] = 16'h3280;  // HREF:    Edge offset
        message[22] = 16'h1903;  // VSTART
        message[23] = 16'h1A7B;  // VSTOP
        message[24] = 16'h030A;  // VREF:    VSYNC edge offset
        message[25] = 16'h0F41;  // COM6:    Reset timings
        message[26] = 16'h330B;  // CHLF:    Magic value
        message[27] = 16'h3C78;  // COM12:   No HREF when VSYNC low
 
        // Misc analog
        message[28] = 16'h7400;  // REG74:   Digital gain off
        message[29] = 16'hB084;  // RSVD:    Required for good color
        message[30] = 16'hB10C;  // ABLC1
        message[31] = 16'hB20E;  // RSVD
        message[32] = 16'hB380;  // THL_ST
 
        // Scaling
        message[33] = 16'h703A;  // SCALING_XSC
        message[34] = 16'h7135;  // SCALING_YSC
        message[35] = 16'h7222;  // SCALING_DCWCTR
        message[36] = 16'h73F0;  // SCALING_PCLK_DIV
        message[37] = 16'hA205;  // SCALING_PCLK_DELAY
 
        // Gamma curve
        message[38] = 16'h7A20;  // SLOP
        message[39] = 16'h7B10;  // GAM1
        message[40] = 16'h7C1E;  // GAM2
        message[41] = 16'h7D35;  // GAM3
        message[42] = 16'h7E5A;  // GAM4
        message[43] = 16'h7F69;  // GAM5
        message[44] = 16'h8076;  // GAM6
        message[45] = 16'h8180;  // GAM7
        message[46] = 16'h8288;  // GAM8
        message[47] = 16'h838F;  // GAM9
        message[48] = 16'h8496;  // GAM10
        message[49] = 16'h85A3;  // GAM11
        message[50] = 16'h86AF;  // GAM12
        message[51] = 16'h87C4;  // GAM13
        message[52] = 16'h88D7;  // GAM14
        message[53] = 16'h89E8;  // GAM15
 
        // AGC/AEC: disable, write registers, re-enable
        message[54] = 16'h13E0;  // COM8:    Disable AGC, AEC, AWB
        message[55] = 16'h0040;  // GAIN:    Initial mid-level gain
        message[56] = 16'h1000;  // AECH:    AEC high bits = 0
        message[57] = 16'h0D40;  // COM4:    Magic reserved bit
        message[58] = 16'h1400;  // COM9:    2x max AGC gain ceiling
        message[59] = 16'hA505;  // BD50MAX
        message[60] = 16'hAB07;  // BD60MAX
        message[61] = 16'h9F78;  // HAECC1
        message[62] = 16'hA068;  // HAECC2
        message[63] = 16'hA103;  // HAECC3 (reserved, keep 0x03)
        message[64] = 16'hA6D8;  // HAECC4
        message[65] = 16'hA7D8;  // HAECC5
        message[66] = 16'hA8F0;  // HAECC6
        message[67] = 16'hA990;  // HAECC7
        message[68] = 16'hAA94;  // HAECC8
        message[69] = 16'h13E7;  // COM8:    Re-enable AGC + AEC + AWB
 
        // Post-enable tuning
        message[70] = 16'h1E23;  // MVFP:    Mirror image
        message[71] = 16'h690C;  // GFIX:    Fixed gain bias = 0x06
        message[72] = 16'h0160;  // BLUE:    Neutral AWB start point
        message[73] = 16'h02C0;  // RED:     Neutral AWB start point
        message[74] = 16'h4118;  // COM16:   AWB gain enable only
        message[75] = 16'h4C88;  // DNSTH:   De-noise on
 
        // AWB controllers
        message[76] = 16'h6C0A;  // AWBCTR3
        message[77] = 16'h6D55;  // AWBCTR2
        message[78] = 16'h6E11;  // AWBCTR1
        message[79] = 16'h6F9F;  // AWBCTR0
 
        // AEC stable region (tightened for indoor lighting)
        message[80] = 16'h2460;  // AEW:     Upper bound
        message[81] = 16'h2550;  // AEB:     Lower bound
        message[82] = 16'h26A5;  // VPT:     Fast mode region
 
        // AWB coefficients
        message[83] = 16'h43F0;  // AWBC1
        message[84] = 16'h4414;  // AWBC2
        message[85] = 16'h4525;  // AWBC3
        message[86] = 16'h4620;  // AWBC4
        message[87] = 16'h4757;  // AWBC5
        message[88] = 16'h5500; // BRIGHT: Apply negative brightness offset (-16) to crush shadow noise
        message[89] = 16'h5655; // CONTRAS: Boost contrast (1.25x) to keep highlights bright
        message[90] = 16'h0C00; // COM3:    Force scaling OFF
        message[91] = 16'h1204; // COM7:    Force VGA and RGB output mode
        message[92] = 16'h40D0; // COM15:   Force RGB565 format
        message[93] = 16'h8C00; // RGB444:  Ensure RGB444 is completely disabled
        message[94] = 16'hFFFF; // END SENTINEL
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