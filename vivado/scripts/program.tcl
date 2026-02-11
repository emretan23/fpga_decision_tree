# =============================================================================
# Vivado Programming Script
# =============================================================================
# Usage:
#   vivado -mode batch -source vivado/scripts/program.tcl
#
# Programs the Arty A7-35T with the generated bitstream.
# Requires the board to be connected via USB.
# =============================================================================

set BIT_FILE "vivado/output/impl/top_arty.bit"

puts "=== Opening hardware manager ==="
open_hw_manager
connect_hw_server -allow_non_jtag

puts "=== Searching for hardware target ==="
open_hw_target

set device [get_hw_devices xc7a35t_0]
current_hw_device $device
refresh_hw_device -update_hw_probes false $device

puts "=== Programming device ==="
set_property PROGRAM.FILE $BIT_FILE $device
program_hw_devices $device

puts ""
puts "=== Programming complete ==="
puts "  Device programmed with: $BIT_FILE"

close_hw_target
disconnect_hw_server
close_hw_manager
