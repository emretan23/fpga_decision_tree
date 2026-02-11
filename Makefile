# ===========================================================================
# FPGA Decision Tree — Build System
# ===========================================================================

# --- Source paths ---
RTL_DIR  = rtl
TB_DIR   = tb
SIM_DIR  = sim
BUILD_DIR = build

HDL_FILES = $(RTL_DIR)/decision_tree.sv
TB_FILES  = $(TB_DIR)/decision_tree_tb.sv

PIPE_HDL  = $(RTL_DIR)/decision_tree_pipelined.sv
PIPE_TB   = $(TB_DIR)/decision_tree_pipelined_tb.sv

all: test

# ===========================================================================
# SystemVerilog testbenches (self-contained, no C++)
# ===========================================================================
tb:
	@mkdir -p $(BUILD_DIR)/tb
	verilator -cc $(HDL_FILES) $(TB_FILES) \
	--top-module decision_tree_tb \
	--trace --timing \
	--Mdir $(BUILD_DIR)/tb \
	--binary --build

	./$(BUILD_DIR)/tb/Vdecision_tree_tb

tb-pipe:
	@mkdir -p $(BUILD_DIR)/tb_pipe
	verilator -cc $(PIPE_HDL) $(PIPE_TB) \
	--top-module decision_tree_pipelined_tb \
	--trace --timing \
	--Mdir $(BUILD_DIR)/tb_pipe \
	--binary --build

	./$(BUILD_DIR)/tb_pipe/Vdecision_tree_pipelined_tb

# ===========================================================================
# Comprehensive comparison tests (C++ / Verilator + golden model)
# ===========================================================================
test-orig:
	@echo "=== Building original design test ==="
	@mkdir -p $(BUILD_DIR)/test_orig
	verilator --cc $(HDL_FILES) \
	--exe ../$(SIM_DIR)/test_original.cpp \
	--trace \
	--Mdir $(BUILD_DIR)/test_orig \
	--build \
	-o test_original
	@echo "=== Running original design test ==="
	./$(BUILD_DIR)/test_orig/test_original

test-pipe:
	@echo "=== Building pipelined design test ==="
	@mkdir -p $(BUILD_DIR)/test_pipe
	verilator --cc $(PIPE_HDL) \
	--exe ../$(SIM_DIR)/test_pipelined.cpp \
	--trace \
	--Mdir $(BUILD_DIR)/test_pipe \
	--build \
	-o test_pipelined
	@echo "=== Running pipelined design test ==="
	./$(BUILD_DIR)/test_pipe/test_pipelined

test: test-orig test-pipe
	@echo ""
	@echo "========================================"
	@echo "  Both tests complete. Compare results:"
	@echo "========================================"
	@echo ""
	@echo "  results_original.txt   (FSM / linked-list)"
	@echo "  results_pipelined.txt  (pipelined)"
	@echo ""
	@echo "  Waveforms:"
	@echo "    test_original.vcd"
	@echo "    test_pipelined.vcd"
	@echo ""

# ===========================================================================
# Utilities
# ===========================================================================
clean:
	rm -rf $(BUILD_DIR) \
	       *.vcd \
	       results_original.txt results_pipelined.txt

wave:
	surfer dump.vcd

lint:
	verilator --lint-only $(HDL_FILES) $(TB_FILES)

lint-pipe:
	verilator --lint-only $(PIPE_HDL) $(PIPE_TB)

.PHONY: all tb tb-pipe test-orig test-pipe test clean wave lint lint-pipe
