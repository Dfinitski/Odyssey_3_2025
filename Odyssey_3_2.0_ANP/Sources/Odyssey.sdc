# Odyssey.sdc  -  Odyssey-III firmware (Hermes new protocol), EP4CE55F23C8
#
# 2026 rework of the Ethernet part (same methodology as Bootloader 3.3, which
# closes timing on the same board):
#   * RGMII RX/TX really constrained now. Before, "set_clock_groups -exclusive
#     -group {X}" with ONE group cut X from every clock, so no RGMII I/O path
#     was analysed at all.
#   * GTX_CLK = generated clock on the PHY_TX_CLOCK pin, forwarded through
#     ddio_out1 from tx_pll c1 (90 deg).
#   * PHY_RX_CLOCK is asynchronous to the tx PLL (was grouped with PHY_CLK125).
#   * Ethernet set_max_delay relaxations removed (see ETH_LEGACY_RELAX).
# The ADC/DAC/audio part is unchanged from 1.5 (marked LEGACY below).

set_time_format -unit ns -decimal_places 3

#**************************************************************
# Base clocks
#**************************************************************
create_clock -name INA_CLK      -period 8.138 [get_ports {INA_CLK}]
# CLKOUT+ of ADC2: captures ADC2 (rising edge, I/O register)
create_clock -name INA_CLK_2    -period 8.138 [get_ports {INA_CLK_2}]
create_clock -name _122MHz_in   -period 8.138 [get_ports {_122MHz_in}]
create_clock -name {_122MHz_out} -period 8.138 -waveform { 0.000 4.069 } [get_ports {_122MHz_out}]
create_clock -name OSC_10MHZ    -period 100.000 [get_ports {OSC_10MHZ}]
create_clock -name PHY_CLK125   -period 8.000 [get_ports {PHY_CLK125}]
create_clock -name PHY_RX_CLOCK -period 8.000 [get_ports {PHY_RX_CLOCK}]
create_clock -name rx_virt      -period 8.000
create_clock -name virt_CBCLK   -period 325.520 -waveform { 0.000 162.760 }

derive_pll_clocks
derive_clock_uncertainty

set eth_c0  {network_inst|rgmii_send_inst|tx_pll_inst|altpll_component|auto_generated|pll1|clk[0]}
set eth_c1  {network_inst|rgmii_send_inst|tx_pll_inst|altpll_component|auto_generated|pll1|clk[1]}
set eth_c2  {network_inst|rgmii_send_inst|tx_pll_inst|altpll_component|auto_generated|pll1|clk[2]}

set CMCLK  PLL_IF_inst|altpll_component|auto_generated|pll1|clk[0]
set CBCLK  PLL_IF_inst|altpll_component|auto_generated|pll1|clk[1]
set CLRCLK PLL_IF_inst|altpll_component|auto_generated|pll1|clk[2]

# GTX_CLK as seen on the PHY_TX_CLOCK pin
create_generated_clock -name gtx_clk_out \
    -source [get_pins {network_inst|rgmii_send_inst|tx_pll_inst|altpll_component|auto_generated|pll1|clk[1]}] \
    [get_ports {PHY_TX_CLOCK}]

# PLL generated clocks feeding output pins (codec)
create_generated_clock -name CBCLK   -source $CBCLK  [get_ports CBCLK]
create_generated_clock -name CMCLK   -source $CMCLK  [get_ports CMCLK]
create_generated_clock -name CLRCIN  -source $CLRCLK [get_ports CLRCIN]
create_generated_clock -name CLRCOUT -source $CLRCLK [get_ports CLRCOUT]

#**************************************************************
# Clock groups
#**************************************************************
set c122_c0 {PLL_inst|altpll_component|auto_generated|pll1|clk[0]}
set c122_c1 {PLL_inst|altpll_component|auto_generated|pll1|clk[1]}

