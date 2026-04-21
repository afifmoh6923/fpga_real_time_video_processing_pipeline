###############################################################################
# ece385_camera.xdc
# ECE 385 Final Project – OV7670 Camera + HDMI Pipeline
# Urbana Board (Nexys 4 DDR / XC7A100T-CSG324)
#
# PIN ASSIGNMENT STRATEGY
# ───────────────────────
#  PmodB  (JB connector, 8 signal pins) → Camera CONTROL + TIMING signals
#           cam_pclk  → H16  JB3_P  *** MRCC clock-capable pin ***
#           cam_vsync → H18  JB1_P
#           cam_href  → G18  JB1_N
#           cam_xclk  → K14  JB2_P
#           cam_sioc  → J15  JB2_N
#           cam_siod  → H17  JB3_N  (open-drain; pull-up set below)
#           cam_reset_n → K16 JB4_P (driven HIGH internally – just needs a pin)
#           cam_pwdn  → J16  JB4_N  (driven LOW  internally – just needs a pin)
#
#  PmodA  (JA connector, 8 signal pins) → Camera DATA BUS [7:0]
#           cam_data[0] → F14  JA1_P
#           cam_data[1] → J13  JA3_P
#           cam_data[2] → F15  JA1_N
#           cam_data[3] → J14  JA3_N
#           cam_data[4] → H13  JA2_P
#           cam_data[5] → E14  JA4_P
#           cam_data[6] → H14  JA2_N
#           cam_data[7] → E15  JA4_N
#
# IMPORTANT NOTES BEFORE SYNTHESISING
# ─────────────────────────────────────
# 1. cam_pclk is placed on H16 (IO_L13P_T2_MRCC_35), a dedicated Multi-Region
#    Clock Capable (MRCC) pin.  This allows it to be routed through a BUFG
#    without any CLOCK_DEDICATED_ROUTE override.  Do NOT move cam_pclk to a
#    non-clock-capable pin.
#
# 2. cam_siod (SCCB data) is open-drain.  The KEEPER/PULLUP constraint below
#    adds a weak pull-up via the FPGA's I/O cell.  Your OV7670 PMOD board
#    should also have a physical 4.7 kΩ pull-up to 3.3 V on SIOD; if it does,
#    you can remove the PULLUP constraint.
#
# 3. HDMI pins – these are the standard Nexys 4 DDR on-board HDMI-TX pins.
#    *** VERIFY these against the Urbana board schematic if different. ***
#    If you are using a Real Digital VGA-to-HDMI PMOD instead, plug it into
#    JAB and replace these assignments with the JAB pin numbers.
#
# 4. Switch / button pins – standard Nexys 4 DDR assignments are listed.
#    *** CROSS-CHECK with the Urbana board master XDC before use. ***
#    NOTE: J15 (SW[0] on Nexys 4 DDR) is reassigned here to cam_sioc.
#    If you need SW[0], reroute cam_sioc to a free JAB pin (e.g., C12 = JAB_1).
###############################################################################


###############################################################################
# SYSTEM CLOCK  –  100 MHz on-board oscillator
###############################################################################
set_property PACKAGE_PIN E3      [get_ports Clk]
set_property IOSTANDARD  LVCMOS33 [get_ports Clk]

create_clock -add -name sys_clk_pin \
             -period 10.00 \
             -waveform {0 5} \
             [get_ports Clk]


###############################################################################
# RESET BUTTON  –  BTNC on Urbana / Nexys 4 DDR
###############################################################################
set_property PACKAGE_PIN M18     [get_ports reset_btn]
set_property IOSTANDARD  LVCMOS33 [get_ports reset_btn]


###############################################################################
# SLIDE SWITCHES  –  SW[15:0]
# NOTE: J15 is intentionally OMITTED here because it is used for cam_sioc.
#       SW[0] is therefore unavailable when the camera PMOD is connected.
#       All remaining switches (SW[1]–SW[15]) are unaffected.
###############################################################################
# set_property PACKAGE_PIN J15 [get_ports {SW[0]}]  ← CONFLICT with cam_sioc
set_property PACKAGE_PIN L16     [get_ports {SW[1]}]
set_property PACKAGE_PIN M13     [get_ports {SW[2]}]
set_property PACKAGE_PIN R15     [get_ports {SW[3]}]
set_property PACKAGE_PIN R17     [get_ports {SW[4]}]
set_property PACKAGE_PIN T18     [get_ports {SW[5]}]
set_property PACKAGE_PIN U18     [get_ports {SW[6]}]
set_property PACKAGE_PIN R13     [get_ports {SW[7]}]
set_property PACKAGE_PIN T8      [get_ports {SW[8]}]
set_property PACKAGE_PIN U8      [get_ports {SW[9]}]
set_property PACKAGE_PIN R16     [get_ports {SW[10]}]
set_property PACKAGE_PIN T13     [get_ports {SW[11]}]
set_property PACKAGE_PIN H6      [get_ports {SW[12]}]
set_property PACKAGE_PIN U12     [get_ports {SW[13]}]
set_property PACKAGE_PIN U11     [get_ports {SW[14]}]
set_property PACKAGE_PIN V10     [get_ports {SW[15]}]

