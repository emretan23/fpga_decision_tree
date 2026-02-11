`timescale 1ns / 1ps

module decision_tree_tb;

  // Parameters
  parameter MAX_NODES = 64;
  parameter ADDR_WIDTH = 6;

  // DUT signals
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
  logic [5:0] sw_data_left_idx;
  logic [5:0] sw_data_right_idx;
  logic [1:0] sw_data_action;

  // Clock generation
  initial clk = 0;
  always #5 clk = ~clk;

  // DUT instantiation
  decision_tree dut (
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

  // Task to write node
  task write_node(
    input [ADDR_WIDTH-1:0] addr,
    input logic is_leaf,
    input [7:0] threshold,
    input logic less_than,
    input [5:0] left,
    input [5:0] right,
    input [1:0] act
  );
  begin
    sw_addr = addr;
    sw_data_is_leaf = is_leaf;
    sw_data_threshold = threshold;
    sw_data_less_than = less_than;
    sw_data_left_idx = left;
    sw_data_right_idx = right;
    sw_data_action = act;
    sw_we = 1;
    @(posedge clk);
    sw_we = 0;
    @(posedge clk);
  end
  endtask

  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, decision_tree_tb);

    // Reset
    rst = 1;
    start = 0;
    sw_we = 0;
    @(posedge clk); @(posedge clk);
    rst = 0;

    // Write small tree
    // Node 0: input < 20 → L=1, R=2
    // Node 1: input < 10 → L=3(BUY), R=4(SELL)
    // Node 2: leaf CANCEL
    // Node 3: leaf BUY
    // Node 4: leaf SELL
    write_node(0, 0, 10, 1, 1, 2, 0);
    write_node(1, 0, 20, 1, 3, 4, 0);
    write_node(2, 0, 5, 0, 5, 6, 0);
    write_node(3, 1, 0, 0, 0, 0, 2'b01); // BUY
    write_node(4, 1, 0, 0, 0, 0, 2'b10); // SELL
    write_node(5, 1, 0, 0, 0, 0, 2'b11); // CANCEL
    write_node(6, 1, 0, 0, 0, 0, 2'b00); // NONE

    // Apply input
    market_input = 15; // should go to node 3 -> BUY
    start = 1;
    @(posedge clk);
    start = 0;

    // Wait for result
    repeat (10) @(posedge clk);
    if (action_valid)
      $display("Action: %0d", action);
    else
      $display("No action received");

    $finish;
  end

endmodule
