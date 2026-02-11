# Vivado Flow

Non-project mode TCL scripts for Xilinx Vivado targeting the **Digilent Arty A7-35T** (XC7A35TICSG324-1L).

## Quick Start

All commands are run from the **repository root** (not this directory).

```bash
# Synthesis only (decision_tree module, timing analysis)
vivado -mode batch -source vivado/scripts/synth.tcl

# Full implementation (synthesis → place → route → bitstream)
vivado -mode batch -source vivado/scripts/impl.tcl

# XSim simulation
vivado -mode batch -source vivado/scripts/xsim.tcl

# Program the board (after implementation)
vivado -mode batch -source vivado/scripts/program.tcl
```

## Scripts

| Script | What it does |
|--------|-------------|
| `synth.tcl` | Synthesises `decision_tree` standalone with timing constraints. Good for checking utilisation and timing without board pinout. |
| `impl.tcl` | Full flow with `top_arty` board wrapper: synth → opt → place → phys_opt → route → bitstream. Generates all reports. |
| `xsim.tcl` | Compiles and runs the SV testbench in Xilinx XSim. Outputs `.wdb` waveform. |
| `program.tcl` | Programs the Arty A7-35T via JTAG/USB. |

## Constraints

| File | Use |
|------|-----|
| `timing.xdc` | Clock + I/O delay constraints only. For synthesis analysis on any Artix-7 without pin assignments. |
| `arty_a7_35t.xdc` | Full pin mapping for the Arty A7-35T board. Used by `impl.tcl`. |

## Board Mapping (Arty A7-35T)

| Board Resource | Signal | Direction |
|---------------|--------|-----------|
| 100 MHz clock (E3) | `CLK100MHZ` | Input |
| BTN0 | Reset | Input |
| BTN1 | Start traversal | Input |
| SW[3:0] | `market_input[3:0]` | Input |
| Pmod JA[3:0] | `market_input[7:4]` | Input |
| Pmod JB | Software write control | Input |
| Pmod JC | `sw_data_threshold[7:0]` | Input |
| Pmod JD | `sw_data_left/right_idx` | Input |
| LED[0:1] | `action[1:0]` | Output |
| LED[2] | `action_valid` | Output |
| LED[3] | Heartbeat (1 Hz) | Output |

## Output Directory

All outputs go to `vivado/output/`:

```
vivado/output/
  synth/
    post_synth.dcp          # Synthesis checkpoint
    timing_summary.rpt      # Timing analysis
    utilization.rpt         # Resource usage
    timing_paths.rpt        # Critical paths
    clocks.rpt
  impl/
    post_synth.dcp          # Post-synthesis checkpoint
    post_place.dcp          # Post-placement checkpoint
    post_route.dcp          # Post-route checkpoint
    top_arty.bit            # Bitstream
    post_route_timing.rpt   # Final timing
    post_route_util.rpt     # Final utilisation
    post_route_paths.rpt    # Critical paths
    power.rpt               # Power estimate
    drc.rpt                 # Design rule checks
    methodology.rpt
  xsim/
    sim.wdb                 # Waveform database
    x*.log                  # Compilation/sim logs
```

## Adapting to Other Boards

1. Copy `arty_a7_35t.xdc` and modify pin assignments for your board
2. Update `PART` in `synth.tcl` / `impl.tcl` (e.g., `xc7a100tcsg324-1` for Arty A7-100T)
3. Modify `top_arty.sv` I/O mapping if your board has different peripherals
4. For synthesis-only analysis, `synth.tcl` with `timing.xdc` works on any Artix-7 — just change `PART`
