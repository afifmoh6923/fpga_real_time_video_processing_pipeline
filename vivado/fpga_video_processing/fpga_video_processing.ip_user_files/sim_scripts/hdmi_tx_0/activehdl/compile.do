transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

vlib work
vlib activehdl/xpm
vlib activehdl/xil_defaultlib

vmap xpm activehdl/xpm
vmap xil_defaultlib activehdl/xil_defaultlib

vlog -work xpm  -sv2k12 "+incdir+../../../../../../../../../../../../Xilinx/2025.1/Vivado/data/rsb/busdef" -l xpm -l xil_defaultlib \
"C:/Xilinx/2025.1/Vivado/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm -93  \
"C:/Xilinx/2025.1/Vivado/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work xil_defaultlib  -v2k5 "+incdir+../../../../../../../../../../../../Xilinx/2025.1/Vivado/data/rsb/busdef" -l xpm -l xil_defaultlib \
"../../../../fpga_video_processing.gen/sources_1/ip/hdmi_tx_0/hdl/encode.v" \
"../../../../fpga_video_processing.gen/sources_1/ip/hdmi_tx_0/hdl/serdes_10_to_1.v" \
"../../../../fpga_video_processing.gen/sources_1/ip/hdmi_tx_0/hdl/srldelay.v" \
"../../../../fpga_video_processing.gen/sources_1/ip/hdmi_tx_0/hdl/hdmi_tx_v1_0.v" \
"../../../../fpga_video_processing.gen/sources_1/ip/hdmi_tx_0/sim/hdmi_tx_0.v" \

vlog -work xil_defaultlib \
"glbl.v"