# 2026-10: PLL_inst (C122_clk, osc_80khz) is generated from INA_CLK and is in
# the SAME group as INA_CLK and INA_CLK_2 (both converters run from the same
# encode clock). Before, it was in a group of its own, so the ADC data transfer
# into the C122_clk domain was never analysed.
set_clock_groups -asynchronous \
    -group [get_clocks [list INA_CLK INA_CLK_2 $c122_c0 $c122_c1 _122MHz_in _122MHz_out CBCLK CMCLK CLRCIN CLRCOUT]] \
    -group [get_clocks [list PHY_CLK125 $eth_c0 $eth_c1 $eth_c2 gtx_clk_out]] \
    -group { PHY_RX_CLOCK rx_virt } \
    -group { PLL_IF_inst|altpll_component|auto_generated|pll1|clk[0] PLL_IF_inst|altpll_component|auto_generated|pll1|clk[1] PLL_IF_inst|altpll_component|auto_generated|pll1|clk[2] } \
    -group { OSC_10MHZ PLL2_inst|altpll_component|auto_generated|pll1|clk[0] }

# keep the legacy cuts: C122 PLL <-> DAC / codec clocks, osc_80khz <-> ADC clocks
set_clock_groups -asynchronous \
    -group [get_clocks [list $c122_c0 $c122_c1]] \
    -group [get_clocks {_122MHz_in _122MHz_out CBCLK CMCLK CLRCIN CLRCOUT}]
set_clock_groups -asynchronous \
    -group [get_clocks $c122_c1] \
    -group [get_clocks {INA_CLK INA_CLK_2}]

#**************************************************************
# ADC (LTC2165, full-rate CMOS) -> FPGA
#**************************************************************
# LTC2165 full-rate CMOS: the data changes with the FALLING edge of CLKOUT+
# (tSKEW = tD - tC = 0 .. 0.6 ns), the rising edge is in the middle of the
# eye. Each converter is captured by its own CLKOUT+ (INA_CLK, INA_CLK_2),
# rising edge, in the I/O-cell input register. The data is therefore
# launched by the falling edge: -clock_fall input delays.
# TimeQuest then checks: setup  fall -> next rise (4.069 ns),
#                        hold   next fall -> rise (-4.069 ns), incl. the
#                        global clock network delay. Board: +-0.2 ns.
set adc_board 0.2
set_input_delay -clock INA_CLK   -clock_fall -max [expr 0.6 + $adc_board] [get_ports {INA[*]}]
set_input_delay -clock INA_CLK   -clock_fall -min [expr 0.0 - $adc_board] [get_ports {INA[*]}]
set_input_delay -clock INA_CLK_2 -clock_fall -max [expr 0.6 + $adc_board] [get_ports {INA_2[*]}]
set_input_delay -clock INA_CLK_2 -clock_fall -min [expr 0.0 - $adc_board] [get_ports {INA_2[*]}]

# adc1_ioe / adc2_ioe -> adc1_c122 / adc2_c122 on the FALLING edge of C122_clk
# (INA_CLK + 6.10 ns): default analysis (setup to the next falling edge, hold
# to the previous one), no multicycle. The CLKOUT of ADC2 may differ from ADC1
# by the part-to-part spread of tC (1.0..2.6 ns) plus board: +-1.0 ns.
set_clock_uncertainty -from [get_clocks INA_CLK_2] -to [get_clocks $c122_c0] -add 1.0

# temp_DACD (DAC loop-back for the RX, on INA_CLK) -> C122_clk (+2.035 ns):
# taken by the C122 edge of the next period, must not reach the +2.035 edge.
set_multicycle_path -setup -end 2 -from [get_registers {temp_DACD*}] -to [get_clocks $c122_c0]

#**************************************************************
# C122_clk (122.88 MHz) DSP domain
#**************************************************************
# 1.5 relaxed the whole domain to 12 ns (set_max_delay 12). The paths that need
# it start at the cdc_mcp outputs (sample rate, frequency words ...), which are
# quasi-static: they are given 2 cycles. Everything else is now checked at
# 8.138 ns. If the compile fails in clk[0] paths that do NOT start at cdc_mcp,
# set C122_LEGACY_RELAX to 1 and send the report.
set C122_LEGACY_RELAX 0
# cdc_mcp outputs change only when the PC sends a new setting (sample rate,
# frequency, ADC selection ...); the sample rate goes through the rate decode
# and the CIC rounding mux into the 73-bit adder (~17 ns) -> 4 clocks.
set_multicycle_path -setup -end 4 -from [get_registers {*cdc_mcp*b_data*}] -to [get_clocks $c122_c0]
set_multicycle_path -hold  -end 3 -from [get_registers {*cdc_mcp*b_data*}] -to [get_clocks $c122_c0]
# Receiver CICs (cic.v, receiver2.v):
#  cic_inst_I2/Q2: integrators every clock (single-cycle, not covered); combs
#    and output rounding only on out_strobe = decimA_avail (every >= 5 clocks).
#  varcic_inst_I1/Q1 (11 stages, 73-bit): integrators on in_strobe =
#    decimA_avail (every >= 5 clocks); combs + FIR input on out_strobe
#    (every >= 40 clocks).
# Covered with 4 clocks, because source AND destination only move on strobes
# that are >= 5 clocks apart:
#   integrator -> integrator inside varcic
#   comb / comb_last -> anything (own combs, next CIC integrator, FIR RAM)
# NOT covered (single-cycle!): last integrator -> first comb. out_strobe is
# set on the same edge as the integrators update, the combs read the last
# integrator one clock later.
set varcic_int [get_registers {*varcic_inst_*|integrator_data*}]
set cic_comb   [get_registers {*receiver*cic_inst_*|comb_data* *receiver*cic_inst_*|comb_last*}]
set_multicycle_path -setup -end 4 -from $varcic_int -to $varcic_int
set_multicycle_path -hold  -end 3 -from $varcic_int -to $varcic_int
set_multicycle_path -setup -end 4 -from $cic_comb -to [get_clocks $c122_c0]
set_multicycle_path -hold  -end 3 -from $cic_comb -to [get_clocks $c122_c0]
if {$C122_LEGACY_RELAX} {
  set_max_delay -from [get_clocks $c122_c0] -to [get_clocks $c122_c0] 12
}

#**************************************************************
# RGMII receive (KSZ9031 -> FPGA): data centred by the PHY (RGMII-ID)
#**************************************************************
# KSZ9031 table 7-1: TsetupT/TholdT >= 1.2 ns at the PHY pins; the 1.2 ns
# RX_CLK delay is typical only, so setup is taken as 1.0 ns.
set rgmii_rx_tsu   1.0
set rgmii_rx_th    1.2
set rgmii_rx_board 0.1
set rx_max [expr 4.0 - $rgmii_rx_tsu + $rgmii_rx_board]
set rx_min [expr $rgmii_rx_th - $rgmii_rx_board]
set rx_ports [get_ports {PHY_RX[*] PHY_RX_DV}]
set_input_delay -clock rx_virt -max $rx_max $rx_ports
set_input_delay -clock rx_virt -min $rx_min $rx_ports
set_input_delay -clock rx_virt -max $rx_max $rx_ports -clock_fall -add_delay
set_input_delay -clock rx_virt -min $rx_min $rx_ports -clock_fall -add_delay
# setup on the opposite edge, hold on the same edge
set_false_path -setup -rise_from [get_clocks rx_virt] -rise_to [get_clocks PHY_RX_CLOCK]
set_false_path -setup -fall_from [get_clocks rx_virt] -fall_to [get_clocks PHY_RX_CLOCK]
set_false_path -hold  -rise_from [get_clocks rx_virt] -fall_to [get_clocks PHY_RX_CLOCK]
set_false_path -hold  -fall_from [get_clocks rx_virt] -rise_to [get_clocks PHY_RX_CLOCK]

