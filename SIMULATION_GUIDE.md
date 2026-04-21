# Simulation Testbench Guide
## ECE 385 Final Project — Real-Time FPGA Video Processing Pipeline

---

## File List

| Testbench file | Module(s) tested | Notes |
|---|---|---|
| `tb/tb_ov7670_sccb.sv` | `ov7670_sccb` | Needs `ov7670_sccb.sv` |
| `tb/tb_ov7670_capture.sv` | `ov7670_capture` | Needs `ov7670_capture.sv` |
| `tb/tb_line_buffer.sv` | `line_buffer` | Needs `line_buffer.sv` |
| `tb/tb_pointwise_filters.sv` | `grayscale`, `brightness_contrast`, `channel_isolate` | Three modules in one file; each has its own `module` block |
| `tb/tb_conv_filters.sv` | `box_blur`, `sharpen`, `edge_detect` | Depends on `line_buffer.sv` |
| `tb/tb_filter_pipeline_and_cm.sv` | `filter_pipeline`, `color_mapper` | Integration test; depends on all filter modules |
| `tb/tb_text_overlay.sv` | `text_overlay` | Includes a **behavioural font_rom stub**; replace stub with real `font_rom.sv` for full test |

---

## How to Run in Vivado (XSim)

### Method A — One Testbench at a Time (Recommended for Debugging)

1. **Open your Vivado project.**

2. **Add the testbench as a simulation source:**
   - Click **"Add Sources"** → Select **"Add or create simulation sources"**
   - Add the desired `tb_*.sv` file
   - Make sure to also have all relevant design source files in the project
   - Click **Finish**

3. **Set the testbench as the simulation top:**
   - In the **Sources** panel expand **"Simulation Sources → sim_1"**
   - Right-click the testbench module → **"Set as Top"**

4. **Set simulation run time:**
   - **Flow Navigator → Simulation → Simulation Settings**
   - Set `xsim.simulate.runtime` to `all` (not 1000ns) so the simulation
     runs until `$finish` is called

5. **Run Simulation:**
   - **Flow Navigator → Run Simulation → Run Behavioral Simulation**

6. **Read the results in the TCL Console:**
   - Passing tests print `PASS:` lines
   - Failing tests print `$error` messages in red
   - Final line is `ALL TESTS PASSED` or `FAILED: N error(s)`

7. **Waveform viewer:**
   - After simulation, open the **Waveform** window
   - The testbench calls `$dumpfile` / `$dumpvars` for VCD output
   - Add signals of interest from the **Objects** panel

---

### Method B — Tcl Script (Run All from Console)

Enter this in the **Vivado TCL Console** to batch-run all simulations:

```tcl
# Run from the project root directory
foreach tb {
    tb_ov7670_sccb
    tb_ov7670_capture
    tb_line_buffer
    tb_grayscale
    tb_brightness_contrast
    tb_channel_isolate
    tb_box_blur
    tb_sharpen
    tb_edge_detect
    tb_filter_pipeline
    tb_color_mapper
    tb_text_overlay
} {
    set_property top $tb [get_filesets sim_1]
    launch_simulation
    run all
    close_sim
}
```

---

### Method C — Standalone XSim (Outside Vivado GUI)

If you want to run simulations from command line (on EWS Linux machines):

```bash
# Compile all sources together
xvlog --sv \
    ov7670_sccb.sv \
    ov7670_capture.sv \
    line_buffer.sv \
    pointwise_filters.sv \
    box_blur.sv \
    conv_filters.sv \
    filter_pipeline.sv \
    text_overlay.sv \
    color_mapper.sv \
    tb/tb_ov7670_sccb.sv

# Elaborate
xelab -debug typical tb_ov7670_sccb -s tb_sccb_sim

# Simulate
xsim tb_sccb_sim -runall
```

Repeat for each testbench module.

---

## What Each Testbench Verifies

### `tb_ov7670_sccb` — SCCB Protocol

**What it does:** Drives the `start` input and monitors `sioc`/`siod` waveforms.

**Key checks:**
- **START condition**: `siod` falls while `sioc` is HIGH before any bits are sent
- **STOP condition**: `siod` rises while `sioc` is HIGH after all bits are sent
- **`done` pulse**: asserts exactly once per transaction, then goes low
- **Bus idle**: `sioc=1`, `siod` floating (pulled HIGH) between transactions
- **Reset recovery**: de-asserting `reset_n` mid-transaction returns bus to idle

**Why the siod pull-up model matters:**  
The DUT drives `siod = 1'bz` (high-impedance) when releasing the line.
The TB models the physical pull-up with:
```sv
assign siod_pulled = (siod === 1'bz) ? 1'b1 : siod;
```
Without this, `siod === 1'bz` and comparisons with 1/0 would fail.

**Expected simulation time:** ~20 ms (several full SCCB transactions at 100 kHz SCL)

---

### `tb_ov7670_capture` — Pixel Assembly

**What it does:** Generates OV7670-like VSYNC/HREF/PCLK/DATA signals and checks the BRAM write port.

**Key checks:**
- **Byte assembly**: first byte (high) + second byte (low) → correct 16-bit RGB565
- **Write address**: `row * 320 + col` computed correctly at every pixel
- **VSYNC reset**: col and row counters go back to 0 after VSYNC falling edge
- **HREF-low clearing**: if HREF drops after the first byte (partial pixel), `wr_en` never fires and next HREF high starts fresh on the high byte

**How the stimulus is generated:**  
A `send_pixel` task drives two bytes on consecutive PCLK rising edges with HREF=1, then captures `wr_addr`, `wr_data`, `wr_en` after the second byte.

