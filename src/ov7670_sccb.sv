///////////////////////////////////////////////////////////////////////////////
// ov7670_sccb.sv
// ECE 385 Final Project - Real-Time FPGA Video Processing Pipeline
//
// SCCB (Serial Camera Control Bus) BIT-BANG CONTROLLER
// ?????????????????????????????????????????????????????????????????????????????
// OmniVision SCCB is functionally identical to I2C write transactions.
// No ACK bit is checked (SCCB uses a "don't care" bit instead).
//
// Protocol for a 3-phase write:
//   1. START condition  : siod falls while sioc is HIGH
//   2. Phase 1 (8 bits): Device write address = 0x42
//   3. Don't-care bit  : release siod (float HIGH via pull-up)
//   4. Phase 2 (8 bits): Register address
//   5. Don't-care bit
//   6. Phase 3 (8 bits): Register value
//   7. Don't-care bit
//   8. STOP condition   : siod rises while sioc is HIGH
///////////////////////////////////////////////////////////////////////////////

module ov7670_sccb (
    input  logic clk,           // ~24 MHz cam_clk_int
    input  logic reset_n,       // active-LOW reset

    input  logic       start,
    input  logic [7:0] reg_addr,
    input  logic [7:0] reg_data,
    output logic       done,

    output logic sioc,
    inout  wire  siod
);

    localparam HALF_PERIOD = 120;   // 24 MHz / 100 kHz / 2

    typedef enum logic [3:0] {
        IDLE,
        START_HI,
        START_LO,
        SHIFT_ADDR,
        DC_ADDR,
        SHIFT_REG,
        DC_REG,
        SHIFT_DATA,
        DC_DATA,
        STOP_LO,
        STOP_HI,
        DONE_ST
    } state_t;

    state_t    state;
    logic [15:0]  clk_cnt;
    logic [3:0]  bit_cnt;
    logic [23:0] shift_reg;
    logic        sda_oe;

    // Open-drain: drive 0 when sda_oe=1, else release (Z ? pulled HIGH)
    assign siod = sda_oe ? 1'b0 : 1'bz;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state     <= IDLE;
            sioc      <= 1'b1;
            sda_oe    <= 1'b0;
            done      <= 1'b0;
            clk_cnt   <= '0;
            bit_cnt   <= '0;
            shift_reg <= '0;
        end else begin
            done <= 1'b0;

            case (state)

                // ?? Idle: wait for start pulse ????????????????????????????????
                IDLE: begin
                    sioc   <= 1'b1;
                    sda_oe <= 1'b0;
                    if (start) begin
                        shift_reg <= {8'h42, reg_addr, reg_data};
                        clk_cnt   <= '0;
                        bit_cnt   <= 4'd0;
                        state     <= START_HI;
                    end
                end

                // ?? START: pull siod LOW while sioc is HIGH ???????????????????
                START_HI: begin
                    sioc   <= 1'b1;
                    sda_oe <= 1'b1;         // pull siod LOW ? START condition
                    if (clk_cnt == HALF_PERIOD - 1) begin
                        clk_cnt <= '0;
                        state   <= START_LO;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                START_LO: begin
                    sioc <= 1'b0;           // bring clock low to begin data
                    if (clk_cnt == HALF_PERIOD - 1) begin
                        clk_cnt <= '0;
                        bit_cnt <= 4'd0;
                        state   <= SHIFT_ADDR;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                // ?? Shift out 8 bits: device address (0x42) ??????????????????
                SHIFT_ADDR: begin
                    if (clk_cnt < HALF_PERIOD) begin
                        // Low half: sioc=0, present MSB on siod
                        sioc   <= 1'b0;
                        sda_oe <= shift_reg[23] ? 1'b0 : 1'b1;
                        // sda_oe=1 drives 0; sda_oe=0 releases to 1 via pull-up
                        // Invert: to send a '1' we release; to send '0' we drive low
                        sda_oe <= ~shift_reg[23];
                        clk_cnt <= clk_cnt + 1;
                    end else if (clk_cnt < 2 * HALF_PERIOD) begin
                        // High half: sioc=1, hold siod
                        sioc    <= 1'b1;
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        // Bit done
                        shift_reg <= {shift_reg[22:0], 1'b0};
                        clk_cnt   <= '0;
                        if (bit_cnt == 4'd7) begin
                            sioc    <= 1'b0;
                            sda_oe  <= 1'b0;    // release for don't-care
                            bit_cnt <= 4'd0;
                            state   <= DC_ADDR;
                        end else begin
                            bit_cnt <= bit_cnt + 1;
                        end
                    end
                end

                // ?? Don't-care bit after address phase ????????????????????????
                DC_ADDR: begin
                    sda_oe <= 1'b0;     // release siod
                    if (clk_cnt < HALF_PERIOD) begin
                        sioc    <= 1'b0;
                        clk_cnt <= clk_cnt + 1;
                    end else if (clk_cnt < 2 * HALF_PERIOD) begin
                        sioc    <= 1'b1;
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        sioc    <= 1'b0;
                        clk_cnt <= '0;
                        bit_cnt <= 4'd0;
                        state   <= SHIFT_REG;
                    end
                end

                // ?? Shift out 8 bits: register address ???????????????????????
                SHIFT_REG: begin
                    if (clk_cnt < HALF_PERIOD) begin
                        sioc    <= 1'b0;
                        sda_oe  <= ~shift_reg[23];
                        clk_cnt <= clk_cnt + 1;
                    end else if (clk_cnt < 2 * HALF_PERIOD) begin
                        sioc    <= 1'b1;
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        shift_reg <= {shift_reg[22:0], 1'b0};
                        clk_cnt   <= '0;
                        if (bit_cnt == 4'd7) begin
                            sioc    <= 1'b0;
                            sda_oe  <= 1'b0;
                            bit_cnt <= 4'd0;
                            state   <= DC_REG;
                        end else begin
                            bit_cnt <= bit_cnt + 1;
                        end
                    end
                end

                // ?? Don't-care bit after register address ?????????????????????
                DC_REG: begin
                    sda_oe <= 1'b0;
                    if (clk_cnt < HALF_PERIOD) begin
                        sioc    <= 1'b0;
                        clk_cnt <= clk_cnt + 1;
                    end else if (clk_cnt < 2 * HALF_PERIOD) begin
                        sioc    <= 1'b1;
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        sioc    <= 1'b0;
                        clk_cnt <= '0;
                        bit_cnt <= 4'd0;
                        state   <= SHIFT_DATA;
                    end
                end

                // ?? Shift out 8 bits: register data ??????????????????????????
                SHIFT_DATA: begin
                    if (clk_cnt < HALF_PERIOD) begin
                        sioc    <= 1'b0;
                        sda_oe  <= ~shift_reg[23];
                        clk_cnt <= clk_cnt + 1;
                    end else if (clk_cnt < 2 * HALF_PERIOD) begin
                        sioc    <= 1'b1;
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        shift_reg <= {shift_reg[22:0], 1'b0};
                        clk_cnt   <= '0;
                        if (bit_cnt == 4'd7) begin
                            sioc    <= 1'b0;
                            sda_oe  <= 1'b0;
                            bit_cnt <= 4'd0;
                            state   <= DC_DATA;
                        end else begin
                            bit_cnt <= bit_cnt + 1;
                        end
                    end
                end

                // ?? Don't-care bit after data phase ???????????????????????????
                DC_DATA: begin
                    sda_oe <= 1'b0;
                    if (clk_cnt < HALF_PERIOD) begin
                        sioc    <= 1'b0;
                        clk_cnt <= clk_cnt + 1;
                    end else if (clk_cnt < 2 * HALF_PERIOD) begin
                        sioc    <= 1'b1;
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        sioc    <= 1'b0;
                        clk_cnt <= '0;
                        state   <= STOP_LO;
                    end
                end

                // ?? STOP: sioc HIGH, then release siod ????????????????????????
                STOP_LO: begin
                    sda_oe <= 1'b1;     // hold siod LOW before STOP
                    sioc   <= 1'b1;     // bring clock HIGH
                    if (clk_cnt == HALF_PERIOD - 1) begin
                        clk_cnt <= '0;
                        state   <= STOP_HI;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                STOP_HI: begin
                    sioc   <= 1'b1;
                    sda_oe <= 1'b0;     // release siod ? rises to HIGH = STOP
                    if (clk_cnt == HALF_PERIOD - 1) begin
                        clk_cnt <= '0;
                        state   <= DONE_ST;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                // ?? Done: pulse done for one cycle ????????????????????????????
                DONE_ST: begin
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule