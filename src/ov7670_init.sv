
module ov7670_init (
    input  logic clk,           // ~24 MHz cam_clk_int
    input  logic reset_n,       // active-LOW reset
    // SCCB pins (routed through to ov7670_sccb)
    output logic sioc,
    inout  wire  siod,
    output logic config_done
    );    // stays HIGH after all registers written
   
    localparam PWRUP_DELAY = 12_000_000;   // ~50 ms at 24 MHz
    localparam RESET_DELAY = 1_200_000;   // ~50 ms  at 24 MHz
    localparam REG_DELAY   =    72_000;   // ~1 ms  at 24 MHz
    
    localparam ROM_DEPTH = 97;
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
        message[11] = 16'h4F40;  // MTX1
        message[12] = 16'h5030;  // MTX2
        message[13] = 16'h510C;  // MTX3
        message[14] = 16'h5217;  // MTX4
        message[15] = 16'h5329;  // MTX5
        message[16] = 16'h5440;  // MTX6
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
        message[32] = 16'hB382;  // THL_ST
 
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
        message[54] = 16'h1300;  // COM8:     Disable AGC, AEC, AWB
        message[55] = 16'h0040;  // GAIN:    Initial mid-level gain
        message[56] = 16'h1000;  // AECH:    AEC high bits = 0
        message[57] = 16'h0D40;  // COM4:    Magic reserved bit
        message[58] = 16'h1418;  // COM9:    2x max AGC gain ceiling
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
        message[72] = 16'h0180;  // BLUE:    Neutral AWB start point
        message[73] = 16'h0240;  // RED:     Neutral AWB start point
        message[74] = 16'h4108;  // COM16:   AWB gain enable only
        message[75] = 16'h4CC0;  // DNSTH:   De-noise on
 
        // AWB controllers
        message[76] = 16'h6C0A;  // AWBCTR3
        message[77] = 16'h6D55;  // AWBCTR2
        message[78] = 16'h6E11;  // AWBCTR1
        message[79] = 16'h6F9C;  // AWBCTR0
 
        // AEC stable region (tightened for indoor lighting)
        message[80] = 16'h2450;  // AEW:     Upper bound
        message[81] = 16'h2540;  // AEB:     Lower bound
        message[82] = 16'h26A1;  // VPT:     Fast mode region
 
        // AWB coefficients
        message[83] = 16'h43F0;  // AWBC1
        message[84] = 16'h4414;  // AWBC2
        message[85] = 16'h4525;  // AWBC3
        message[86] = 16'h4620;  // AWBC4
        message[87] = 16'h4757;  // AWBC5
        message[88] = 16'h5510; // BRIGHT: Apply negative brightness offset (-16) to crush shadow noise
        message[89] = 16'h5640; // CONTRAS: Boost contrast (1.25x) to keep highlights bright
        message[90] = 16'h0C00; // COM3:    Force scaling OFF
        message[91] = 16'h1204; // COM7:    Force VGA and RGB output mode
        message[92] = 16'h40D0; // COM15:   Force RGB565 format
        message[93] = 16'h8C00; // RGB444:  Ensure RGB444 is completely disabled
        message[94] = 16'h6B4A; //DBLV
        message[95] = 16'h7410; //Digit
        message[96] = 16'hFFFF; // END SENTINEL
    end
  
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