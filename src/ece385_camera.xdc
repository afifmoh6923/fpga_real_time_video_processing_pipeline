###############################################################################
# ece385_camera.xdc
# ECE 385 Final Project - OV7670 Camera + HDMI Pipeline
# AMD Urbana Board  -  Spartan-7  XC7S50-CSGA324
# All pin locations taken from URBANA BOARD CONSTRAINTS V2I1 1/3/2023
###############################################################################


###############################################################################
# SYSTEM CLOCK  -  100 MHz on-board oscillator  (Urbana: N15)
###############################################################################
set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33} [get_ports Clk]

create_clock -add -name sys_clk_pin \
             -period 10.00 \
             -waveform {0 5} \
             [get_ports Clk]


###############################################################################
# RESET BUTTON  -  BTN[0] = J2
###############################################################################
set_property -dict {PACKAGE_PIN J2 IOSTANDARD LVCMOS25} [get_ports reset_btn]


###############################################################################
# SLIDE SWITCHES  SW[15:0]  -  LVCMOS25 on Urbana
#
# SW[0] is mapped to a dummy safe free pin because J15 (its normal pin on other
# boards) is used here for cam_sioc.  Keep SW[0] physically DOWN at all times.
# All other switches use their correct Urbana pins.
###############################################################################
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports {SW[0]}]  ;# dummy - cam_sioc is on J15 which conflicts; keep SW[0] down
set_property -dict {PACKAGE_PIN F2  IOSTANDARD LVCMOS25} [get_ports {SW[1]}]
set_property -dict {PACKAGE_PIN F1  IOSTANDARD LVCMOS25} [get_ports {SW[2]}]
set_property -dict {PACKAGE_PIN E2  IOSTANDARD LVCMOS25} [get_ports {SW[3]}]
set_property -dict {PACKAGE_PIN E1  IOSTANDARD LVCMOS25} [get_ports {SW[4]}]
set_property -dict {PACKAGE_PIN D2  IOSTANDARD LVCMOS25} [get_ports {SW[5]}]
set_property -dict {PACKAGE_PIN D1  IOSTANDARD LVCMOS25} [get_ports {SW[6]}]
set_property -dict {PACKAGE_PIN C2  IOSTANDARD LVCMOS25} [get_ports {SW[7]}]
set_property -dict {PACKAGE_PIN B2  IOSTANDARD LVCMOS25} [get_ports {SW[8]}]
set_property -dict {PACKAGE_PIN A4  IOSTANDARD LVCMOS25} [get_ports {SW[9]}]
set_property -dict {PACKAGE_PIN A5  IOSTANDARD LVCMOS25} [get_ports {SW[10]}]
set_property -dict {PACKAGE_PIN A6  IOSTANDARD LVCMOS25} [get_ports {SW[11]}]
set_property -dict {PACKAGE_PIN C7  IOSTANDARD LVCMOS25} [get_ports {SW[12]}]
set_property -dict {PACKAGE_PIN A7  IOSTANDARD LVCMOS25} [get_ports {SW[13]}]
set_property -dict {PACKAGE_PIN B7  IOSTANDARD LVCMOS25} [get_ports {SW[14]}]
set_property -dict {PACKAGE_PIN A8  IOSTANDARD LVCMOS25} [get_ports {SW[15]}]


