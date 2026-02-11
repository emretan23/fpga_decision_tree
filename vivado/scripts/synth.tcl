# =============================================================================
# Vivado Synthesis Script (Non-Project Mode)
# =============================================================================
# Usage:
#   vivado -mode batch -source vivado/scripts/synth.tcl
#
# Synthesises the decision_tree module standalone (no board wrapper) with
# timing constraints for analysis. Use impl.tcl for full place & route.
# =============================================================================

# ---- Configuration ----
set PART        "xc7a35ticsg324-1L"
set TOP         "decision_tree"
set RTL_DIR     "rtl"
set XDC_DIR     "vivado/constraints"
set OUT_DIR     "vivado/output/synth"

# ---- Setup output directory ----
file mkdir $OUT_DIR

# ---- Read sources ----
puts "=== Reading design sources ==="
read_verilog -sv $RTL_DIR/decision_tree.sv

# ---- Read timing constraints ----
read_xdc $XDC_DIR/timing.xdc

# ---- Synthesise ----
puts "=== Running synthesis ==="
synth_design -top $TOP -part $PART -flatten_hierarchy rebuilt

# ---- Reports ----
puts "=== Generating synthesis reports ==="
report_timing_summary -file $OUT_DIR/timing_summary.rpt
report_utilization     -file $OUT_DIR/utilization.rpt
report_clocks          -file $OUT_DIR/clocks.rpt
report_timing -max_paths 10 -sort_by slack -file $OUT_DIR/timing_paths.rpt

# ---- Write checkpoint ----
write_checkpoint -force $OUT_DIR/post_synth.dcp

puts "=== Synthesis complete ==="
puts "  Reports:    $OUT_DIR/*.rpt"
puts "  Checkpoint: $OUT_DIR/post_synth.dcp"
