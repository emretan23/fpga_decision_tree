# FPGA Decision Tree Inference Engine — Solution Guide

---

## Part 1 — Warm-up: Trace the Tree

**Q1a: `market_input = 5`**

- Node 0: 5 < 20? **Yes** → go left to Node 1
- Node 1: 5 < 10? **Yes** → go left to Node 3
- Node 3: leaf → **BUY** (`01`)

**Q1b: `market_input = 15`**

- Node 0: 15 < 20? **Yes** → go left to Node 1
- Node 1: 15 < 10? **No** → go right to Node 4
- Node 4: leaf → **SELL** (`10`)

**Q1c: `market_input = 25`**

- Node 0: 25 < 20? **No** → go right to Node 2
- Node 2: leaf → **CANCEL** (`11`)

---

## Part 2 — RTL Analysis

### Q2a: What does `path[]` represent?

`path[j]` holds the index of the **next node** you would visit from node `j`, given the
current `market_input`. For each internal node, the pre-computation resolves the
threshold comparison and stores either `left_idx` or `right_idx`. For leaf nodes the
value is meaningless (but computed anyway).

In effect, `path[]` is a **"next pointer" table** for the entire tree, specialized for
one particular input value.

### Q2b: What data structure does the traversal resemble?

A **singly linked list**.

The FSM follows the pattern:

```
current_path_index = 0;               // start at root
path_index = path[current_path_index]; // follow the pointer
current_path_index = path_index;       // advance
// repeat...
```

This is `current = next[current]` — textbook linked list traversal. Even though the
underlying data is a binary tree, the pre-computation collapses it into a single chain
for a given input. Only one branch is ever taken at each node, so the tree degenerates
into a list.

### Q2c: Timing consequence of `node_reg` in `always_ff`

In a synchronous `always_ff` block, all right-hand side values are read **before** the
clock edge (pre-edge values). The non-blocking assignment `node_reg <= tree_mem[path_index]`
schedules the update for **after** the edge.

Therefore, when `if (node_reg.is_leaf)` executes, it sees the **previous cycle's** value
of `node_reg`, NOT the value being loaded in the same statement. The FSM is always
checking node N-1's leaf status while loading node N.

This creates a **one-cycle pipeline delay**: the traversal needs one extra cycle beyond
the tree depth because the leaf detection lags behind the node loading by one cycle.

### Q2d: Cycle-by-cycle trace for `market_input = 5`

Pre-computed `path[]` values (from the `always_comb` block):
- `path[0] = 1` (5 < 20, go left)
- `path[1] = 3` (5 < 10, go left)
- `path[3] = 0` (leaf, computed_path is meaningless but resolves to some value)

Trace:

| Cycle | Event | `current_path_index` | `path_index` | `node_reg` loaded this edge | `is_leaf` checked (old `node_reg`) | Result |
|-------|-------|---------------------|-------------|---------------------------|-----------------------------------|-|
| 0 | `start=1` | <= 0 | -- | -- | -- | FSM arms |
| 1 | FSM active | 0 | `path[0]`=1 | `tree_mem[1]` (Node 1) | old value (init/zero, not leaf) | `current_path_index <= 1` |
| 2 | follow ptr | 1 | `path[1]`=3 | `tree_mem[3]` (Node 3, BUY) | Node 1 → not leaf | `current_path_index <= 3` |
| 3 | follow ptr | 3 | `path[3]`=? | `tree_mem[?]` | **Node 3 → is_leaf!** | `action <= BUY`, `action_valid <= 1` |

**Total: 3 cycles** from `start` to `action_valid`.

General formula: **latency = tree_depth + 1** clock cycles (the +1 from the registered
pipeline delay on `node_reg`).

---

## Part 3 — Design Critique and Optimization

### Q3a: Cost of parallel pre-computation

The `always_comb` block synthesizes **64 parallel comparators** (8-bit compare) and
**64 multiplexers** (selecting left vs right index). For a tree that only uses ~6 nodes
on any given path, roughly 90% of this hardware is wasted.

**Area cost:** 64 comparators + 64 muxes worth of LUTs. Not catastrophic, but
unnecessary.

**Power cost:** All 64 comparators toggle on every `market_input` change, burning
dynamic power for no useful work. In a low-power or thermally constrained FPGA design,
this matters.

