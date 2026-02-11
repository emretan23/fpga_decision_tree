# =============================================================================
# Vivado XSim Simulation Script
# =============================================================================
# Usage:
#   vivado -mode batch -source vivado/scripts/xsim.tcl
#
# Compiles and runs the SystemVerilog testbench in XSim.
# Generates a WDB waveform database for viewing in Vivado waveform viewer.
# =============================================================================

# ---- Configuration ----
set RTL_DIR     "rtl"
set TB_DIR      "tb"
set OUT_DIR     "vivado/output/xsim"
set TOP_TB      "decision_tree_tb"

# ---- Setup output directory ----
file mkdir $OUT_DIR

# ---- Compile sources ----
puts "=== Compiling design for XSim ==="
exec xvlog -sv \
    $RTL_DIR/decision_tree.sv \
    $TB_DIR/decision_tree_tb.sv \
    --work work \
    --log $OUT_DIR/xvlog.log

# ---- Elaborate ----
puts "=== Elaborating ==="
exec xelab work.$TOP_TB \
    -s sim_snapshot \
    -timescale 1ns/1ps \
    -debug typical \
    --log $OUT_DIR/xelab.log

# ---- Run simulation ----
puts "=== Running simulation ==="
exec xsim sim_snapshot \
    -runall \
    -wdb $OUT_DIR/sim.wdb \
    --log $OUT_DIR/xsim.log

puts ""
puts "=== XSim simulation complete ==="
puts "  Waveform: $OUT_DIR/sim.wdb"
puts "  Logs:     $OUT_DIR/x*.log"
puts ""
puts "To view waveforms:"
puts "  vivado -source vivado/scripts/xsim.tcl  (then open $OUT_DIR/sim.wdb)"
puts "  Or: open Vivado GUI → File → Open Waveform Database"
