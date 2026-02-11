# =============================================================================
# Vivado Implementation Script (Non-Project Mode)
# =============================================================================
# Usage:
#   vivado -mode batch -source vivado/scripts/impl.tcl
#
# Full flow: synthesis → opt → place → phys_opt → route → bitstream
# Targets the Arty A7-35T with board wrapper (top_arty).
# =============================================================================

# ---- Configuration ----
set PART        "xc7a35ticsg324-1L"
set TOP         "top_arty"
set RTL_DIR     "rtl"
set VIVADO_SRC  "vivado/src"
set XDC_DIR     "vivado/constraints"
set OUT_DIR     "vivado/output/impl"

# ---- Setup output directory ----
file mkdir $OUT_DIR

# ---- Read sources ----
puts "=== Reading design sources ==="
read_verilog -sv $RTL_DIR/decision_tree.sv
read_verilog -sv $VIVADO_SRC/top_arty.sv

# ---- Read constraints ----
read_xdc $XDC_DIR/arty_a7_35t.xdc

# ---- Synthesise ----
puts "=== Running synthesis ==="
synth_design -top $TOP -part $PART -flatten_hierarchy rebuilt

report_timing_summary -file $OUT_DIR/post_synth_timing.rpt
report_utilization     -file $OUT_DIR/post_synth_util.rpt
write_checkpoint -force $OUT_DIR/post_synth.dcp

# ---- Optimise ----
puts "=== Running optimisation ==="
opt_design

# ---- Place ----
puts "=== Running placement ==="
place_design
report_clock_utilization -file $OUT_DIR/clock_util.rpt
write_checkpoint -force $OUT_DIR/post_place.dcp

# ---- Physical optimisation ----
puts "=== Running physical optimisation ==="
phys_opt_design

# ---- Route ----
puts "=== Running routing ==="
route_design
write_checkpoint -force $OUT_DIR/post_route.dcp

# ---- Post-route reports ----
puts "=== Generating implementation reports ==="
report_timing_summary -file $OUT_DIR/post_route_timing.rpt
report_timing -max_paths 20 -sort_by slack -file $OUT_DIR/post_route_paths.rpt
report_utilization     -file $OUT_DIR/post_route_util.rpt
report_power           -file $OUT_DIR/power.rpt
report_drc             -file $OUT_DIR/drc.rpt
report_methodology     -file $OUT_DIR/methodology.rpt

# ---- Generate bitstream ----
puts "=== Generating bitstream ==="
write_bitstream -force $OUT_DIR/top_arty.bit

puts ""
puts "=== Implementation complete ==="
puts "  Bitstream:  $OUT_DIR/top_arty.bit"
puts "  Reports:    $OUT_DIR/*.rpt"
puts "  Checkpoint: $OUT_DIR/post_route.dcp"