#**************************************************************
# RGMII transmit (FPGA -> KSZ9031): clock centred by the FPGA (c1 = 90 deg)
#**************************************************************
# KSZ9031 table 7-1 (receiver): TsetupR >= 1.0 ns, TholdR >= 1.0 ns
set rgmii_tx_tsu   1.0
set rgmii_tx_th    1.0
set rgmii_tx_board 0.1
set tx_ports [get_ports {PHY_TX[*] PHY_TX_EN}]
set_output_delay -clock gtx_clk_out -max [expr  $rgmii_tx_tsu + $rgmii_tx_board] $tx_ports
set_output_delay -clock gtx_clk_out -min [expr -$rgmii_tx_th  - $rgmii_tx_board] $tx_ports
set_output_delay -clock gtx_clk_out -max [expr  $rgmii_tx_tsu + $rgmii_tx_board] $tx_ports -clock_fall -add_delay
set_output_delay -clock gtx_clk_out -min [expr -$rgmii_tx_th  - $rgmii_tx_board] $tx_ports -clock_fall -add_delay
# setup on the same edge (+2 ns), hold on the opposite edge
set_false_path -setup -rise_from [get_clocks $eth_c0] -fall_to [get_clocks gtx_clk_out]
set_false_path -setup -fall_from [get_clocks $eth_c0] -rise_to [get_clocks gtx_clk_out]
set_false_path -hold  -rise_from [get_clocks $eth_c0] -rise_to [get_clocks gtx_clk_out]
set_false_path -hold  -fall_from [get_clocks $eth_c0] -fall_to [get_clocks gtx_clk_out]
set_false_path -to [get_ports {PHY_TX_CLOCK}]

#**************************************************************
# Ethernet internal timing
#**************************************************************
# 1.5 relaxed the 125 MHz domains to 14..16 ns. They are now analysed at
# 8 ns. If the compile shows negative slack in rx_clock / tx_clock paths of
# the SDR C&C logic, set this to 1 temporarily and send the report, the
# failing paths will be pipelined.
set ETH_LEGACY_RELAX 0
if {$ETH_LEGACY_RELAX} {
  set_max_delay -from [get_clocks PHY_RX_CLOCK] -to [get_clocks PHY_RX_CLOCK] 14
  set_max_delay -from [get_clocks $eth_c0] -to [get_clocks $eth_c0] 16
  set_max_delay -from [get_clocks $eth_c2] -to [get_clocks $eth_c0] 15
}

#**************************************************************
# LEGACY (unchanged from 1.5): ADC / DAC / codec
#**************************************************************

#TLV320 Data in +/- 20nS setup and hold
set_input_delay  20  -clock virt_CBCLK  {CDOUT} -add_delay
#TLV320 Data out
set_output_delay  10 -clock $CBCLK {CDIN CMODE} -add_delay
#122.88MHz clock for Tx DAC
set_output_delay 0.8 -clock _122MHz_out {DACD[*]} -add_delay

set_max_delay -from _122MHz_in -to _122MHz_out 9
set_min_delay -from PLL_IF_inst|altpll_component|auto_generated|pll1|clk[2] -to PLL_IF_inst|altpll_component|auto_generated|pll1|clk[1] -1

#**************************************************************
# Slow / asynchronous I/O
#**************************************************************
set_false_path -to [get_ports {UO[*] PHY_MDC ANT[*] TUNE PTT_out u_tx led1 led2 led3 led4 test1 test2 PHY_RESET_N PHY_MDIO ATTN_CLK ATTN_DATA \
                    ATTN_LE ATTN_LE_2 BAND[*] CMCLK CBCLK CLRCIN CLRCOUT CCS_N CMOSI CSCK FPGA_PLL LNA PTT_out_mcu DAC_ALC NCONFIG }]
set_false_path -from [get_ports {KEY_DASH KEY_DOT PTT_in_UO PTT_in u_rx PHY_MDIO OVERFLOW OVERFLOW_2}]
