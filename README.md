# FPGA Decision Tree Inference Engine

Hardware-accelerated binary decision tree for low-latency trading signal classification. An 8-bit market signal is classified into a 2-bit trading action (NONE / BUY / SELL / CANCEL) by traversing a software-configurable decision tree in FPGA fabric.

Two implementations are provided with identical interfaces:

| Design | File | Traversal | Latency | Throughput |
|--------|------|-----------|---------|------------|
| **Original (FSM)** | `rtl/decision_tree.sv` | Linked-list walk | depth cycles | 1 result / (depth+1) cycles |
| **Pipelined** | `rtl/decision_tree_pipelined.sv` | Pipeline stages | MAX_DEPTH + 2 cycles (fixed) | **1 result / cycle** |

The original is faster for single shallow queries. The pipeline wins on sustained throughput.

## Architecture

### Original — FSM / Linked-List Traversal

1. **Pre-computation:** A combinational block evaluates all 64 nodes in parallel against `market_input`, building a "next pointer" table (`path[]`). The table is captured once on the `start` pulse and frozen for the traversal.
2. **Traversal:** An FSM walks `path[]` one hop per clock cycle — `current = path[current]` — until a leaf is found via combinational read of `tree_mem`.

This collapses the tree into a singly linked list for each input. Simple but sequential.

> **Timing note:** The leaf detection uses a combinational read that cascades two LUTRAM lookups in a single cycle. At high clock speeds (>300 MHz), this may require switching to a registered `node_reg` approach (+1 cycle latency but shorter critical path). See the comment in `rtl/decision_tree.sv` for details.

### Pipelined

A `generate` loop unrolls the tree into one pipeline stage per level. Each stage reads one node, evaluates the threshold, and passes the child index forward. `market_input` is captured once and frozen for the traversal.

After the pipeline fills, one new result emerges every clock cycle.

## Tree Node Format

```systemverilog
typedef struct packed {
    logic        is_leaf;      // 1 = leaf node
    logic [7:0]  threshold;    // comparison value
    logic        less_than;    // 1 = use '<', 0 = use '>'
    logic [5:0]  left_idx;     // left child index
    logic [5:0]  right_idx;    // right child index
    logic [1:0]  action;       // leaf action (00=NONE, 01=BUY, 10=SELL, 11=CANCEL)
} node_t;
```

Trees are loaded at runtime via a software write interface (`sw_we`, `sw_addr`, `sw_data_*`). Max 64 nodes.

## Building and Testing

Requires [Verilator](https://verilator.org/) (tested with v5.036).

```bash
# Run all tests (both designs, 256 exhaustive inputs each, golden model verification)
make test

# Run individually
make test-orig      # Original FSM design
make test-pipe      # Pipelined design

# SystemVerilog testbenches (standalone, no C++)
make tb             # Original
make tb-pipe        # Pipelined

# Lint
make lint           # Original
make lint-pipe      # Pipelined

# Clean build artifacts
make clean
```

### Test output

Results are written to `results_original.txt` and `results_pipelined.txt` with:
- 12 spot-check tests at various tree depths
- Throughput measurement (back-to-back queries)
- Exhaustive verification of all 256 inputs against a C++ golden model (`simulate_tree()`)

VCD waveforms are generated at `test_original.vcd` and `test_pipelined.vcd` for inspection with [Surfer](https://surfer-project.org/) or GTKWave.

## Vivado Flow (Arty A7-35T)

TCL scripts for Xilinx Vivado targeting the Digilent Arty A7-35T. No Vivado project file needed — everything runs in non-project batch mode.

```bash
# Synthesis only (timing analysis, no board)
vivado -mode batch -source vivado/scripts/synth.tcl

# Full implementation → bitstream
vivado -mode batch -source vivado/scripts/impl.tcl

# Program the board
vivado -mode batch -source vivado/scripts/program.tcl
```

See [`vivado/README.md`](vivado/README.md) for full details, board mapping, and how to adapt to other FPGAs.

## Project Structure

```
rtl/
  decision_tree.sv               # Original FSM-based design
  decision_tree_pipelined.sv     # Pipelined alternative
tb/
  decision_tree_tb.sv            # SV testbench (original)
  decision_tree_pipelined_tb.sv  # SV testbench (pipelined)
sim/
  test_original.cpp              # C++ test harness + golden model (original)
  test_pipelined.cpp             # C++ test harness + golden model (pipelined)
vivado/
  constraints/
    timing.xdc                   # Timing-only (synthesis analysis)
    arty_a7_35t.xdc              # Pin mapping for Arty A7-35T
  scripts/
    synth.tcl                    # Synthesis flow
    impl.tcl                     # Place & route + bitstream
    xsim.tcl                     # XSim simulation
    program.tcl                  # JTAG programming
  src/
    top_arty.sv                  # Board wrapper for Arty A7-35T
doc/
  INTERVIEW_QUESTION.md          # Interview question derived from this project
  INTERVIEW_SOLUTION.md          # Solution guide with rubric
Makefile                         # Verilator build targets
README.md
LICENSE
```

## Interview Materials

The `doc/` folder contains an interview question and solution derived from this project:

- `INTERVIEW_QUESTION.md` — 3-part question (tree tracing, RTL analysis, design critique)
- `INTERVIEW_SOLUTION.md` — full solutions with evaluation rubric

Topics covered: FSM timing analysis, linked-list traversal in hardware, latency vs fmax trade-offs, pipelining, and mid-traversal input stability.

## License

MIT
