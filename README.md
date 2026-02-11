# FPGA Decision Tree Inference Engine

Hardware-accelerated binary decision tree for low-latency trading signal classification. An 8-bit market signal is classified into a 2-bit trading action (NONE / BUY / SELL / CANCEL) by traversing a software-configurable decision tree in FPGA fabric.

Two implementations are provided with identical interfaces:

| Design | File | Traversal | Latency | Throughput |
|--------|------|-----------|---------|------------|
| **Original (FSM)** | `decision_tree.sv` | Linked-list walk | depth + 1 cycles | 1 result / (depth+2) cycles |
| **Pipelined** | `decision_tree_pipelined.sv` | Pipeline stages | MAX_DEPTH + 2 cycles (fixed) | **1 result / cycle** |

## Architecture

### Original — FSM / Linked-List Traversal

1. **Pre-computation:** A combinational block evaluates all 64 nodes in parallel against `market_input`, building a "next pointer" table (`path[]`).
2. **Traversal:** An FSM walks `path[]` one hop per clock cycle — `current = path[current]` — until a leaf is found.

This collapses the tree into a singly linked list for each input. Simple but sequential.

### Pipelined

A `generate` loop unrolls the tree into one pipeline stage per level. Each stage reads one node, evaluates the threshold, and passes the child index forward. `market_input` is captured once and frozen for the traversal — no mid-traversal corruption.

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

## Project Structure

```
decision_tree.sv                 # Original FSM-based design
decision_tree_pipelined.sv       # Pipelined alternative
decision_tree_tb.sv              # SV testbench (original)
decision_tree_pipelined_tb.sv    # SV testbench (pipelined)
test_original.cpp                # C++ test harness + golden model (original)
test_pipelined.cpp               # C++ test harness + golden model (pipelined)
Makefile                         # Build targets
INTERVIEW_QUESTION.md            # Interview question derived from this project
INTERVIEW_SOLUTION.md            # Solution guide with rubric
```

## Interview Materials

The project includes an interview question (`INTERVIEW_QUESTION.md`) and solution (`INTERVIEW_SOLUTION.md`) that use this codebase. The question covers:

1. Tree tracing (warm-up)
2. RTL analysis — identifying the linked-list traversal pattern and a registered pipeline delay
3. Design critique — area/power trade-offs, pipelining, and a subtle mid-traversal bug

## License

MIT
