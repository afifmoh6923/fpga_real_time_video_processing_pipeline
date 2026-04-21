###############################################################################
# ece385_camera.xdc
# ECE 385 Final Project – OV7670 Camera + HDMI Pipeline
# AMD Urbana Board  –  Spartan-7  XC7S50-CSGA324
#
# PHYSICAL TIE-OFFS (no FPGA pin needed):
#   OV7670 RET  → 3.3V directly (PMOD Pin 6 / VCC rail)
#   OV7670 PWDN → GND  directly (PMOD Pin 5 / GND rail)
#
# PIN ASSIGNMENT SUMMARY
# ───────────────────────
#  PmodB  →  Camera control + timing  (8 signals, all 8 JB pins used)
#  PmodA  →  Camera data bus D[7:0]   (8 signals, all 8 JA pins used)
#
#  PmodB pin → signal mapping:
#    JB3_P  H16  Pin 7   cam_pclk    *** MRCC clock-capable – do not move ***
#    JB1_P  H18  Pin 1   cam_vsync
#    JB1_N  G18  Pin 2   cam_href
#    JB2_P  K14  Pin 3   cam_xclk
#    JB2_N  J15  Pin 4   cam_sioc
#    JB3_N  H17  Pin 8   cam_siod    (open-drain; PULLUP enabled below)
#
#  PmodA pin → signal mapping:
#    JA1_P  F14  Pin 1   cam_data[0]
#    JA3_P  J13  Pin 2   cam_data[1]
#    JA1_N  F15  Pin 3   cam_data[2]
#    JA3_N  J14  Pin 4   cam_data[3]
#    JA2_P  H13  Pin 7   cam_data[4]
#    JA4_P  E14  Pin 8   cam_data[5]
#    JA2_N  H14  Pin 9   cam_data[6]
#    JA4_N  E15  Pin 10  cam_data[7]
###############################################################################


###############################################################################
# SYSTEM CLOCK  –  100 MHz on-board oscillator
###############################################################################
set_property PACKAGE_PIN E3       [get_ports Clk]
set_property IOSTANDARD  LVCMOS33 [get_ports Clk]

create_clock -add -name sys_clk_pin \
             -period 10.00 \
             -waveform {0 5} \
             [get_ports Clk]


###############################################################################
# RESET BUTTON  –  BTNC
###############################################################################
set_property PACKAGE_PIN M18      [get_ports reset_btn]
set_property IOSTANDARD  LVCMOS33 [get_ports reset_btn]


###############################################################################
# SLIDE SWITCHES  SW[15:0]
#
# NOTE: J15 is used for cam_sioc (PmodB Pin 4).
#       SW[0] is therefore commented out to avoid a pin conflict.
#       If you need SW[0], move cam_sioc to a free JAB pin (e.g. C12)
#       and update the wiring + cam_sioc constraint accordingly.
###############################################################################
# set_property PACKAGE_PIN J15 [get_ports {SW[0]}]   <- conflicts with cam_sioc
set_property PACKAGE_PIN L16      [get_ports {SW[1]}]
set_property PACKAGE_PIN M13      [get_ports {SW[2]}]
set_property PACKAGE_PIN R15      [get_ports {SW[3]}]
set_property PACKAGE_PIN R17      [get_ports {SW[4]}]
set_property PACKAGE_PIN T18      [get_ports {SW[5]}]
set_property PACKAGE_PIN U18      [get_ports {SW[6]}]
set_property PACKAGE_PIN R13      [get_ports {SW[7]}]
set_property PACKAGE_PIN T8       [get_ports {SW[8]}]
set_property PACKAGE_PIN U8       [get_ports {SW[9]}]
set_property PACKAGE_PIN R16      [get_ports {SW[10]}]
set_property PACKAGE_PIN T13      [get_ports {SW[11]}]
set_property PACKAGE_PIN H6       [get_ports {SW[12]}]
set_property PACKAGE_PIN U12      [get_ports {SW[13]}]
set_property PACKAGE_PIN U11      [get_ports {SW[14]}]
set_property PACKAGE_PIN V10      [get_ports {SW[15]}]

set_property IOSTANDARD LVCMOS33  [get_ports {SW[*]}]


###############################################################################
# OV7670 CAMERA – CONTROL & TIMING  (PmodB)
#
# Physical wiring:
#   OV7670 PLK  → PmodB Pin 7  (H16)   *** clock-capable MRCC pin ***
#   OV7670 VS   → PmodB Pin 1  (H18)
#   OV7670 HS   → PmodB Pin 2  (G18)
#   OV7670 XLK  → PmodB Pin 3  (K14)
#   OV7670 SCL  → PmodB Pin 4  (J15)
#   OV7670 SDA  → PmodB Pin 8  (H17)
#   OV7670 RET  → PmodB Pin 6  (3.3V)  ← hard-wired, NO FPGA pin
#   OV7670 PWDN → PmodB Pin 5  (GND)   ← hard-wired, NO FPGA pin
###############################################################################

# cam_pclk  –  MUST stay on H16 (MRCC).  Moving it will break clock routing.
set_property PACKAGE_PIN H16      [get_ports cam_pclk]
set_property IOSTANDARD  LVCMOS33 [get_ports cam_pclk]

