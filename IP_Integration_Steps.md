# Vivado IP Integration Steps
## ECE 385 Final Project — Real-Time FPGA Video Processing Pipeline

This document covers every Vivado GUI step needed to create the three IPs
and the BRAM before building the project.  Do these **before** running
synthesis.

---

## IP 1 — Clocking Wizard (`clk_wiz_0`)

**Tools → IP Catalog → Search "Clocking Wizard" → Double-click**

### Clocking Options tab
| Field | Value |
|---|---|
| Primitive | MMCM |
| Input clock | Primary, 100.000 MHz, Single-ended |

### Output Clocks tab
| Clock | Requested (MHz) | Port name |
|---|---|---|
| clk_out1 | 25.000 | `clk_out1` (rename to `pixel_clk` in top if you prefer) |
| clk_out2 | 125.000 | `clk_out2` |
| clk_out3 | 24.000 | `clk_out3` |

Check **"Reset Type: Active High"**, uncheck locked requirement for now.

Click **OK → Generate**.

> **Why these frequencies?**
> 25 MHz × 800 × 525 ≈ 59.5 Hz — standard VGA refresh.
> 125 MHz = 5 × 25 MHz — required TMDS bit clock for HDMI.
> 24 MHz — OV7670 XCLK; camera generates its own PCLK from this.

---

## IP 2 — Block Memory Generator (`blk_mem_gen_0`) — Frame Buffer

**Tools → IP Catalog → Search "Block Memory Generator" → Double-click**

### Basic tab
| Field | Value |
|---|---|
| Component name | `blk_mem_gen_0` |
| Memory type | **Simple Dual Port RAM** |
| ECC | No ECC |

### Port A Options (WRITE port — camera clock domain)
| Field | Value |
|---|---|
| Write width | **16** |
| Write depth | **76800** ← (320 × 240; Vivado rounds up to next power of two internally but accepts this) |
| Operating Mode | Write First |
| Enable Port Type | Always Enabled |

> Vivado may auto-set address width to 17 bits (2^17 = 131072 ≥ 76800). This is fine.

### Port B Options (READ port — pixel_clk domain)
| Field | Value |
|---|---|
| Read width | **16** |
| Enable Port Type | Always Enabled |
| **Check "Primitives Output Register"** | ✓ |

> The output register adds 1 cycle of read latency.  This is why `top.sv`
> pre-computes `fb_rd_addr` one cycle early using the delayed `drawX_d / drawY_d`.

### Other Options tab
| Field | Value |
|---|---|
| **Uncheck "Common Clock"** | ✗ — ports have different clocks |
| Load Init File | No |

Click **OK → Generate**.

Port names produced:
```
clka, wea[0], addra[16:0], dina[15:0]     ← write port
clkb,         addrb[16:0], doutb[15:0]    ← read port
```

---

## IP 3 — Real Digital VGA→HDMI Transmitter (`hdmi_tx_0`)

This IP was used in the USB lab (IUSB document).
Follow the same repository-import procedure:

### Step A — Add Repository
1. **Project Manager → IP Catalog** (left panel)
2. Right-click **"Vivado Repository"** → **"Add Repository"**
3. Navigate to the **`hdmi_tx_1.0`** folder from the lab ZIP → click **Select**
4. Vivado reports "1 IP found" — click **OK**

### Step B — Instantiate and Configure
**IP Catalog → User Repository → hdmi_tx_v1_0 → Double-click**

| Field | Value |
|---|---|
| Component name | `hdmi_tx_0` |
| Blue Channel Data Width | **4** |
| Green Channel Data Width | **4** |
| Red Channel Data Width | **4** |
| Mode | **HDMI** |

Click **OK → Out-of-context run → Generate**.

Port interface:
```
pix_clk        ← 25 MHz pixel_clk
pix_clkx5      ← 125 MHz tmds_clk
pix_clk_locked ← tie to 1'b1
rst            ← reset_btn
red[3:0]       ← from color_mapper
green[3:0]     ← from color_mapper
blue[3:0]      ← from color_mapper
hsync          ← hs from vga_controller
vsync          ← vs from vga_controller
vde            ← from color_mapper
hdmi_tx_p[2:0] → hdmi_tmds_data_p
hdmi_tx_n[2:0] → hdmi_tmds_data_n
hdmi_clk_p     → hdmi_tmds_clk_p
hdmi_clk_n     → hdmi_tmds_clk_n
```

