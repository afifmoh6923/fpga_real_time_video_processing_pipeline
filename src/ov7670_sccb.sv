///////////////////////////////////////////////////////////////////////////////
// ov7670_sccb.sv
// ECE 385 Final Project – Real-Time FPGA Video Processing Pipeline
//
// SCCB (Serial Camera Control Bus) BIT-BANG CONTROLLER
// ─────────────────────────────────────────────────────────────────────────────
// OmniVision SCCB is functionally identical to I2C write transactions.
// No ACK bit is checked (SCCB uses a "don't care" bit instead).
//
// Protocol for a 3-phase write (the only type we need):
//   1. START condition  : siod falls while sioc is HIGH
//   2. Phase 1 (8 bits): Device write address = 0x42
//   3. Don't-care bit  : release siod (float HIGH via pull-up)
//   4. Phase 2 (8 bits): Register address
//   5. Don't-care bit
//   6. Phase 3 (8 bits): Register value
//   7. Don't-care bit
//   8. STOP condition   : siod rises while sioc is HIGH
//
// Timing:
//   clk input  ≈ 24 MHz (cam_clk_int from Clocking Wizard)
//   Target SCL ≈ 100 kHz  →  half-period = 240 cycles at 24 MHz
//   HALF_PERIOD parameter controls this.
//
// Open-drain note:
//   siod is INOUT.  We never actively drive it HIGH; instead we release it
//   (assign 1'bz) and a pull-up resistor on the PMOD board raises the line.
//   Driving LOW is done by asserting the output enable and driving 0.
///////////////////////////////////////////////////////////////////////////////

