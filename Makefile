TOP_MODULE = decision_tree
HDL_FILES = decision_tree.sv
TB_FILES = decision_tree_tb.sv
WAVE_FILE = dump.vcd

# Pipelined variant
PIPE_HDL = decision_tree_pipelined.sv
PIPE_TB  = decision_tree_pipelined_tb.sv

all: test

# --- SystemVerilog testbenches (self-contained, no C++) ---
tb:
	verilator -cc $(HDL_FILES) $(TB_FILES) \
	--top-module decision_tree_tb \
	--trace --timing \
	--Mdir obj_dir_tb \
	--binary --build

	./obj_dir_tb/Vdecision_tree_tb

tb-pipe:
	verilator -cc $(PIPE_HDL) $(PIPE_TB) \
	--top-module decision_tree_pipelined_tb \
	--trace --timing \
	--Mdir obj_dir_pipe_tb \
	--binary --build

	./obj_dir_pipe_tb/Vdecision_tree_pipelined_tb

# --- Comprehensive comparison tests (C++ / Verilator) ---
test-orig:
	@echo "=== Building original design test ==="
	verilator --cc $(HDL_FILES) \
	--exe test_original.cpp \
	--trace --timing \
	--Mdir obj_dir_test_orig \
	--build \
	-o test_original
	@echo "=== Running original design test ==="
	./obj_dir_test_orig/test_original

test-pipe:
	@echo "=== Building pipelined design test ==="
	verilator --cc $(PIPE_HDL) \
	--exe test_pipelined.cpp \
	--trace --timing \
	--Mdir obj_dir_test_pipe \
	--build \
	-o test_pipelined
	@echo "=== Running pipelined design test ==="
	./obj_dir_test_pipe/test_pipelined

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

# --- Utilities ---
clean:
	rm -rf obj_dir_tb obj_dir_pipe_tb \
	       obj_dir_test_orig obj_dir_test_pipe \
	       $(WAVE_FILE) \
	       test_original.vcd test_pipelined.vcd \
	       results_original.txt results_pipelined.txt

wave:
	surfer $(WAVE_FILE)

lint:
	verilator --lint-only $(HDL_FILES) $(TB_FILES)

lint-pipe:
	verilator --lint-only $(PIPE_HDL) $(PIPE_TB)
