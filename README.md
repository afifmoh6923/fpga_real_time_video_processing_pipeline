# Urbana Board Video Processing Pipeline with OV7670 Camera
**ECE 385 Final Project — Spring 2026**
Sanjiv Sainathan (sanjivs2) · Afif Mohamed Vavanan (amoha225)

---

## Overview

Real-time FPGA video processing pipeline implemented on the Urbana board (Xilinx Spartan-7). An OV7670 CMOS camera captures live 640×480 video over a parallel RGB565 bus, which is subsampled to 320×240 and stored in a dual-port block RAM frame buffer. The image is displayed centered in a 640×480 HDMI output and passed through a chain of eight independently switch-selectable image filters. A live text banner at the top of the screen shows the names of all active filters. The entire design is written in SystemVerilog and runs on the Urbana board without any soft processor.

---

## Features

- Live 640×480 OV7670 camera input, subsampled to 320×240 and centered on screen
- Dual-clock frame buffer (camera clock domain write, pixel clock domain read) using Simple Dual-Port BRAM
- Eight independently switch-selectable filters chained in a 9-stage pipeline with constant latency:
  - Brightness adjustment (SW3)
  - Contrast adjustment (SW4)
  - Red / Green / Blue channel isolation (SW5 / SW6 / SW7)
  - Grayscale conversion — BT.601 luminance (SW11)
  - 3×3 Box blur (SW2)
  - Unsharp mask sharpening — 8-neighbor kernel (SW8)
  - Sobel edge detection — binary thresholded (SW1)
  - Directional emboss (SW9)
  - Color inversion (SW12)
- SW15 enables a built-in 8-bar color test pattern (no camera needed)
- Live filter-name text overlay at top of screen, updated every vsync
- HDMI output via Real Digital HDMI TX IP (TMDS, 640×480 @ ~60 Hz)
- Camera initialized over SCCB (I2C-compatible) with a 97-register configuration table

---

## Hardware Requirements

- Urbana board (Xilinx Spartan-7 XC7S50)
- OV7670 camera module (without FIFO) connected to PMOD JA/JB
- HDMI monitor
- Micro-USB cable for programming

---

## Project Structure

```
├── top.sv                  # Top-level module, clock and pin connections
├── VGA_controller.sv       # 640×480 VGA timing generator
├── ov7670_sccb.sv          # SCCB (I2C-compatible) bit-bang controller
├── ov7670_init.sv          # Camera power-up and register configuration FSM
├── ov7670_capture.sv       # Parallel pixel bus decoder and frame buffer writer
├── filter_pipeline.sv      # Filter chain orchestrator, pixel/row advance control
├── pointwise_filters.sv    # Grayscale, brightness/contrast, channel isolate, invert
├── box_blur.sv             # 3×3 uniform averaging filter
├── conv_filters.sv         # Sharpen, Sobel edge detect, emboss (3×3 convolution)
├── line_buffer.sv          # Dual-BRAM ping-pong two-line delay for 3×3 kernels
├── text_overlay.sv         # Filter-name banner renderer using font ROM
├── color_mapper.sv         # RGB888 → RGB444 + VDE for HDMI TX IP
├── font_rom.sv             # IBM Codepage 437 glyph ROM (128 glyphs, 8×16)
├── sync.sv                 # Two-flop synchronizer and debouncer
├── ece385_camera.xdc       # Constraints file (pins, clocks, IOSTANDARD)
└── IP_Integration_Steps.md # Vivado IP setup instructions (clk_wiz, BRAM, HDMI TX)
```

---

## Vivado IP Required

Three IPs must be generated before synthesis. Full configuration details are in `IP_Integration_Steps.md`.

| IP | Component name | Key settings |
|---|---|---|
| Clocking Wizard | `clk_wiz_0` | 25 MHz (pixel), 125 MHz (TMDS), 24 MHz (camera XCLK) |
| Block Memory Generator | `blk_mem_gen_0` | Simple Dual Port, 16-bit × 76800, separate clocks |
| Real Digital HDMI TX | `hdmi_tx_0` | 4-bit per channel, HDMI mode |

---

## Build Instructions

1. Open Vivado and create a new RTL project targeting the Spartan-7 XC7S50.
2. Follow `IP_Integration_Steps.md` to generate all three IPs.
3. Add all `.sv` files to the project. Right-click `top.sv` → Set as Top.
4. Add `ece385_camera.xdc` as the constraints file.
5. Run Synthesis → Implementation → Generate Bitstream.
6. Open Hardware Manager → Program Device.

---

## Bring-up Sequence

Test subsystems in order to isolate issues early.

1. **SW15 = 1** — Should show 8-bar color pattern. Verifies clocks, VGA, HDMI TX.
2. **Camera connected, power on** — `config_done` lights LED[15] after ~1.5 s.
3. **Live image** — 320×240 camera image appears centered on screen.
4. **Toggle filters one at a time** — Verify each switch produces the expected effect.

---

## Filter Switch Map

| Switch | Filter |
|---|---|
| SW1 | Sobel edge detection |
| SW2 | Box blur |
| SW3 | Brightness +32 |
| SW4 | Contrast stretch |
| SW5 | Red channel only |
| SW6 | Green channel only |
| SW7 | Blue channel only |
| SW8 | Sharpen (unsharp mask) |
| SW9 | Emboss |
| SW11 | Grayscale (BT.601) |
| SW12 | Color inversion |
| SW15 | Test pattern (overrides camera) |

---

## Clock Domains

| Domain | Source | Frequency | Used by |
|---|---|---|---|
| `pixel_clk` | clk_wiz_0 clk_out1 | 25 MHz | VGA, BRAM read, filters, text, HDMI |
| `tmds_clk` | clk_wiz_0 clk_out2 | 125 MHz | HDMI TX serializer |
| `cam_clk_int` | clk_wiz_0 clk_out3 | 24 MHz | Camera XCLK input, SCCB controller |
| `cam_pclk_buf` | OV7670 PCLK via BUFG | ~24 MHz | BRAM write, ov7670_capture |

---

## Known Issues and Notes

- SW0 is faulty on our physical board (stuck high). Grayscale was remapped to SW11.
- `cam_pclk` must be connected to a clock-capable (MRCC/SRCC) FPGA pin. Verify against the Urbana board schematic before assigning in the XDC.
- The OV7670 byte ordering in RGB565 mode is second-byte-first. Swapping bytes in `ov7670_capture.sv` corrects the color output.
- Camera initialization takes approximately 1.5 seconds after bitstream load before `config_done` asserts and live video appears.
- Neighborhood filters (blur, sharpen, edge, emboss) require correct `pixel_advance` / `row_advance` timing. These signals are pipelined through a shift register in `filter_pipeline.sv` to stay aligned with the 9-stage pipeline depth.

---

## References

- OV7670/OV7171 CMOS VGA CAMERACHIP Datasheet, OmniVision Technologies, v1.01 (2005)
- Xilinx Block Memory Generator Product Guide (PG058)
- Real Digital HDMI TX IP documentation
- Linux kernel `ov7670.c` driver register table
- Mike Field, Hamsterworks OV7670 Verilog reference project