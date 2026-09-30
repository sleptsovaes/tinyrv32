export PLATFORM = sky130hd
export DESIGN_NAME = cpu_core

export VERILOG_FILES = $(sort $(wildcard ./designs/src/tinyrv32/*.sv))

export SDC_FILE = ./designs/sky130hd/tinyrv32/constraint.sdc

export CORE_UTILIZATION = 35
export CORE_ASPECT_RATIO = 1
export CORE_MARGIN = 2
export PLACE_DENSITY = 0.60
