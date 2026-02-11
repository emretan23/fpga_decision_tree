// =============================================================================
// Decision Tree Inference Engine — Original (FSM-based) Implementation
// =============================================================================
//
// Architecture overview:
//
//   This module stores a binary decision tree in an on-chip node array and
//   traverses it to classify an 8-bit market signal into a 2-bit trading
//   action (NONE / BUY / SELL / CANCEL).
//
//   The design has two phases:
//
//   Phase 1 — Pre-computation (combinational, always_comb):
//     For ALL 64 nodes in parallel, evaluate the threshold comparison against
//     market_input and store the "next child index" in computed_path[]. This
//     effectively builds a "next pointer" table for the entire tree.  The
//     result is registered into path[] on the clock edge when start is pulsed.
//
//   Phase 2 — Traversal (sequential FSM, always_ff):
//     Starting at node 0 (root), follow the path[] pointers one hop per clock
//     cycle:  current_path_index → path[current_path_index] → ...
//     Stop when a leaf node is found and output its action.
//
//   This makes the traversal behave like a singly-linked-list walk.
//   Latency = tree_depth cycles.
//
//   Remaining trade-offs:
//     - 64 parallel comparators are synthesised but only ~depth are used.
//       Wastes area and dynamic power; does not affect latency.
//     - Throughput is limited: only one traversal can be in flight at a time.
//
//   Bugs fixed (vs original):
//     - path[] is now only captured on start, not every cycle. Prevents
//       mid-traversal corruption if market_input changes.
//     - Leaf detection uses a combinational read of tree_mem instead of a
//       registered node_reg, eliminating the +1 cycle off-by-one latency.
//
// =============================================================================