---

## File Import Checklist

After generating all IPs, import/copy these source files into your Vivado project
(**File → Add Sources → Add or create design sources → Add Files**):

Check "**Copy sources into project**" for all files.

| File | Source |
|---|---|
| `top.sv` | This project |
| `VGA_controller.sv` | Provided (existing) |
| `sync.sv` | Provided (existing) |
| `ov7670_sccb.sv` | This project |
| `ov7670_init.sv` | This project |
| `ov7670_capture.sv` | This project |
| `line_buffer.sv` | This project |
| `pointwise_filters.sv` | This project (contains grayscale, brightness_contrast, channel_isolate) |
| `box_blur.sv` | This project |
| `conv_filters.sv` | This project (contains sharpen, edge_detect) |
| `filter_pipeline.sv` | This project |
| `text_overlay.sv` | This project |
| `color_mapper.sv` | This project |
| `font_rom.sv` | **Copy from AXI lab project** |

> **Right-click `top.sv` → Set as Top** after importing all files.

---

## Constraints File (`.xdc`)

Start from the Urbana board master XDC.  Add camera PMOD pins and HDMI pins.

### HDMI Pins (Urbana board standard — verify with your schematic)
```tcl
# HDMI TMDS data
set_property PACKAGE_PIN W19  [get_ports {hdmi_tmds_data_p[2]}]
set_property PACKAGE_PIN W20  [get_ports {hdmi_tmds_data_n[2]}]
set_property PACKAGE_PIN V18  [get_ports {hdmi_tmds_data_p[1]}]
set_property PACKAGE_PIN V19  [get_ports {hdmi_tmds_data_n[1]}]
set_property PACKAGE_PIN U18  [get_ports {hdmi_tmds_data_p[0]}]
set_property PACKAGE_PIN U19  [get_ports {hdmi_tmds_data_n[0]}]
set_property PACKAGE_PIN R19  [get_ports hdmi_tmds_clk_p]
set_property PACKAGE_PIN T19  [get_ports hdmi_tmds_clk_n]
set_property IOSTANDARD TMDS_33 [get_ports hdmi_tmds_*]
```

### OV7670 PMOD pins
**CRITICAL**: `cam_pclk` must connect to a **clock-capable (MRCC/SRCC)** FPGA pin.
Check the Urbana board schematic to find which PMOD connector pins are clock-capable.

```tcl
# Example: PMOD JA (adjust pin names to match actual Urbana PMOD assignments)
# cam_pclk MUST be on a clock-capable pin — verify in schematic
set_property PACKAGE_PIN <MRCC_PIN>  [get_ports cam_pclk]
set_property PACKAGE_PIN <PIN>       [get_ports cam_xclk]
set_property PACKAGE_PIN <PIN>       [get_ports cam_sioc]
set_property PACKAGE_PIN <PIN>       [get_ports cam_siod]
set_property PACKAGE_PIN <PIN>       [get_ports cam_vsync]
set_property PACKAGE_PIN <PIN>       [get_ports cam_href]
set_property PACKAGE_PIN <PIN>       [get_ports {cam_data[0]}]
set_property PACKAGE_PIN <PIN>       [get_ports {cam_data[1]}]
set_property PACKAGE_PIN <PIN>       [get_ports {cam_data[2]}]
set_property PACKAGE_PIN <PIN>       [get_ports {cam_data[3]}]
set_property PACKAGE_PIN <PIN>       [get_ports {cam_data[4]}]
set_property PACKAGE_PIN <PIN>       [get_ports {cam_data[5]}]
set_property PACKAGE_PIN <PIN>       [get_ports {cam_data[6]}]
set_property PACKAGE_PIN <PIN>       [get_ports {cam_data[7]}]
set_property PACKAGE_PIN <PIN>       [get_ports cam_reset_n]
set_property PACKAGE_PIN <PIN>       [get_ports cam_pwdn]
set_property IOSTANDARD LVCMOS33 [get_ports cam_*]

# Clock constraint for cam_pclk (camera generates ~24 MHz PCLK)
create_clock -period 41.667 -name cam_pclk [get_ports cam_pclk]
```