set_property IOSTANDARD LVCMOS33 [get_ports {SW[*]}]


###############################################################################
# OV7670 CAMERA – CONTROL & TIMING  (PmodB / JB connector)
#
# Physical wiring guide for your OV7670 PMOD board
# (numbers are PMOD connector pin numbers on the Urbana JB header):
#
#   JB Pin 7  → cam_pclk   (H16 MRCC) ← CAMERA PCLK output
#   JB Pin 1  → cam_vsync  (H18)       ← CAMERA VSYNC output
#   JB Pin 2  → cam_href   (G18)       ← CAMERA HREF output  [JB1_N]
#   JB Pin 3  → cam_xclk   (K14)       ← FPGA drives ~24 MHz to camera
#   JB Pin 4  → cam_sioc   (J15)       ← SCCB clock  [JB2_N]
#   JB Pin 8  → cam_siod   (H17)       ← SCCB data (open-drain) [JB3_N]
#   JB Pin 9  → cam_reset_n (K16)      ← driven HIGH by FPGA [JB4_P]
#   JB Pin 10 → cam_pwdn   (J16)       ← driven LOW  by FPGA [JB4_N]
#
# Refer to your OV7670 PMOD board's datasheet to match its labelled pins
# (PCLK, VSYNC, HREF, XCLK, SIOC, SIOD, RESET, PWDN) to the above.
###############################################################################

# cam_pclk – MRCC clock-capable pin (MUST stay on H16)
set_property PACKAGE_PIN H16     [get_ports cam_pclk]
set_property IOSTANDARD  LVCMOS33 [get_ports cam_pclk]

set_property PACKAGE_PIN H18     [get_ports cam_vsync]
set_property IOSTANDARD  LVCMOS33 [get_ports cam_vsync]

set_property PACKAGE_PIN G18     [get_ports cam_href]
set_property IOSTANDARD  LVCMOS33 [get_ports cam_href]

set_property PACKAGE_PIN K14     [get_ports cam_xclk]
set_property IOSTANDARD  LVCMOS33 [get_ports cam_xclk]

set_property PACKAGE_PIN J15     [get_ports cam_sioc]
set_property IOSTANDARD  LVCMOS33 [get_ports cam_sioc]

# cam_siod – INOUT open-drain SCCB; weak pull-up enabled via FPGA I/O cell
set_property PACKAGE_PIN H17     [get_ports cam_siod]
set_property IOSTANDARD  LVCMOS33 [get_ports cam_siod]
set_property PULLUP      TRUE     [get_ports cam_siod]

set_property PACKAGE_PIN K16     [get_ports cam_reset_n]
set_property IOSTANDARD  LVCMOS33 [get_ports cam_reset_n]

set_property PACKAGE_PIN J16     [get_ports cam_pwdn]
set_property IOSTANDARD  LVCMOS33 [get_ports cam_pwdn]

# Camera pixel clock – create a clock constraint so Vivado can analyse timing
# across the cam_pclk → BRAM write-port path.
# Typical OV7670 QVGA PCLK = ~12.5 MHz (half of 25 MHz).
# Replace 80.00 ns (12.5 MHz) with the actual measured period if different.
create_clock -add -name cam_pclk_clk \
             -period 80.00 \
             -waveform {0 40} \
             [get_ports cam_pclk]


###############################################################################
# OV7670 CAMERA – DATA BUS [7:0]  (PmodA / JA connector)
#
# Physical wiring guide:
#   JA Pin 1  → cam_data[0]  (F14 JA1_P)
#   JA Pin 2  → cam_data[1]  (J13 JA3_P)
#   JA Pin 3  → cam_data[2]  (F15 JA1_N)
#   JA Pin 4  → cam_data[3]  (J14 JA3_N)
#   JA Pin 7  → cam_data[4]  (H13 JA2_P)
#   JA Pin 8  → cam_data[5]  (E14 JA4_P)
#   JA Pin 9  → cam_data[6]  (H14 JA2_N)
#   JA Pin 10 → cam_data[7]  (E15 JA4_N)
#
# Match these to the D0–D7 labels on your OV7670 PMOD board.
# OV7670 RGB565 byte order: MSB = D7 (red/green), LSB = D0 (green/blue).
###############################################################################