module ov7670_sccb (
    input  logic clk,           // ~24 MHz cam_clk_int
    input  logic reset_n,       // active-LOW reset

    // Trigger interface (from ov7670_init)
    input  logic       start,       // pulse HIGH for one clk cycle to begin
    input  logic [7:0] reg_addr,    // OV7670 register address to write
    input  logic [7:0] reg_data,    // value to write into that register
    output logic       done,        // pulses HIGH for one cycle when finished

    // SCCB pins
    output logic sioc,          // SCCB clock  (push-pull, idle HIGH)
    inout  wire  siod           // SCCB data   (open-drain, idle HIGH via pull-up)
);

    // =========================================================================
    // PARAMETERS
    // =========================================================================
    // HALF_PERIOD: number of clk cycles per SCL half-period
    //   24 MHz / 100 kHz / 2 = 120  →  use 120 (adjust if SCL frequency wrong)
    localparam HALF_PERIOD = 120;

    // =========================================================================
    // INTERNAL SIGNALS
    // =========================================================================
    typedef enum logic [3:0] {
        IDLE,
        START_HI,       // sioc HIGH, pull siod LOW  → START condition
        START_LO,       // sioc goes LOW  (first SCL low phase)
        SHIFT_ADDR,     // clock out 8-bit device address (0x42)
        DC_ADDR,        // don't-care bit after address phase
        SHIFT_REG,      // clock out 8-bit register address
        DC_REG,         // don't-care bit
        SHIFT_DATA,     // clock out 8-bit data value
        DC_DATA,        // don't-care bit
        STOP_LO,        // sioc HIGH, siod still LOW before STOP
        STOP_HI,        // siod rises → STOP condition
        DONE_ST
    } state_t;

    state_t    state;
    logic [$clog2(HALF_PERIOD)-1:0] clk_cnt;   // half-period counter
    logic [3:0]  bit_cnt;     // bit counter within a phase (counts 0..8)
    logic [23:0] shift_reg;   // 24-bit shift register: {0x42, reg_addr, reg_data}

    // Open-drain drive signals
    logic sda_oe;   // 1 = drive LOW,  0 = release (high-Z → pulled HIGH)
    logic sda_out;  // value driven when sda_oe = 1  (always 0 for open-drain)
    assign siod = sda_oe ? 1'b0 : 1'bz;
    assign sda_out = 1'b0;  // we only ever actively drive LOW

    // =========================================================================
    // PSEUDO-CODE  (state machine)
    // =========================================================================
    // IDLE:
    //   sioc = 1, sda_oe = 0 (bus idle)
    //   done = 0
    //   When start == 1:
    //     Latch {0x42, reg_addr, reg_data} into shift_reg
    //     Reset clk_cnt and bit_cnt
    //     Next state → START_HI
    //
    // START_HI:
    //   sioc = 1 (stays HIGH)
    //   Pull siod LOW (sda_oe = 1) → this is the START condition
    //   Wait HALF_PERIOD cycles, then → START_LO
    //
    // START_LO:
    //   Pull sioc LOW
    //   Wait HALF_PERIOD cycles, then → SHIFT_ADDR
    //
    // SHIFT_ADDR / SHIFT_REG / SHIFT_DATA:  (same template, 8 bits each)
    //   For bit_cnt in 0..7:
    //     LOW  half: sioc = 0; drive siod with shift_reg[23] (MSB)
    //     HIGH half: sioc = 1; hold siod
    //     After HIGH half: shift shift_reg left by 1; bit_cnt++
    //   After 8 bits: pull sioc LOW, release siod → DC_xxx state
    //
    // DC_ADDR / DC_REG / DC_DATA:
    //   sioc = 0 → 1 → 0  (one full SCL cycle with siod released = don't-care)
    //   After: → next SHIFT_xxx state, or STOP_LO if DC_DATA
    //
    // STOP_LO:
    //   sioc HIGH, siod still LOW
    //   Wait HALF_PERIOD cycles, then → STOP_HI
    //
    // STOP_HI:
    //   Release siod (sda_oe = 0) while sioc stays HIGH → STOP condition
    //   Wait HALF_PERIOD cycles, then → DONE_ST
    //
    // DONE_ST:
    //   Assert done = 1 for one cycle → IDLE

    // =========================================================================
    // IMPLEMENTATION STUB  (fill in during lab)
    // =========================================================================
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state   <= IDLE;
            sioc    <= 1'b1;
            sda_oe  <= 1'b0;
            done    <= 1'b0;
            clk_cnt <= '0;
            bit_cnt <= '0;
            shift_reg <= '0;
        end else begin
            done <= 1'b0;   // default: done is a one-cycle pulse

            case (state)
                // ── IDLE ─────────────────────────────────────────────────────
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

                // ── START condition ───────────────────────────────────────────
                // TODO: sioc stays HIGH, pull siod LOW, wait HALF_PERIOD, go START_LO
                START_HI: begin
                    /* IMPLEMENT: sda_oe <= 1 (pull LOW = START)
                                  count HALF_PERIOD cycles
                                  then state <= START_LO               */
                end

                START_LO: begin
                    /* IMPLEMENT: sioc <= 0 (pull clock LOW)
                                  count HALF_PERIOD cycles
                                  then state <= SHIFT_ADDR             */
                end

                // ── Shift out device address 0x42 ────────────────────────────
                // TODO: 8-bit shift-out with SCL toggling; after 8 bits → DC_ADDR
                SHIFT_ADDR: begin
                    /* IMPLEMENT:
                       Each bit takes 2 × HALF_PERIOD cycles:
                         First half  (clk_cnt < HALF_PERIOD): sioc=0, drive MSB
                         Second half (clk_cnt < 2*HALF_PERIOD): sioc=1, hold
                       After 2*HALF_PERIOD:
                         shift_reg <<= 1;  bit_cnt++;  clk_cnt=0
                       After 8 bits:
                         state <= DC_ADDR                              */
                end

                DC_ADDR: begin
                    /* IMPLEMENT: one full SCL cycle with sda_oe=0 (release)
                                  then state <= SHIFT_REG              */
                end

                // ── Shift out register address ────────────────────────────────
                SHIFT_REG: begin
                    /* IMPLEMENT: identical to SHIFT_ADDR but counts
                                  8 more bits from shift_reg
                                  then state <= DC_REG                 */
                end

                DC_REG: begin
                    /* IMPLEMENT: one full SCL cycle, release siod
                                  then state <= SHIFT_DATA             */
                end

                // ── Shift out register value ──────────────────────────────────
                SHIFT_DATA: begin
                    /* IMPLEMENT: 8-bit shift-out
                                  then state <= DC_DATA                */
                end

                DC_DATA: begin
                    /* IMPLEMENT: one full SCL cycle, release siod
                                  then state <= STOP_LO                */
                end

                // ── STOP condition ────────────────────────────────────────────
                STOP_LO: begin
                    /* IMPLEMENT: sioc=1, sda_oe=1 (siod still LOW)
                                  wait HALF_PERIOD, then state <= STOP_HI */
                end

                STOP_HI: begin
                    /* IMPLEMENT: sda_oe=0 (release siod → line goes HIGH via pull-up)
                                  sioc stays HIGH
                                  wait HALF_PERIOD, then state <= DONE_ST */
                end

                // ── Done ─────────────────────────────────────────────────────
                DONE_ST: begin
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
