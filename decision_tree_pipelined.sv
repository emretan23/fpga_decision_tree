`timescale 1ns / 1ps

// =============================================================================
// Pipelined Decision Tree — Alternative Implementation
// =============================================================================
//
// This is the "interview solution" version of decision_tree.sv.
//
// Key differences from the original:
//   1. Pipelined: one tree level evaluated per pipeline stage
//   2. Throughput: one new result per clock cycle (after pipeline fills)
//   3. Latency: exactly MAX_DEPTH cycles (no +1 penalty from register lag)
//   4. No wasted parallel pre-computation — only the traversed node is evaluated
//   5. market_input is captured once and flows through the pipeline (no mid-
//      traversal corruption bug)
//
// Same software write interface as the original for drop-in compatibility.
// =============================================================================

module decision_tree_pipelined #(
    parameter MAX_NODES  = 64,
    parameter MAX_DEPTH  = 6,                    // max tree depth (log2 of MAX_NODES)
    parameter ADDR_WIDTH = $clog2(MAX_NODES)
)(
    input  logic         clk,
    input  logic         rst,
    input  logic  [7:0]  market_input,
    input  logic         start,
    output logic  [1:0]  action,
    output logic         action_valid,

    // Software write interface (identical to original)
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
// Node definition (same as original)
// -------------------------------------------------------------------------
typedef struct packed {
    logic                  is_leaf;
    logic [7:0]            threshold;
    logic                  less_than;
    logic [ADDR_WIDTH-1:0] left_idx;
    logic [ADDR_WIDTH-1:0] right_idx;
    logic [1:0]            action;
} node_t;

// -------------------------------------------------------------------------
// Tree memory (shared, inferred as LUTRAM / distributed RAM)
// -------------------------------------------------------------------------
node_t tree_mem [0:MAX_NODES-1];

integer i;
initial begin
    for (i = 0; i < MAX_NODES; i++)
        tree_mem[i] = '0;
end

// Software write interface
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
// Pipeline registers
// -------------------------------------------------------------------------
// Each pipeline stage carries forward:
//   - valid:        is this pipeline slot active?
//   - resolved:     has a leaf already been found at an earlier stage?
//   - node_idx:     index of the node to evaluate at this stage
//   - input_val:    the captured market_input (frozen at start)
//   - result:       the action from the leaf (valid when resolved=1)

logic                  pipe_valid    [0:MAX_DEPTH];
logic                  pipe_resolved [0:MAX_DEPTH];
logic [ADDR_WIDTH-1:0] pipe_node_idx [0:MAX_DEPTH];
logic [7:0]            pipe_input    [0:MAX_DEPTH];
logic [1:0]            pipe_result   [0:MAX_DEPTH];

// -------------------------------------------------------------------------
// Stage 0: Capture input and inject into pipeline
// -------------------------------------------------------------------------
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        pipe_valid[0]    <= 1'b0;
        pipe_resolved[0] <= 1'b0;
        pipe_node_idx[0] <= '0;
        pipe_input[0]    <= '0;
        pipe_result[0]   <= '0;
    end else begin
        pipe_valid[0]    <= start;
        pipe_resolved[0] <= 1'b0;           // not yet resolved
        pipe_node_idx[0] <= '0;             // always start at root (index 0)
        pipe_input[0]    <= market_input;   // capture input — frozen for this traversal
        pipe_result[0]   <= '0;
    end
end

// -------------------------------------------------------------------------
// Stages 1..MAX_DEPTH: Evaluate one tree level per stage
// -------------------------------------------------------------------------
genvar s;
generate
    for (s = 1; s <= MAX_DEPTH; s++) begin : stage

        // Combinational: read the node and decide
        node_t                  cur_node;
        logic                   cond;
        logic [ADDR_WIDTH-1:0]  next_idx;

        always_comb begin
            cur_node = tree_mem[pipe_node_idx[s-1]];
            cond     = cur_node.less_than
                         ? (pipe_input[s-1] < cur_node.threshold)
                         : (pipe_input[s-1] > cur_node.threshold);
            next_idx = cond ? cur_node.left_idx : cur_node.right_idx;
        end

        // Sequential: register the pipeline stage
        always_ff @(posedge clk or posedge rst) begin
            if (rst) begin
                pipe_valid[s]    <= 1'b0;
                pipe_resolved[s] <= 1'b0;
                pipe_node_idx[s] <= '0;
                pipe_input[s]    <= '0;
                pipe_result[s]   <= '0;
            end else begin
                pipe_valid[s]    <= pipe_valid[s-1];
                pipe_input[s]    <= pipe_input[s-1];

                if (!pipe_valid[s-1]) begin
                    // Bubble — no active data
                    pipe_resolved[s] <= 1'b0;
                    pipe_node_idx[s] <= '0;
                    pipe_result[s]   <= '0;
                end
                else if (pipe_resolved[s-1]) begin
                    // Already found a leaf in an earlier stage — just pass through
                    pipe_resolved[s] <= 1'b1;
                    pipe_node_idx[s] <= pipe_node_idx[s-1];
                    pipe_result[s]   <= pipe_result[s-1];
                end
                else if (cur_node.is_leaf) begin
                    // This node is a leaf — resolve now
                    pipe_resolved[s] <= 1'b1;
                    pipe_node_idx[s] <= pipe_node_idx[s-1];
                    pipe_result[s]   <= cur_node.action;
                end
                else begin
                    // Internal node — advance to child
                    pipe_resolved[s] <= 1'b0;
                    pipe_node_idx[s] <= next_idx;
                    pipe_result[s]   <= '0;
                end
            end
        end

    end
endgenerate

// -------------------------------------------------------------------------
// Output: tap the end of the pipeline
// -------------------------------------------------------------------------
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        action       <= '0;
        action_valid <= 1'b0;
    end else begin
        action_valid <= pipe_valid[MAX_DEPTH] & pipe_resolved[MAX_DEPTH];
        action       <= pipe_result[MAX_DEPTH];
    end
end

endmodule
