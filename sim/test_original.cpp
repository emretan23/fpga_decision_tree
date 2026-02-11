#include "Vdecision_tree.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <cstdio>
#include <cstdint>
#include <vector>
#include <string>

// =========================================================================
// Test harness for the ORIGINAL (FSM-based) decision tree
// Output: results_original.txt
// =========================================================================

vluint64_t sim_time = 0;
double sc_time_stamp() { return sim_time; }

static void tick(Vdecision_tree *dut, VerilatedVcdC *tfp) {
    dut->clk = 0; dut->eval(); tfp->dump(sim_time); sim_time += 5;
    dut->clk = 1; dut->eval(); tfp->dump(sim_time); sim_time += 5;
    tfp->flush();
}

struct Node {
    uint8_t is_leaf;
    uint8_t threshold;
    uint8_t less_than;
    uint8_t left_idx;
    uint8_t right_idx;
    uint8_t action;
};

struct TestCase {
    uint8_t input;
    int expected_action;   // 0=NONE 1=BUY 2=SELL 3=CANCEL
    int expected_depth;
    const char *label;
};

static const char *action_name(int a) {
    switch (a) {
        case 0: return "NONE  ";
        case 1: return "BUY   ";
        case 2: return "SELL  ";
        case 3: return "CANCEL";
        default: return "???   ";
    }
}

// =========================================================================
// Software golden model — walks the tree in pure C++, no Verilog involved.
// This is the reference: if HW disagrees with this, HW has a bug.
// If this disagrees with our hand-traced expectations, WE had a bug.
// =========================================================================
struct SimResult {
    int action;    // leaf action (0-3)
    int depth;     // number of edges from root to leaf
    bool valid;    // false if tree is malformed (loop, missing leaf, etc.)
};

static SimResult simulate_tree(const std::vector<Node> &tree, uint8_t input) {
    SimResult r = {0, 0, false};
    int idx = 0;  // start at root

    for (int step = 0; step < 64; step++) {  // cap at 64 to detect infinite loops
        if (idx < 0 || idx >= (int)tree.size()) return r;  // out of bounds
        const Node &n = tree[idx];
        if (n.is_leaf) {
            r.action = n.action;
            r.depth  = step;
            r.valid  = true;
            return r;
        }
        bool cond = n.less_than ? (input < n.threshold) : (input > n.threshold);
        idx = cond ? n.left_idx : n.right_idx;
    }

    return r;  // valid=false — probable cycle in tree
}