###############################################################################
# LEDs  LED[15:0]  -  LVCMOS33 on Urbana (from master XDC)
###############################################################################
set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS33} [get_ports {LED[0]}]
set_property -dict {PACKAGE_PIN C14 IOSTANDARD LVCMOS33} [get_ports {LED[1]}]
set_property -dict {PACKAGE_PIN D14 IOSTANDARD LVCMOS33} [get_ports {LED[2]}]
set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS33} [get_ports {LED[3]}]
set_property -dict {PACKAGE_PIN D16 IOSTANDARD LVCMOS33} [get_ports {LED[4]}]
set_property -dict {PACKAGE_PIN F18 IOSTANDARD LVCMOS33} [get_ports {LED[5]}]
set_property -dict {PACKAGE_PIN E17 IOSTANDARD LVCMOS33} [get_ports {LED[6]}]
set_property -dict {PACKAGE_PIN D17 IOSTANDARD LVCMOS33} [get_ports {LED[7]}]
set_property -dict {PACKAGE_PIN C17 IOSTANDARD LVCMOS33} [get_ports {LED[8]}]
set_property -dict {PACKAGE_PIN B18 IOSTANDARD LVCMOS33} [get_ports {LED[9]}]
set_property -dict {PACKAGE_PIN A17 IOSTANDARD LVCMOS33} [get_ports {LED[10]}]
set_property -dict {PACKAGE_PIN B17 IOSTANDARD LVCMOS33} [get_ports {LED[11]}]
set_property -dict {PACKAGE_PIN C18 IOSTANDARD LVCMOS33} [get_ports {LED[12]}]
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVCMOS33} [get_ports {LED[13]}]
set_property -dict {PACKAGE_PIN E18 IOSTANDARD LVCMOS33} [get_ports {LED[14]}]
set_property -dict {PACKAGE_PIN G17 IOSTANDARD LVCMOS33} [get_ports {LED[15]}]


###############################################################################
# OV7670 CAMERA - CONTROL & TIMING  (PmodB - from Urbana master XDC)
#
#   OV7670 PLK  -> JB3_P  H16  PmodB Pin 7  *** MRCC clock-capable ***
#   OV7670 VS   -> JB1_P  H18  PmodB Pin 1
#   OV7670 HS   -> JB1_N  G18  PmodB Pin 2
#   OV7670 XLK  -> JB2_P  K14  PmodB Pin 3  (NOT in master XDC - free LVCMOS33)
#   OV7670 SCL  -> JB2_N  J15  PmodB Pin 4  (NOT in master XDC - free LVCMOS33)
#   OV7670 SDA  -> JB3_N  H17  PmodB Pin 8
#   OV7670 RET  -> 3.3V directly on PmodB Pin 6  (no FPGA pin)
#   OV7670 PWDN -> GND    directly on PmodB Pin 5  (no FPGA pin)
###############################################################################

# cam_pclk - MUST stay on H16 (JB3_P MRCC pin). Do not move.
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports cam_pclk]

set_property -dict {PACKAGE_PIN H18 IOSTANDARD LVCMOS33} [get_ports cam_vsync]
set_property PULLDOWN TRUE [get_ports cam_vsync]
set_property PULLDOWN TRUE [get_ports {cam_data[0]}]
set_property PULLDOWN TRUE [get_ports {cam_data[1]}]
set_property PULLDOWN TRUE [get_ports {cam_data[2]}]
set_property PULLDOWN TRUE [get_ports {cam_data[3]}]
set_property PULLDOWN TRUE [get_ports {cam_data[4]}]
set_property PULLDOWN TRUE [get_ports {cam_data[5]}]
set_property PULLDOWN TRUE [get_ports {cam_data[6]}]
set_property PULLDOWN TRUE [get_ports {cam_data[7]}]
set_property -dict {PACKAGE_PIN G18 IOSTANDARD LVCMOS33} [get_ports cam_href]
set_property PULLDOWN TRUE [get_ports cam_href]
set_property -dict {PACKAGE_PIN K14 IOSTANDARD LVCMOS33} [get_ports cam_xclk]
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports cam_sioc]

# cam_siod - open-drain SCCB data; weak pull-up via FPGA I/O cell
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports cam_siod]
set_property PULLUP TRUE [get_ports cam_siod]

# cam_reset_n driven HIGH internally in top.sv; dummy pin JB4_P satisfies DRC
#set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports cam_reset_n]

# cam_pwdn driven LOW internally in top.sv; dummy pin JB4_N satisfies DRC
#set_property -dict {PACKAGE_PIN J16 IOSTANDARD LVCMOS33} [get_ports cam_pwdn]

# Camera pixel clock timing constraint (~12.5 MHz for QVGA)
create_clock -add -name cam_pclk_clk \
             -period 80.00 \
             -waveform {0 40} \
             [get_ports cam_pclk]