`timescale 1ns / 1ps

module decision_tree #(
    parameter MAX_NODES = 64,
    parameter ADDR_WIDTH = $clog2(MAX_NODES)
)(
    input  logic         clk,
    input  logic         rst,
    input  logic  [7:0]  market_input,  // 8-bit market signal to classify
    input  logic         start,         // pulse high for 1 cycle to begin traversal
    output logic  [1:0]  action,        // 00=NONE, 01=BUY, 10=SELL, 11=CANCEL
    output logic         action_valid,  // high for 1 cycle when action is ready

    // Interface for software to write tree nodes one at a time.
    // Assert sw_we for one cycle with address and field values to program a node.
    input  logic                  sw_we,
    input  logic [ADDR_WIDTH-1:0] sw_addr,
    input  logic                  sw_data_is_leaf,
    input  logic [7:0]            sw_data_threshold,
    input  logic                  sw_data_less_than,
    input  logic [ADDR_WIDTH-1:0] sw_data_left_idx,
    input  logic [ADDR_WIDTH-1:0] sw_data_right_idx,
    input  logic [1:0]            sw_data_action
);

// -------------------------------------------------------------------------
// Tree Node Definition
// -------------------------------------------------------------------------
// Each node is packed into a single word.  For MAX_NODES=64 (ADDR_WIDTH=6):
//   is_leaf(1) + threshold(8) + less_than(1) + left_idx(6) + right_idx(6) + action(2)
//   = 24 bits per node
// Internal nodes use threshold/less_than/left_idx/right_idx.
// Leaf nodes only use is_leaf and action; other fields are don't-cares.
typedef struct packed {
    logic                  is_leaf;
    logic [7:0]            threshold;
    logic                  less_than;
    logic [ADDR_WIDTH-1:0] left_idx;
    logic [ADDR_WIDTH-1:0] right_idx;
    logic [1:0]            action;
} node_t;

// -------------------------------------------------------------------------
// Tree memory — 64 nodes, inferred as LUTRAM (distributed RAM)
// -------------------------------------------------------------------------
integer i, j, k;

node_t tree_mem [0:MAX_NODES-1];

// -------------------------------------------------------------------------
// Traversal state signals
// -------------------------------------------------------------------------
logic cond;                                         // threshold comparison result (combinational)
node_t node;                                        // current node being evaluated (combinational)
node_t current_node;                                // combinational read of tree_mem at path_index
logic path_valid = 0;                               // 1 = FSM is actively traversing
logic [ADDR_WIDTH-1:0] path [0:MAX_NODES-1];        // registered "next pointer" table (frozen after start):
                                                    //   path[j] = child index to visit from node j
logic [ADDR_WIDTH-1:0] path_index;                  // = path[current_path_index], the next node to visit
logic [ADDR_WIDTH-1:0] current_path_index = 0;      // the node whose "next pointer" we are following
logic [ADDR_WIDTH-1:0] computed_path [0:MAX_NODES-1]; // combinational version of path[] (before register)

// Simulation-only: zero-initialise all nodes.
// NOTE: $dumpfile/$dumpvars removed — they conflict with the C++ Verilator
// trace (VerilatedVcdC). VCD dumping is controlled from the C++ test harness.
initial begin
    for (i = 0; i < MAX_NODES; i++) begin
        tree_mem[i] = '0;
    end
end

// -------------------------------------------------------------------------
// Software write interface
// -------------------------------------------------------------------------
// One node is programmed per clock cycle when sw_we is asserted.
// Typical usage: software writes all nodes before asserting start.
// There is no protection against writing while a traversal is in progress.
always_ff @(posedge clk) begin
    if (sw_we) begin
        tree_mem[sw_addr].is_leaf    <= sw_data_is_leaf;
        tree_mem[sw_addr].threshold  <= sw_data_threshold;
        tree_mem[sw_addr].less_than  <= sw_data_less_than;
        tree_mem[sw_addr].left_idx   <= sw_data_left_idx;
        tree_mem[sw_addr].right_idx  <= sw_data_right_idx;
        tree_mem[sw_addr].action     <= sw_data_action;
    end
end

// -------------------------------------------------------------------------
// Pointer dereference: look up the "next node" from the current position
// -------------------------------------------------------------------------
// This is the linked-list "follow the pointer" step:
//   path_index = path[current_path_index]
// i.e., "from node current_path_index, go to node path_index next."
assign path_index = path[current_path_index];

// -------------------------------------------------------------------------
// Phase 1 — Parallel pre-computation (combinational)
// -------------------------------------------------------------------------
// For EVERY node j in the tree, evaluate:
//   "if market_input were at node j, which child would we visit?"
// Result: computed_path[j] = left_idx or right_idx of node j.
//
// This builds a complete "next pointer" table in one combinational pass.
// Synthesises MAX_NODES comparators + muxes in parallel — only ~depth of
// them are ever useful for a given traversal.  The rest waste area/power.
always_comb begin
    for (j = 0; j < MAX_NODES; j++) begin
        node = tree_mem[j];
        cond = node.less_than ? (market_input < node.threshold)
                              : (market_input > node.threshold);
        computed_path[j] = cond ? node.left_idx : node.right_idx;
    end
end

// Register the "next pointer" table ONLY when start is asserted.
// Once captured, path[] is frozen for the entire traversal — if
// market_input changes mid-traversal, it does NOT corrupt the path.
always_ff @(posedge clk) begin
    if (start) begin
        for (k = 0; k < MAX_NODES; k++)
            path[k] <= computed_path[k];
    end
end

// -------------------------------------------------------------------------
// Combinational node read — check the node at path_index without registering
// -------------------------------------------------------------------------
// This eliminates the old node_reg off-by-one bug: we check is_leaf on the
// CURRENT node in the same cycle it's read, not on the previous cycle's
// stale registered copy.
assign current_node = tree_mem[path_index];

// -------------------------------------------------------------------------
// Phase 2 — Traversal FSM (sequential, one hop per clock cycle)
// -------------------------------------------------------------------------
//
// State machine:
//   IDLE  → (start=1) → WALKING → (leaf found) → IDLE
//
// Walking behaviour:
//   Each cycle:  current_path_index  →  path_index = path[current_path_index]
//                current_node = tree_mem[path_index]  (combinational read)
//                if leaf → done, else advance
//
// Timing (tree: root → child → leaf, depth=2):
//   Cycle 0: start=1, arm FSM, path[] captured
//   Cycle 1: path_index=path[0]=child, current_node=tree_mem[child] → not leaf → advance
//   Cycle 2: path_index=path[child]=leaf, current_node=tree_mem[leaf] → IS leaf → done
//
//   Total latency = depth cycles (no +1 penalty).
//
// Throughput:
//   Only one traversal can be active at a time.  A new start pulse must
//   wait until the current traversal finishes (action_valid goes high).
//
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        action <= 0;
        action_valid <= 0;
        path_valid <= 0;
        current_path_index <= 0;
    end 
    else begin
        if (start) begin
            // Arm the FSM: begin traversal from root (index 0)
            path_valid <= 1;
            action_valid <= 0;
            current_path_index <= 0;
        end 
        else if (path_valid) begin
            // Check if the node at the current path pointer is a leaf.
            // current_node is a combinational read — no register delay.
            if (current_node.is_leaf) begin
                path_valid <= 0;
                action_valid <= 1;
                action <= current_node.action;
            end else begin
                // Not a leaf — advance to the next node in the chain.
                // This is the linked-list step: current = next[current]
                current_path_index <= path_index;
            end
        end 
        else begin
            // IDLE: clear action_valid after one cycle
            action_valid <= 0;
        end
    end
end

endmodule
