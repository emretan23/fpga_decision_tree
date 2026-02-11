`timescale 1ns / 1ps

// =============================================================================
// Top-level wrapper for Digilent Arty A7-35T
// =============================================================================
//
// Maps the decision_tree module to board I/O:
//
//   Clock:   100 MHz onboard oscillator (E3)
//   Reset:   BTN0 (active high, directly wired — no debounce)
//   Start:   BTN1 (active high, directly wired — no debounce)
//
//   market_input[7:0]:
//     [3:0] = SW[3:0]   (4 onboard switches)
//     [7:4] = JA[3:0]   (Pmod header JA, accent pins 1–4)
//
//   action[1:0]:
//     LED[0] = action[0]
//     LED[1] = action[1]
//
//   action_valid:
//     LED[2] = action_valid
//
//   LED[3] = heartbeat (1 Hz blink to confirm FPGA is alive)
//
//   Software write interface exposed on Pmod JB for external controller:
//     JB[0]   = sw_we
//     JB[3:1] = sw_addr[2:0]  (only 3 bits exposed — supports 8 nodes)
//     JB[4]   = sw_data_is_leaf
//     JB[5]   = sw_data_less_than
//     JB[7:6] = sw_data_action[1:0]
//   Remaining sw_data fields (threshold, left/right idx) on Pmod JC:
//     JC[7:0] = sw_data_threshold[7:0]
//   Pmod JD:
//     JD[5:0] = sw_data_left_idx[5:0]
//     JD[7]   = unused
//     JD[6]   = unused
//   Note: sw_data_right_idx uses sw_addr bits repurposed after write —
//         for a full board deployment, use a UART/SPI controller instead.
//         This pin mapping is for synthesis/implementation testing only.
//
// =============================================================================

module top_arty (
    // Board clock and reset
    input  logic        CLK100MHZ,
    input  logic [3:0]  btn,
    input  logic [3:0]  sw,
    output logic [3:0]  led,

    // Pmod JA — market_input[7:4]
    input  logic [7:0]  ja,

    // Pmod JB — sw_we, sw_addr, sw_data control
    input  logic [7:0]  jb,

    // Pmod JC — sw_data_threshold
    input  logic [7:0]  jc,

    // Pmod JD — sw_data_left_idx, sw_data_right_idx
    input  logic [7:0]  jd
);

    // ---- Internal signals ----
    logic        clk;
    logic        rst;
    logic        start;
    logic [7:0]  market_input;
    logic [1:0]  action;
    logic        action_valid;

    // Software write interface
    logic        sw_we;
    logic [5:0]  sw_addr;
    logic        sw_data_is_leaf;
    logic [7:0]  sw_data_threshold;
    logic        sw_data_less_than;
    logic [5:0]  sw_data_left_idx;
    logic [5:0]  sw_data_right_idx;
    logic [1:0]  sw_data_action;

    // Heartbeat counter (1 Hz blink at 100 MHz)
    logic [26:0] heartbeat_cnt = 0;

    // ---- Clock and control ----
    assign clk   = CLK100MHZ;
    assign rst    = btn[0];
    assign start  = btn[1];

    // ---- Market input: switches + Pmod JA ----
    assign market_input = {ja[3:0], sw[3:0]};

    // ---- Software write interface from Pmod headers ----
    assign sw_we             = jb[0];
    assign sw_addr           = {3'b000, jb[3:1]};  // 3 LSBs from JB
    assign sw_data_is_leaf   = jb[4];
    assign sw_data_less_than = jb[5];
    assign sw_data_action    = jb[7:6];
    assign sw_data_threshold = jc[7:0];
    assign sw_data_left_idx  = jd[5:0];
    assign sw_data_right_idx = jd[5:0];  // shared — limitation of pin count

    // ---- Decision tree instance ----
    decision_tree #(
        .MAX_NODES(64)
    ) u_tree (
        .clk              (clk),
        .rst              (rst),
        .market_input     (market_input),
        .start            (start),
        .action           (action),
        .action_valid     (action_valid),
        .sw_we            (sw_we),
        .sw_addr          (sw_addr),
        .sw_data_is_leaf  (sw_data_is_leaf),
        .sw_data_threshold(sw_data_threshold),
        .sw_data_less_than(sw_data_less_than),
        .sw_data_left_idx (sw_data_left_idx),
        .sw_data_right_idx(sw_data_right_idx),
        .sw_data_action   (sw_data_action)
    );

    // ---- LED outputs ----
    assign led[0] = action[0];
    assign led[1] = action[1];
    assign led[2] = action_valid;
    assign led[3] = heartbeat_cnt[26];  // ~0.75 Hz blink

    // ---- Heartbeat ----
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            heartbeat_cnt <= 0;
        else
            heartbeat_cnt <= heartbeat_cnt + 1;
    end

endmodule
