# =============================================================================
# Timing-only constraints — use for synthesis analysis without board pinout
# =============================================================================
# Target: any Artix-7 at 100 MHz. No pin assignments.
# Use this with: synth_design -top decision_tree (module-level synthesis)

create_clock -period 10.000 -name sys_clk -waveform {0.000 5.000} [get_ports clk]

# Input delay: assume inputs arrive 2ns after clock edge
set_input_delay -clock sys_clk 2.000 [get_ports -filter {DIRECTION == IN && NAME != "clk"}]

# Output delay: assume outputs needed 2ns before next clock edge
set_output_delay -clock sys_clk 2.000 [get_ports -filter {DIRECTION == OUT}]