###############################################################################
# OV7670 CAMERA - DATA BUS D[7:0]  (PmodA - from Urbana master XDC)
#
#   D0 -> JA1_P  F14  PmodA Pin 1
#   D1 -> JA3_P  J13  PmodA Pin 2
#   D2 -> JA1_N  F15  PmodA Pin 3
#   D3 -> JA3_N  J14  PmodA Pin 4
#   D4 -> JA2_P  H13  PmodA Pin 7
#   D5 -> JA4_P  E14  PmodA Pin 8
#   D6 -> JA2_N  H14  PmodA Pin 9
#   D7 -> JA4_N  E15  PmodA Pin 10
###############################################################################
set_property -dict {PACKAGE_PIN F14 IOSTANDARD LVCMOS33} [get_ports {cam_data[0]}] ;# JA1_P
set_property -dict {PACKAGE_PIN H13 IOSTANDARD LVCMOS33} [get_ports {cam_data[1]}] ;# JA2_P
set_property -dict {PACKAGE_PIN J13 IOSTANDARD LVCMOS33} [get_ports {cam_data[2]}] ;# JA3_P
set_property -dict {PACKAGE_PIN E14 IOSTANDARD LVCMOS33} [get_ports {cam_data[3]}] ;# JA4_P

set_property -dict {PACKAGE_PIN F15 IOSTANDARD LVCMOS33} [get_ports {cam_data[4]}] ;# JA1_N
set_property -dict {PACKAGE_PIN H14 IOSTANDARD LVCMOS33} [get_ports {cam_data[5]}] ;# JA2_N
set_property -dict {PACKAGE_PIN J14 IOSTANDARD LVCMOS33} [get_ports {cam_data[6]}] ;# JA3_N
set_property -dict {PACKAGE_PIN E15 IOSTANDARD LVCMOS33} [get_ports {cam_data[7]}] ;# JA4_N


###############################################################################
# HDMI TX  -  from Urbana master XDC  (IOSTANDARD corrected to TMDS_33)
#
# Master XDC names -> our port names:
#   HDMI_DO_P  -> hdmi_tmds_data_p[0]   U17
#   HDMI_D0_N  -> hdmi_tmds_data_n[0]   U18
#   HDMI_D1_P  -> hdmi_tmds_data_p[1]   R16
#   HDMI_D1_N  -> hdmi_tmds_data_n[1]   R17
#   HDMI_D2_P  -> hdmi_tmds_data_p[2]   R14
#   HDMI_D2_N  -> hdmi_tmds_data_n[2]   T14
#   HDMI_CLK_P -> hdmi_tmds_clk_p       U16
#   HDMI_CLK_N -> hdmi_tmds_clk_n       V17
#
# NOTE: Master XDC had a typo "TDMS_33" - correct standard is TMDS_33
###############################################################################
set_property -dict {PACKAGE_PIN U17 IOSTANDARD TMDS_33} [get_ports {hdmi_tmds_data_p[0]}]
set_property -dict {PACKAGE_PIN U18 IOSTANDARD TMDS_33} [get_ports {hdmi_tmds_data_n[0]}]
set_property -dict {PACKAGE_PIN R16 IOSTANDARD TMDS_33} [get_ports {hdmi_tmds_data_p[1]}]
set_property -dict {PACKAGE_PIN R17 IOSTANDARD TMDS_33} [get_ports {hdmi_tmds_data_n[1]}]
set_property -dict {PACKAGE_PIN R14 IOSTANDARD TMDS_33} [get_ports {hdmi_tmds_data_p[2]}]
set_property -dict {PACKAGE_PIN T14 IOSTANDARD TMDS_33} [get_ports {hdmi_tmds_data_n[2]}]
set_property -dict {PACKAGE_PIN U16 IOSTANDARD TMDS_33} [get_ports hdmi_tmds_clk_p]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD TMDS_33} [get_ports hdmi_tmds_clk_n]


###############################################################################
# CLOCK ROUTING OVERRIDES
###############################################################################
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets cam_pclk_IBUF]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets clk_gen/inst/clk_in1]


###############################################################################
# CLOCK DOMAIN CROSSING
###############################################################################
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk_pin] \
    -group [get_clocks cam_pclk_clk]


###############################################################################
# CONFIGURATION  -  Spartan-7 / Urbana board settings
###############################################################################
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLUP [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