static void write_node(Vdecision_tree *dut, VerilatedVcdC *tfp,
                        int addr, const Node &n) {
    dut->sw_we             = 1;
    dut->sw_addr           = addr;
    dut->sw_data_is_leaf   = n.is_leaf;
    dut->sw_data_threshold = n.threshold;
    dut->sw_data_less_than = n.less_than;
    dut->sw_data_left_idx  = n.left_idx;
    dut->sw_data_right_idx = n.right_idx;
    dut->sw_data_action    = n.action;
    tick(dut, tfp);
    dut->sw_we = 0;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    auto *dut = new Vdecision_tree;
    auto *tfp = new VerilatedVcdC;
    dut->trace(tfp, 99);
    tfp->open("test_original.vcd");

    FILE *out = fopen("results_original.txt", "w");

    // =====================================================================
    // Tree with mixed depths (15 nodes, max depth = 5)
    // =====================================================================
    //
    //                     [0] input < 128?
    //                    /                \
    //              [1] < 64              [2] < 192
    //             /       \             /         \
    //         [3] < 32   [4]SELL    [5] < 160   [6]NONE       depth 2 leaves
    //        /      \                /       \
    //    [7]<16   [8]CANCEL     [9]BUY    [10]SELL             depth 3 leaves
    //    /     \
    // [11]<8  [12]SELL                                         depth 4 leaf
    //  /    \
    // [13]BUY [14]CANCEL                                       depth 5 leaves

    std::vector<Node> tree = {
        // idx  leaf  thr  lt  L   R   act
        /*  0*/ {0, 128, 1,  1,  2, 0},   // <128 → L=1, R=2
        /*  1*/ {0,  64, 1,  3,  4, 0},   // <64  → L=3, R=4
        /*  2*/ {0, 192, 1,  5,  6, 0},   // <192 → L=5, R=6
        /*  3*/ {0,  32, 1,  7,  8, 0},   // <32  → L=7, R=8
        /*  4*/ {1,   0, 0,  0,  0, 2},   // leaf SELL
        /*  5*/ {0, 160, 1,  9, 10, 0},   // <160 → L=9, R=10
        /*  6*/ {1,   0, 0,  0,  0, 0},   // leaf NONE
        /*  7*/ {0,  16, 1, 11, 12, 0},   // <16  → L=11, R=12
        /*  8*/ {1,   0, 0,  0,  0, 3},   // leaf CANCEL
        /*  9*/ {1,   0, 0,  0,  0, 1},   // leaf BUY
        /* 10*/ {1,   0, 0,  0,  0, 2},   // leaf SELL
        /* 11*/ {0,   8, 1, 13, 14, 0},   // <8   → L=13, R=14
        /* 12*/ {1,   0, 0,  0,  0, 2},   // leaf SELL
        /* 13*/ {1,   0, 0,  0,  0, 1},   // leaf BUY
        /* 14*/ {1,   0, 0,  0,  0, 3},   // leaf CANCEL
    };

    // Build test cases from the software golden model (no hand-tracing!)
    uint8_t spot_inputs[] = {4, 10, 20, 40, 80, 140, 170, 200, 0, 127, 128, 255};
    std::vector<TestCase> tests;
    for (uint8_t inp : spot_inputs) {
        SimResult sw = simulate_tree(tree, inp);
        TestCase tc;
        tc.input           = inp;
        tc.expected_action = sw.action;
        tc.expected_depth  = sw.depth;
        tc.label           = "";
        tests.push_back(tc);
    }

    // ----- Reset -----
    dut->rst   = 1;
    dut->start = 0;
    dut->sw_we = 0;
    tick(dut, tfp); tick(dut, tfp);
    dut->rst = 0;
    tick(dut, tfp);

    // ----- Load tree -----
    for (int i = 0; i < (int)tree.size(); i++)
        write_node(dut, tfp, i, tree[i]);

    // Allow one extra cycle for path[] to register after tree is loaded
    tick(dut, tfp);

    // =====================================================================
    // Header
    // =====================================================================
    fprintf(out, "================================================================\n");
    fprintf(out, "  Decision Tree Test — ORIGINAL (FSM / linked-list traversal)\n");
    fprintf(out, "================================================================\n\n");
    fprintf(out, "Tree: 15 nodes, max depth 5, leaves at depths 2–5\n\n");

    fprintf(out, "Tree structure:\n");
    fprintf(out, "                     [0] input < 128?\n");
    fprintf(out, "                    /                \\\n");
    fprintf(out, "              [1] < 64              [2] < 192\n");
    fprintf(out, "             /       \\             /         \\\n");
    fprintf(out, "         [3] < 32   [4]SELL    [5] < 160   [6]NONE     depth 2\n");
    fprintf(out, "        /      \\                /       \\\n");
    fprintf(out, "    [7]<16   [8]CANCEL     [9]BUY    [10]SELL          depth 3\n");
    fprintf(out, "    /     \\\n");
    fprintf(out, " [11]<8  [12]SELL                                      depth 4\n");
    fprintf(out, "  /    \\\n");
    fprintf(out, " [13]BUY [14]CANCEL                                    depth 5\n\n");

    // =====================================================================
    // Individual query tests — measure latency per input
    // =====================================================================
    fprintf(out, "----------------------------------------------------------------\n");
    fprintf(out, "  Individual Query Tests  (latency = cycles from start to valid)\n");
    fprintf(out, "----------------------------------------------------------------\n\n");
    fprintf(out, "  Input | Depth | Expected | Got      | Cycles | Status\n");
    fprintf(out, "  ------|-------|----------|----------|--------|------\n");

    int pass_count = 0;
    int total      = (int)tests.size();

    for (auto &tc : tests) {
        dut->market_input = tc.input;

        // Let path[] settle for the new market_input (1 cycle to compute + register)
        tick(dut, tfp);

        // Pulse start
        dut->start = 1;
        tick(dut, tfp);
        dut->start = 0;

        int cycles = 0;
        bool got_result = false;
        int got_action  = -1;

        for (int c = 0; c < 20; c++) {
            tick(dut, tfp);
            cycles++;
            if (dut->action_valid) {
                got_action = dut->action;
                got_result = true;
                break;
            }
        }

        bool ok = got_result && (got_action == tc.expected_action);
        if (ok) pass_count++;

        fprintf(out, "  %5d |   %d   | %s | %s | %6d | %s\n",
                tc.input,
                tc.expected_depth,
                action_name(tc.expected_action),
                got_result ? action_name(got_action) : "TIMEOUT",
                got_result ? cycles : -1,
                ok ? "PASS" : "*** FAIL ***");
    }

    // =====================================================================
    // Throughput test — original can only do one at a time
    // =====================================================================
    fprintf(out, "\n----------------------------------------------------------------\n");
    fprintf(out, "  Throughput Test  (back-to-back queries, sequential)\n");
    fprintf(out, "----------------------------------------------------------------\n\n");

    uint8_t throughput_inputs[] = {4, 80, 140, 200, 10, 20, 170, 40};
    int n_tp = 8;

    // Compute expected depths from golden model
    int throughput_depths[8];
    int throughput_expected[8];
    for (int t = 0; t < n_tp; t++) {
        SimResult sw = simulate_tree(tree, throughput_inputs[t]);
        throughput_depths[t]   = sw.depth;
        throughput_expected[t] = sw.action;
    }

    fprintf(out, "  #  | Input | Depth | Result | Start@cycle | Done@cycle | Latency\n");
    fprintf(out, "  ---|-------|-------|--------|-------------|------------|--------\n");

    int global_cycle = 0;
    int first_done = -1, last_done = -1;

    for (int t = 0; t < n_tp; t++) {
        dut->market_input = throughput_inputs[t];
        tick(dut, tfp);  // let path[] settle
        global_cycle++;

        int start_cycle = global_cycle;
        dut->start = 1;
        tick(dut, tfp);
        global_cycle++;
        dut->start = 0;

        int lat = 0;
        int result = -1;
        for (int c = 0; c < 20; c++) {
            tick(dut, tfp);
            global_cycle++;
            lat++;
            if (dut->action_valid) {
                result = dut->action;
                if (first_done < 0) first_done = global_cycle;
                last_done = global_cycle;
                break;
            }
        }

        fprintf(out, "  %d  | %5d |   %d   | %s | %11d | %10d | %d cycles\n",
                t, throughput_inputs[t], throughput_depths[t],
                action_name(result), start_cycle, global_cycle, lat);
    }

    int total_throughput_cycles = last_done - first_done;
    fprintf(out, "\n  First result at global cycle %d\n", first_done);
    fprintf(out, "  Last  result at global cycle %d\n", last_done);
    fprintf(out, "  8 results in %d cycles  →  avg %.2f cycles/result\n",
            total_throughput_cycles, total_throughput_cycles / 7.0);
    fprintf(out, "  (Original processes one query at a time — no pipelining)\n");

    // =====================================================================
    // Exhaustive verification — all 256 possible inputs vs golden model
    // =====================================================================
    fprintf(out, "\n----------------------------------------------------------------\n");
    fprintf(out, "  Exhaustive Verification  (all 256 inputs vs C++ golden model)\n");
    fprintf(out, "----------------------------------------------------------------\n\n");

    int exhaust_pass = 0;
    int exhaust_fail = 0;

    for (int inp = 0; inp < 256; inp++) {
        SimResult sw = simulate_tree(tree, (uint8_t)inp);

        dut->market_input = inp;
        tick(dut, tfp);  // let path[] settle

        dut->start = 1;
        tick(dut, tfp);
        dut->start = 0;

        int hw_action = -1;
        bool got = false;
        for (int c = 0; c < 20; c++) {
            tick(dut, tfp);
            if (dut->action_valid) {
                hw_action = dut->action;
                got = true;
                break;
            }
        }

        if (got && hw_action == sw.action) {
            exhaust_pass++;
        } else {
            exhaust_fail++;
            fprintf(out, "  MISMATCH input=%3d: SW=%s HW=%s\n",
                    inp, action_name(sw.action),
                    got ? action_name(hw_action) : "TIMEOUT");
        }
    }

    if (exhaust_fail == 0)
        fprintf(out, "  All 256 inputs match the golden model.\n");
    fprintf(out, "  Passed: %d / 256    Failed: %d / 256\n", exhaust_pass, exhaust_fail);

    // =====================================================================
    // Summary
    // =====================================================================
    fprintf(out, "\n================================================================\n");
    fprintf(out, "  Summary\n");
    fprintf(out, "================================================================\n");
    fprintf(out, "  Spot tests:        %d / %d\n", pass_count, total);
    fprintf(out, "  Exhaustive (0-255): %d / 256\n", exhaust_pass);
    fprintf(out, "  Design: FSM traversal (linked-list walk)\n");
    fprintf(out, "  Latency formula: depth + 1 cycles\n");
    fprintf(out, "  Throughput: 1 result every (depth + 1 + 1) cycles (sequential)\n");
    fprintf(out, "  Verification: C++ golden model (simulate_tree)\n");
    fprintf(out, "================================================================\n");

    printf("Original test complete — results written to results_original.txt\n");

    fclose(out);
    tfp->close();
    delete dut;
    return 0;
}