---

### `tb_line_buffer` — 3-Row Neighbourhood Access

**What it does:** Streams rows of pixels with deterministic values and verifies the 3-row outputs match historical row data.

**Key checks:**
- After warming up 2 rows, `row1` contains the previous row and `row0` the row before that
- `row2` is a 1-cycle delayed version of `din` (matches BRAM latency)
- After a 4th row, `row0` contains what was previously `row1` (oldest row evicted)
- After `reset`, all outputs are zero

**Why outputs are read 1 cycle after pixel_advance:**  
Both `row0` and `row1` are driven from BRAM outputs which have 1 cycle of registered latency. The task `stream_row_and_check` samples on the clock after `pixel_advance`.

---

### `tb_pointwise_filters` — Grayscale, Brightness/Contrast, Channel Isolate

Three independent testbench modules in one file. All filters have 1-cycle pipeline latency — input is presented, output is read one clock later.

**Grayscale checks:**
- Known formula `Y = (77R + 150G + 29B) >> 8` verified for pure R/G/B, white, black, and mixed colours
- Bypass (`enable=0`) produces exact input passthrough
- `pixel_valid=0` results in `pvalid_out=0`

**Brightness/Contrast checks:**
- Each combination (none / brightness only / contrast only / both) against a software reference function that computes the expected clamped result
- Saturation cases (inputs near 255) verified to clamp at 255, not overflow

**Channel Isolate checks:**
- Each channel individually zeroes the other two
- Priority cases (en_R AND en_G → R wins) exhaustively verified

---

### `tb_conv_filters` — Box Blur, Sharpen, Edge Detect

All three use `line_buffer` internally, so 2 warm-up rows are streamed before checking outputs. Output is valid **2 cycles** after `pixel_advance`.

**Box Blur:**
- Uniform image → output ≈ same value (division-by-9 approximation allowed ±2)
- Bypass (`enable=0`) → output equals input delayed by 2 cycles

**Sharpen:**
- Flat image (centre = neighbours) → output unchanged
- Bright centre (200 vs 100 neighbours) → `5*200 - 4*100 = 600 → clamps to 255`
- Dark centre (10 vs 200 neighbours) → `5*10 - 4*200 = -750 → clamps to 0`
- Bypass verified

**Edge Detect:**
- Uniform grey → zero output (no gradient)
- Vertical step (left half = 0, right half = 255) → high Gx magnitude at boundary
- Bypass verified

---

### `tb_filter_pipeline_and_cm` — Integration Test

**Filter pipeline:**  
Simulates VGA scan timing (`drawX`, `drawY`, `active_nblank`) and checks outputs after the full 9-stage pipeline latency.

Key cases:
- Passthrough (all SW=0): RGB565 → RGB888 expansion matches expected formula
- Test pattern (SW[15]=1): bar 0 = white, bar 1 = yellow verified at correct drawX positions
- Grayscale (SW[0]=1): pure green pixel → correct greyscale value in output
- Blanking: `pvalid_out` goes low when `active_nblank=0`

**Color mapper:**  
Purely combinational; tests are immediate (no clock). Verifies correct 4-bit truncation and zero output during blanking.

---

### `tb_text_overlay` — Text Overlay Engine

Uses a **behavioural font_rom stub** that returns `8'hFF` for non-space characters and `8'h00` for space. This lets the TB verify compositing logic without needing the full 128-glyph bitmap ROM.

Key checks:
- **Outside banner**: `video_out` = `video_in` unchanged
- **Inside banner, foreground bit**: `video_out` = `FG_COLOR` (yellow)
- **Inside banner, space character**: `video_out` = `BG_COLOR` (navy)
- **Beyond text_len**: `video_out` = `video_in` unchanged (no banner past the string)
- **Vsync latch**: SW change mid-frame does NOT affect `text_buf_stable`; change only takes effect after next vsync falling edge
- **pvalid_out delay**: exactly 2 cycles behind `pixel_valid`

**Replacing the stub with the real font_rom:**  
Remove the `font_rom` module block at the top of `tb_text_overlay.sv` and ensure `font_rom.sv` from the AXI lab is included in the Vivado simulation source set.

---

## Common Simulation Errors and Fixes

| Error message | Cause | Fix |
|---|---|---|
| `Module 'line_buffer' not found` | Missing source file in sim set | Add `line_buffer.sv` to simulation sources |
| `pvalid_out should be 0` in capture TB | `wr_en` fires after HREF drops | Check `byte_sel` reset logic on HREF falling edge |
| `blur T1: uniform red channel` fails | Wrong approximation constant | Verify `(sum * 28) >> 8` with expected ±2 tolerance |
| `TIMEOUT – done never asserted` in SCCB TB | HALF_PERIOD parameter too large | Verify `HALF_PERIOD = cam_clk / 100kHz / 2 = 120` |
| `row2 mismatch` in line_buffer TB | BRAM read latency off by 1 | Read outputs 1 cycle AFTER pixel_advance, not same cycle |
| X-state in filter outputs | Reset not applied before stimulus | Ensure `reset=1` for ≥ 4 cycles before driving inputs |
| `font_rom` port mismatch | Stub vs real ROM interface differs | Check addr width (11 bits) and data width (8 bits) |

---

## Expected Pass Output (TCL Console)

```
=== Test 1: Bus idle after reset ===
[42] grayscale PASS: post-reset

=== Test 2: Basic write (0x15 = 0xA3) ===
[42] T2: START condition detected ✓
[42] T2: STOP condition detected ✓
[42] T2: transaction complete

...

========================================
ALL TESTS PASSED (0 errors)
========================================
```