set_property PACKAGE_PIN H18      [get_ports cam_vsync]
set_property IOSTANDARD  LVCMOS33 [get_ports cam_vsync]

set_property PACKAGE_PIN G18      [get_ports cam_href]
set_property IOSTANDARD  LVCMOS33 [get_ports cam_href]

set_property PACKAGE_PIN K14      [get_ports cam_xclk]
set_property IOSTANDARD  LVCMOS33 [get_ports cam_xclk]

set_property PACKAGE_PIN J15      [get_ports cam_sioc]
set_property IOSTANDARD  LVCMOS33 [get_ports cam_sioc]

# cam_siod – open-drain SCCB data line; weak internal pull-up enabled.
# Your OV7670 board should also have a physical 4.7 kΩ pull-up to 3.3V on SDA.
set_property PACKAGE_PIN H17      [get_ports cam_siod]
set_property IOSTANDARD  LVCMOS33 [get_ports cam_siod]
set_property PULLUP      TRUE     [get_ports cam_siod]

# Camera pixel clock constraint  (OV7670 QVGA PCLK ≈ 12.5 MHz)
# Adjust the period if you measure a different frequency on your board.
create_clock -add -name cam_pclk_clk \
             -period 80.00 \
             -waveform {0 40} \
             [get_ports cam_pclk]


###############################################################################
# OV7670 CAMERA – DATA BUS  (PmodA)
#
# Physical wiring:
#   OV7670 D0 → PmodA Pin 1   (F14)
#   OV7670 D1 → PmodA Pin 2   (J13)
#   OV7670 D2 → PmodA Pin 3   (F15)
#   OV7670 D3 → PmodA Pin 4   (J14)
#   OV7670 D4 → PmodA Pin 7   (H13)
#   OV7670 D5 → PmodA Pin 8   (E14)
#   OV7670 D6 → PmodA Pin 9   (H14)
#   OV7670 D7 → PmodA Pin 10  (E15)
###############################################################################
set_property PACKAGE_PIN F14      [get_ports {cam_data[0]}]
set_property PACKAGE_PIN J13      [get_ports {cam_data[1]}]
set_property PACKAGE_PIN F15      [get_ports {cam_data[2]}]
set_property PACKAGE_PIN J14      [get_ports {cam_data[3]}]
set_property PACKAGE_PIN H13      [get_ports {cam_data[4]}]
set_property PACKAGE_PIN E14      [get_ports {cam_data[5]}]
set_property PACKAGE_PIN H14      [get_ports {cam_data[6]}]
set_property PACKAGE_PIN E15      [get_ports {cam_data[7]}]

set_property IOSTANDARD LVCMOS33  [get_ports {cam_data[*]}]


###############################################################################
# HDMI TX  –  On-board HDMI connector
# *** VERIFY these pins against your Urbana board schematic.            ***
# *** If using a Real Digital VGA-to-HDMI PMOD on JAB instead, replace ***
# *** with the appropriate JAB pin assignments (D10, D11, C12, etc.)    ***
###############################################################################
set_property PACKAGE_PIN D4       [get_ports hdmi_tmds_clk_p]
set_property IOSTANDARD  TMDS_33  [get_ports hdmi_tmds_clk_p]

set_property PACKAGE_PIN C4       [get_ports hdmi_tmds_clk_n]
set_property IOSTANDARD  TMDS_33  [get_ports hdmi_tmds_clk_n]

set_property PACKAGE_PIN D1       [get_ports {hdmi_tmds_data_p[0]}]
set_property IOSTANDARD  TMDS_33  [get_ports {hdmi_tmds_data_p[0]}]

set_property PACKAGE_PIN C1       [get_ports {hdmi_tmds_data_n[0]}]
set_property IOSTANDARD  TMDS_33  [get_ports {hdmi_tmds_data_n[0]}]

set_property PACKAGE_PIN B2       [get_ports {hdmi_tmds_data_p[1]}]
set_property IOSTANDARD  TMDS_33  [get_ports {hdmi_tmds_data_p[1]}]

set_property PACKAGE_PIN A2       [get_ports {hdmi_tmds_data_n[1]}]
set_property IOSTANDARD  TMDS_33  [get_ports {hdmi_tmds_data_n[1]}]

set_property PACKAGE_PIN D2       [get_ports {hdmi_tmds_data_p[2]}]
set_property IOSTANDARD  TMDS_33  [get_ports {hdmi_tmds_data_p[2]}]

set_property PACKAGE_PIN C2       [get_ports {hdmi_tmds_data_n[2]}]
set_property IOSTANDARD  TMDS_33  [get_ports {hdmi_tmds_data_n[2]}]


###############################################################################
# CLOCK DOMAIN CROSSING
# cam_pclk (write) and pixel_clk (read) are asynchronous.
# The dual-port BRAM handles the CDC; declare async groups to suppress
# false timing violations across the two domains.
###############################################################################
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk_pin] \
    -group [get_clocks cam_pclk_clk]


###############################################################################
# CONFIGURATION  –  Spartan-7 bitstream settings
###############################################################################
set_property CONFIG_VOLTAGE         3.3  [current_design]
set_property CFGBVS                 VCCO [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