set_property PACKAGE_PIN F14     [get_ports {cam_data[0]}]
set_property PACKAGE_PIN J13     [get_ports {cam_data[1]}]
set_property PACKAGE_PIN F15     [get_ports {cam_data[2]}]
set_property PACKAGE_PIN J14     [get_ports {cam_data[3]}]
set_property PACKAGE_PIN H13     [get_ports {cam_data[4]}]
set_property PACKAGE_PIN E14     [get_ports {cam_data[5]}]
set_property PACKAGE_PIN H14     [get_ports {cam_data[6]}]
set_property PACKAGE_PIN E15     [get_ports {cam_data[7]}]

set_property IOSTANDARD LVCMOS33 [get_ports {cam_data[*]}]


###############################################################################
# HDMI TX  –  On-board HDMI connector (Nexys 4 DDR / Urbana board)
# Uses TMDS_33 differential standard.
# *** VERIFY these pin numbers against your Urbana board schematic. ***
# If you are using a Real Digital VGA-to-HDMI PMOD on JAB, replace with:
#   hdmi_tmds_clk_p  → D10 (JAB_5)   hdmi_tmds_clk_n  → D11 (JAB_0)
#   hdmi_tmds_data_p[0] → C12 (JAB_1) hdmi_tmds_data_n[0] → C11 (JAB_4)
#   hdmi_tmds_data_p[1] → E16 (JAB_2) hdmi_tmds_data_n[1] → G16 (JAB_3)
#   hdmi_tmds_data_p[2] → (free JAB pin)  etc.
###############################################################################

set_property PACKAGE_PIN D4      [get_ports hdmi_tmds_clk_p]
set_property IOSTANDARD  TMDS_33  [get_ports hdmi_tmds_clk_p]
set_property PACKAGE_PIN C4      [get_ports hdmi_tmds_clk_n]
set_property IOSTANDARD  TMDS_33  [get_ports hdmi_tmds_clk_n]

set_property PACKAGE_PIN D1      [get_ports {hdmi_tmds_data_p[0]}]
set_property IOSTANDARD  TMDS_33  [get_ports {hdmi_tmds_data_p[0]}]
set_property PACKAGE_PIN C1      [get_ports {hdmi_tmds_data_n[0]}]
set_property IOSTANDARD  TMDS_33  [get_ports {hdmi_tmds_data_n[0]}]

set_property PACKAGE_PIN B2      [get_ports {hdmi_tmds_data_p[1]}]
set_property IOSTANDARD  TMDS_33  [get_ports {hdmi_tmds_data_p[1]}]
set_property PACKAGE_PIN A2      [get_ports {hdmi_tmds_data_n[1]}]
set_property IOSTANDARD  TMDS_33  [get_ports {hdmi_tmds_data_n[1]}]

set_property PACKAGE_PIN D2      [get_ports {hdmi_tmds_data_p[2]}]
set_property IOSTANDARD  TMDS_33  [get_ports {hdmi_tmds_data_p[2]}]
set_property PACKAGE_PIN C2      [get_ports {hdmi_tmds_data_n[2]}]
set_property IOSTANDARD  TMDS_33  [get_ports {hdmi_tmds_data_n[2]}]


###############################################################################
# CLOCK DOMAIN CROSSING  –  tell Vivado these are async paths
# cam_pclk writes BRAM; pixel_clk reads BRAM.  The dual-port BRAM in
# blk_mem_gen_0 handles the CDC safely, so we declare a false path here
# to avoid spurious timing errors across the two clock domains.
###############################################################################
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk_pin] \
    -group [get_clocks cam_pclk_clk]

# Also declare clk_wiz_0 outputs as separate async groups once the wizard
# IP is configured (Vivado auto-generates these constraints in the IP's
# .xdc; add manual overrides only if timing closure becomes difficult).


###############################################################################
# CONFIGURATION  –  general Artix-7 bitstream settings
###############################################################################
set_property CONFIG_VOLTAGE        3.3 [current_design]
set_property CFGBVS                VCCO [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
