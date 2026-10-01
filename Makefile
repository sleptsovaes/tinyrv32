SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

# Avoid tab-sensitive Makefile recipes.
.RECIPEPREFIX := >

IVERILOG ?= iverilog
VVP      ?= vvp
PYTHON   ?= python3
RISCV_PREFIX ?= riscv64-unknown-elf-
YOSYS    ?= yosys
export IVERILOG VVP RISCV_PREFIX YOSYS

IVFLAGS := -g2012

BUILD_DIR := build

RTL := \
	rtl/alu.sv \
	rtl/regfile.sv \
	rtl/imm_gen.sv \
	rtl/control_unit.sv \
	rtl/pc.sv \
	rtl/next_pc.sv \
	rtl/cpu_core.sv

UNIT_NAMES := \
	alu \
	regfile \
	imm_gen \
	control_unit \
	pc

UNIT_BINS := $(addprefix $(BUILD_DIR)/,$(addsuffix _test,$(UNIT_NAMES)))

.PHONY: \
	versions \
	help \
	check \
	checkers \
	upgrade \
	upgrade-quick \
	formal \
	synth-upgrade \
	reference \
	unit \
	regression \
	differential \
	test \
	physical \
	report-manifest \
	clean


help:
> @echo "TinyRV32 verification targets"
> @echo
> @echo "  make check         - syntax-check Python verification tools"
> @echo "  make reference     - run Python architectural model self-test"
> @echo "  make unit          - run RTL unit testbenches"
> @echo "  make regression    - run integrated CPU regression"
> @echo "  make differential  - run 100 randomized differential tests"
> @echo "  make test          - run historical core regression and checker tests"
> @echo "  make upgrade       - test RV32 execution core, waits, compiled C and UART"
> @echo "  make upgrade-quick - smaller RV32 smoke test (10 random programs)"
> @echo "  make formal        - bounded safety checks for both predictor modes"
> @echo "  make synth-upgrade - generic synthesis/check of core and SoC (no PPA claim)"
> @echo "  make clean         - remove generated simulation artifacts"
> @echo "  make physical      - run SKY130 RTL-to-GDS flow with ORFS"

$(BUILD_DIR):
> mkdir -p $(BUILD_DIR)


verification/generated:
> mkdir -p verification/generated


# Python verification sanity check

check:
> $(PYTHON) -m compileall -q verification
> @echo "[PASS] Python verification syntax"


# Independent architectural reference model

reference: check
> $(PYTHON) verification/reference_model.py

checkers:
> $(PYTHON) -m unittest discover -s verification -p 'test_*.py' -v

upgrade: checkers
> $(PYTHON) verification/run_upgrade.py

upgrade-quick: checkers
> $(PYTHON) verification/run_upgrade.py --quick --random-programs 10 --output build/upgrade-quick

formal:
> $(PYTHON) verification/run_safety.py --depth 6

synth-upgrade:
> $(PYTHON) verification/run_synthesis.py


# RTL unit tests

$(BUILD_DIR)/%_test: tb/%_tb.sv $(RTL) | $(BUILD_DIR)
> $(IVERILOG) $(IVFLAGS) -o $@ $(RTL) $<


unit: $(UNIT_BINS)
> @for name in $(UNIT_NAMES); do \
> 	echo "UNIT TEST: $$name"; \
> 	$(VVP) $(BUILD_DIR)/$${name}_test \
> 		| tee $(BUILD_DIR)/$${name}.log; \
> 	if grep -Eiq '\bFAIL(ED)?\b' $(BUILD_DIR)/$${name}.log; then \
> 		echo "[FAIL] $$name"; \
> 		exit 1; \
> 	fi; \
> 	echo "[PASS] $$name"; \
> 	echo; \
> done


# Integrated CPU regression

$(BUILD_DIR)/cpu_core_test: tb/cpu_core_tb.sv $(RTL) | $(BUILD_DIR)
> $(IVERILOG) $(IVFLAGS) -o $@ $(RTL) $<


regression: $(BUILD_DIR)/cpu_core_test
> @echo "CPU INTEGRATION REGRESSION"
> $(VVP) $(BUILD_DIR)/cpu_core_test \
> 	| tee $(BUILD_DIR)/cpu_core.log
> @if grep -Eiq '\bFAIL(ED)?\b' $(BUILD_DIR)/cpu_core.log; then \
> 	echo "[FAIL] CPU regression"; \
> 	exit 1; \
> fi
> @echo "[PASS] CPU regression"


# Randomized differential verification
# run_differential.py currently expects ./diff_test

diff_test: tb/differential_tb.sv $(RTL) | verification/generated
> $(IVERILOG) $(IVFLAGS) -o diff_test $(RTL) tb/differential_tb.sv


differential: diff_test
> @echo "========================================"
> @echo "RANDOMIZED DIFFERENTIAL VERIFICATION"
> @echo "========================================"
> $(PYTHON) verification/run_differential.py


# Complete functional verification

test: reference checkers unit regression differential
> @echo
> @echo "========================================"
> @echo "TINYRV32 FUNCTIONAL VERIFICATION PASSED"
> @echo "========================================"

versions:
> ./scripts/collect_versions.sh
> @cat reproducibility/tool_versions.txt

physical:
> ./physical/scripts/run_orfs.sh

report-manifest:
> ./physical/scripts/update_report_manifest.sh

# Cleanup

clean:
> rm -rf $(BUILD_DIR)
> rm -f diff_test cpu_test
> rm -f *.vcd *.fst *.lxt
> rm -f verification/generated/*
> @echo "Generated simulation artifacts removed."