---

## Build Sequence

Run these in order in Vivado.  Fix any errors before moving to the next step.

```
1.  Generate all IPs (steps above)
2.  Import all source files, set top.sv as top
3.  Import / update constraints (.xdc)
4.  Run Synthesis  →  check for errors in Messages pane
        Common errors:
          "module not found" → missing source file
          "port mismatch"    → signal name typo between modules
          "BRAM primitive mismatch" → check blk_mem_gen port names
5.  Open Synthesised Design → check resource utilisation
        LUTs:  expect ~4,000–8,000 of 32,600 available
        BRAM:  expect ~7–10 of 75 available
        DSP:   expect ~10–20 (from grayscale multiply, blur multiply)
6.  Run Implementation
7.  Open Implemented Design → check timing
        Worst Negative Slack (WNS) must be ≥ 0
        If negative: pipeline the failing path or reduce clock frequency
8.  Generate Bitstream
9.  Program Device (Hardware Manager → Program)
```

---

## Bring-up Sequence  (power-on testing order)

Follow this order — each step verifies a sub-system before adding complexity.

### Stage 1 — HDMI color bars  (no camera needed)
- Set SW[15] = 1 (test pattern)
- Expected: 8 vertical color bars on HDMI monitor
- Verifies: clk_wiz, VGA controller, color_mapper, HDMI IP, constraints

### Stage 2 — Black screen with text overlay
- Set SW[15] = 0, all other switches = 0
- Expected: "PASSTHROUGH" text in yellow on dark blue banner, black below
- Verifies: font_rom instantiation, text_overlay string builder, vsync latch

### Stage 3 — Camera init
- Power camera (verify 3.3V on PMOD)
- Connect oscilloscope or logic analyzer to SIOC/SIOD
- Expected: SCCB clock at ~100 kHz; ~75 write transactions on startup
- Verifies: ov7670_sccb, ov7670_init state machine, register table

### Stage 4 — Live camera image
- After init completes (config_done → LED if wired up)
- Expected: 320×240 camera image pixel-doubled to full screen
- Verifies: ov7670_capture byte assembly, frame buffer write/read, pixel-doubling

### Stage 5 — Individual filters
- Enable one switch at a time, verify each filter independently
- Test order: SW[0] (grayscale) → SW[5/6/7] (channel) → SW[3/4] (brightness/contrast)
  → SW[2] (blur) → SW[8] (sharpen) → SW[1] (edge)

### Stage 6 — Multi-filter combinations
- Enable multiple filters together
- Verify filter names update in overlay correctly
- Confirm no timing violations with full pipeline active

---

## Common Pitfalls

| Symptom | Likely Cause | Fix |
|---|---|---|
| HDMI monitor shows "No Signal" | HDMI IP differential pins undriven | Ensure VGA + HDMI IP are fully connected before bitstream |
| Distorted/shifted image | BRAM read latency not compensated | Verify drawX_d / drawY_d delay in top.sv |
| Camera image is green/purple | RGB565 byte order swapped | Swap high_byte and cam_data assignments in ov7670_capture |
| Camera image doesn't appear | cam_pclk not on MRCC/SRCC pin | Re-assign pin in XDC; check schematic |
| SCCB transactions never complete | HALF_PERIOD counter wrong | Verify HALF_PERIOD = cam_clk_freq / SCL_freq / 2 |
| Text overlay garbled | text_buf index overflow | Check ptr never exceeds MAX_CHARS (40) |
| Timing violation on filter path | Long combinational path in Sobel | Add pipeline register between Gx/Gy computation and abs/clamp |
| Image only appears top-left | cam_x/cam_y counter not resetting on VSYNC | Check vsync falling-edge detection in ov7670_capture |
| Image tears on filter switch | text_buf updating mid-frame | Verify vsync_fall latch in text_overlay |
```
