# FPGA Decision Tree Inference Engine — Interview Question

**Domain:** Digital Design / RTL / Low-Latency Systems
**Level:** Mid to Senior
**Time:** 45–60 minutes
**Topics:** FSM design, timing analysis, combinational vs sequential trade-offs, latency optimization, hardware data structures

---

## Preamble

You are designing a hardware accelerator for a low-latency trading system. The system
uses a **binary decision tree** to classify an 8-bit market signal and produce a 2-bit
trading action:

| Code | Action |
|------|--------|
| `00` | NONE   |
| `01` | BUY    |
| `10` | SELL   |
| `11` | CANCEL |

The tree is stored in an on-chip node array. Each node is either:

- An **internal node** with a threshold, a comparison direction (`<` or `>`), and
  indices pointing to left/right children.
- A **leaf node** with an action value.

Software pre-loads the tree via a write interface. Hardware then traverses the tree for
each incoming market signal.

A node is defined as:

```systemverilog
typedef struct packed {
    logic                  is_leaf;      // 1 = leaf
    logic [7:0]            threshold;    // comparison value
    logic                  less_than;    // 1 = use '<', 0 = use '>'
    logic [ADDR_WIDTH-1:0] left_idx;     // left child index
    logic [ADDR_WIDTH-1:0] right_idx;    // right child index
    logic [1:0]            action;       // leaf action (only valid if is_leaf=1)
} node_t;
```

The tree root is always at index 0. Maximum capacity is 64 nodes.

---

## Part 1 — Warm-up: Trace the Tree (10 min)

Given this tree loaded into memory:

| Index | is_leaf | threshold | less_than | left | right | action |
|-------|---------|-----------|-----------|------|-------|--------|
| 0     | 0       | 20        | 1 (`<`)   | 1    | 2     | --     |
| 1     | 0       | 10        | 1 (`<`)   | 3    | 4     | --     |
| 2     | 1       | --        | --        | --   | --    | CANCEL |
| 3     | 1       | --        | --        | --   | --    | BUY    |
| 4     | 1       | --        | --        | --   | --    | SELL   |

```
          [Node 0]
         input < 20?
          /      \
       yes        no
      [Node 1]  [Node 2]
     input < 10?  CANCEL
      /      \
   yes        no
 [Node 3]  [Node 4]
   BUY       SELL
```

**Q1a:** For `market_input = 5`, which leaf is reached and what is the action?

**Q1b:** For `market_input = 15`, which leaf is reached and what is the action?

**Q1c:** For `market_input = 25`, which leaf is reached and what is the action?

---

## Part 2 — RTL Analysis: Identify the Traversal Strategy (15 min)

A colleague wrote the following RTL for the decision tree traversal engine. Study the
code carefully:

```systemverilog
// --- Pre-computation block (combinational) ---
always_comb begin
    for (int j = 0; j < MAX_NODES; j++) begin
        node = tree_mem[j];
        cond = node.less_than ? (market_input < node.threshold)
                              : (market_input > node.threshold);
        computed_path[j] = cond ? node.left_idx : node.right_idx;
    end
end

// --- Register the computed paths ---
always_ff @(posedge clk) begin
    for (int k = 0; k < MAX_NODES; k++)
        path[k] <= computed_path[k];
end

// --- Traversal FSM ---
assign path_index = path[current_path_index];

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        action <= 0;  action_valid <= 0;
        path_valid <= 0;  current_path_index <= 0;
    end
    else if (start) begin
        path_valid <= 1;  action_valid <= 0;
        current_path_index <= 0;
    end
    else if (path_valid) begin
        node_reg <= tree_mem[path_index];
        if (node_reg.is_leaf) begin
            path_valid <= 0;
            action_valid <= 1;
            action <= node_reg.action;
        end else begin
            current_path_index <= path_index;
        end
    end
    else begin
        action_valid <= 0;
    end
end
```

**Q2a:** The `always_comb` block computes `computed_path[j]` for every node in parallel.
Describe in plain English what the `path[]` array represents after one clock edge.

**Q2b:** The FSM walks the `path[]` array starting at index 0. What familiar data
structure does this traversal resemble, and why?

**Q2c:** Note that `node_reg` is loaded via a non-blocking assignment (`<=`) but the
`is_leaf` check happens in the **same** `always_ff` block. What is the timing
consequence? What value does `node_reg.is_leaf` actually see?

**Q2d:** Using the tree from Part 1 with `market_input = 5`, fill in a cycle-by-cycle
trace starting from the `start` pulse. How many clock cycles from `start` assertion to
`action_valid` going high?

| Cycle | Event | `current_path_index` | `path_index` | `node_reg` loaded | `is_leaf` checked (old value) |
|-------|-------|---------------------|-------------|-------------------|-------------------------------|
| 0     | start=1 | ? | ? | ? | ? |
| 1     | | ? | ? | ? | ? |
| 2     | | ? | ? | ? | ? |
| 3     | | ? | ? | ? | ? |
| ...   | | | | | |

---

## Part 3 — Design Critique and Optimization (20 min)

**Q3a:** The combinational pre-computation evaluates all 64 nodes in parallel, but only
one root-to-leaf path (~6 nodes) is ever used. What is the cost of this approach in
terms of area and power? Is the extra computation "free"?

**Q3b:** Propose a redesign that achieves **single-cycle** leaf resolution (input to
action_valid in 1 clock cycle). What is the trade-off? Sketch the approach.

**Q3c:** Propose a redesign that achieves **throughput of one result per clock cycle**
while maintaining high fmax. How would you restructure the module?

**Q3d (Bonus):** The `path[]` array is re-computed from `market_input` on **every**
clock cycle, even during an active traversal. What happens if `market_input` changes
mid-traversal? Is this a bug? How would you fix it?