**Timing cost:** None — the computation is combinational and happens in parallel. It
doesn't add cycles to the traversal. However, it does contribute to combinational delay
(all 64 comparators fan out from `market_input`), which could affect fmax if the
`tree_mem` read and comparison chain is on the critical path.

The computation is "free" in terms of latency but NOT free in area and power.

### Q3b: Single-cycle design

**Approach:** Chain the comparisons combinationally across tree levels. No FSM, no
state machine — pure combinational logic from input to output.

```
Level 0: Read root (tree_mem[0]), compare, select child index
Level 1: Read tree_mem[child_0], compare, select child index
Level 2: Read tree_mem[child_1], compare, select child index
...
Level D: Read tree_mem[child_D-1], output action if leaf
```

Each level is a cascaded MUX + comparator. The output is the action from whichever
level first encounters a leaf (or the deepest level).

**Trade-off:**

- **Pro:** 1-cycle latency, no state machine, simple control.
- **Con:** The critical path is `D × (memory_read + comparator + mux)`. For a 6-level
  tree, this cascades 6 memory lookups and 6 comparisons in series. This will
  **significantly reduce fmax** — potentially by 3-6x depending on the FPGA fabric.
- **Con:** The design is parameterized by MAX_DEPTH, not MAX_NODES. Deeper trees require
  more combinational stages, and the critical path grows linearly.

This approach is viable for shallow trees (depth 3-4) at moderate clock speeds.

### Q3c: Pipelined design (1 result/cycle throughput)

**Approach:** Create a **pipeline with one stage per tree level**. Each stage contains:
1. A registered node read
2. A comparator
3. A mux to select the next child index
4. Pipeline registers carrying the data forward

```
Stage 0: root compare → child index → register
Stage 1: level-1 compare → child index → register
...
Stage D-1: leaf check → action output
```

A new `market_input` enters Stage 0 every clock cycle. After the pipeline fills
(D cycles), one result emerges per cycle.

**Characteristics:**
- **Throughput:** 1 result per clock cycle (after pipeline latency)
- **Latency:** D cycles (same as original, but without the +1 bug)
- **Fmax:** High — each stage is only one comparator + mux deep
- **Area:** D sets of comparators + muxes + pipeline registers. Comparable to the
  original design's 64 parallel comparators for typical tree sizes.

**This is the recommended approach for a high-throughput low-latency trading system.**

See `decision_tree_pipelined.sv` for a complete implementation.

### Q3d (Bonus): `market_input` changing mid-traversal

**This is a bug.**

The `path[]` array is recomputed from `market_input` combinationally on every cycle and
registered every clock edge. If `market_input` changes while the FSM is mid-traversal:

1. `path[]` gets overwritten with new "next pointers" based on the new input
2. The FSM, which is partway through chasing pointers from the old input, now follows
   a **corrupted mix** of old and new path decisions
3. The result is unpredictable — you might reach a wrong leaf or even cycle forever if
   the new pointers create a loop

**Fixes (pick one):**

**Option A — Register the input on `start`:**
```systemverilog
logic [7:0] market_input_reg;
always_ff @(posedge clk)
    if (start) market_input_reg <= market_input;
// Use market_input_reg in the always_comb block
```

**Option B — Gate the `path[]` update:**
```systemverilog
always_ff @(posedge clk) begin
    if (start) begin  // only capture path on start
        for (int k = 0; k < MAX_NODES; k++)
            path[k] <= computed_path[k];
    end
end
```

**Option C (best) — Both:** Register the input AND only compute/capture the path once.
This also saves power since the 64 comparators don't toggle on every input change.

---

## Evaluation Rubric

| Rating | Criteria |
|--------|----------|
| **Strong Hire** | Gets Parts 1–2 cleanly. Identifies the linked-list pattern and the `node_reg` pipeline delay unprompted. Proposes at least one optimization in Part 3 with correct trade-off analysis. Catches the `market_input` mid-traversal bug. |
| **Hire** | Gets Parts 1–2 with minor guidance. Recognizes the sequential nature. Proposes an optimization but may miss the pipeline delay or the mid-traversal bug. |
| **Borderline** | Completes Part 1 but struggles with cycle-by-cycle trace. Understands the concept but can't articulate timing details. Needs hints for Part 3. |
| **No Hire** | Cannot trace the tree. Doesn't distinguish combinational from sequential logic. Cannot identify optimization opportunities. |
