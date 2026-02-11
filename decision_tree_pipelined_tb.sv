`timescale 1ns / 1ps

module decision_tree_pipelined_tb;

  parameter MAX_NODES  = 64;
  parameter MAX_DEPTH  = 6;
  parameter ADDR_WIDTH = 6;

  logic clk;
  logic rst;
  logic [7:0] market_input;
  logic start;
  logic [1:0] action;
  logic action_valid;

  logic sw_we;
  logic [ADDR_WIDTH-1:0] sw_addr;
  logic sw_data_is_leaf;
  logic [7:0] sw_data_threshold;
  logic sw_data_less_than;
  logic [ADDR_WIDTH-1:0] sw_data_left_idx;
  logic [ADDR_WIDTH-1:0] sw_data_right_idx;
  logic [1:0] sw_data_action;

  // Clock: 10ns period
  initial clk = 0;
  always #5 clk = ~clk;

  // DUT
  decision_tree_pipelined #(
    .MAX_NODES(MAX_NODES),
    .MAX_DEPTH(MAX_DEPTH)
  ) dut (
    .clk(clk),
    .rst(rst),
    .market_input(market_input),
    .start(start),
    .action(action),
    .action_valid(action_valid),
    .sw_we(sw_we),
    .sw_addr(sw_addr),
    .sw_data_is_leaf(sw_data_is_leaf),
    .sw_data_threshold(sw_data_threshold),
    .sw_data_less_than(sw_data_less_than),
    .sw_data_left_idx(sw_data_left_idx),
    .sw_data_right_idx(sw_data_right_idx),
    .sw_data_action(sw_data_action)
  );

  // Task: write a node into tree memory
  task write_node(
    input [ADDR_WIDTH-1:0] addr,
    input logic is_leaf,
    input [7:0] threshold,
    input logic less_than,
    input [ADDR_WIDTH-1:0] left,
    input [ADDR_WIDTH-1:0] right,
    input [1:0] act
  );
  begin
    sw_addr            = addr;
    sw_data_is_leaf    = is_leaf;
    sw_data_threshold  = threshold;
    sw_data_less_than  = less_than;
    sw_data_left_idx   = left;
    sw_data_right_idx  = right;
    sw_data_action     = act;
    sw_we              = 1;
    @(posedge clk);
    sw_we = 0;
    @(posedge clk);
  end
  endtask

  // Task: send an input and wait for action_valid
  task run_input(
    input [7:0] inp,
    input string label
  );
  begin
    market_input = inp;
    start = 1;
    @(posedge clk);
    start = 0;

    // Wait up to MAX_DEPTH+4 cycles for result
    repeat (MAX_DEPTH + 4) begin
      @(posedge clk);
      if (action_valid) begin
        $display("[%s] input=%0d  action=%0d", label, inp, action);
        return;
      end
    end
    $display("[%s] input=%0d  TIMEOUT — no action_valid", label, inp);
  end
  endtask

  initial begin
    $dumpfile("dump_pipe.vcd");
    $dumpvars(0, decision_tree_pipelined_tb);

    // ---- Reset ----
    rst   = 1;
    start = 0;
    sw_we = 0;
    @(posedge clk); @(posedge clk);
    rst = 0;

    // ---- Load tree (same as original testbench) ----
    //
    //          [Node 0]
    //         input < 20?
    //          /      \
    //       yes        no
    //      [Node 1]  [Node 2]
    //     input < 10?  (input > 5?)
    //      /      \       /     \
    //   yes      no    yes      no
    // [Node 3] [Node 4] [Node 5] [Node 6]
    //   BUY      SELL    CANCEL    NONE
    //
    write_node(0, 0, 8'd10, 1, 6'd1, 6'd2, 2'b00);  // root: < 10 ? L=1 R=2
    write_node(1, 0, 8'd20, 1, 6'd3, 6'd4, 2'b00);  // node1: < 20 ? L=3 R=4
    write_node(2, 0, 8'd5,  0, 6'd5, 6'd6, 2'b00);  // node2: > 5 ?  L=5 R=6
    write_node(3, 1, 8'd0,  0, 6'd0, 6'd0, 2'b01);  // leaf BUY
    write_node(4, 1, 8'd0,  0, 6'd0, 6'd0, 2'b10);  // leaf SELL
    write_node(5, 1, 8'd0,  0, 6'd0, 6'd0, 2'b11);  // leaf CANCEL
    write_node(6, 1, 8'd0,  0, 6'd0, 6'd0, 2'b00);  // leaf NONE

    // ---- Test cases ----

    // input=5: 5 < 10 → node1, 5 < 20 → node3 → BUY (depth 2)
    run_input(8'd5, "TEST1");

    // input=15: 15 NOT < 10 → node2, 15 > 5 → node5 → CANCEL (depth 2)
    run_input(8'd15, "TEST2");

    // input=3: 3 < 10 → node1, 3 < 20 → node3 → BUY (depth 2)
    run_input(8'd3, "TEST3");

    // input=50: 50 NOT < 10 → node2, 50 > 5 → node5 → CANCEL (depth 2)
    run_input(8'd50, "TEST4");

    // ---- Pipeline throughput test: back-to-back inputs ----
    $display("--- Pipeline throughput test ---");
    market_input = 8'd5;  start = 1; @(posedge clk);
    market_input = 8'd15; start = 1; @(posedge clk);
    market_input = 8'd50; start = 1; @(posedge clk);
    start = 0;

    // Wait and collect results
    repeat (MAX_DEPTH + 6) begin
      @(posedge clk);
      if (action_valid)
        $display("[PIPE] action=%0d at time %0t", action, $time);
    end

    $display("--- Done ---");
    $finish;
  end

endmodule
