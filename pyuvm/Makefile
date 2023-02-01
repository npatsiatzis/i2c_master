# Makefile

# defaults
SIM ?= ghdl
TOPLEVEL_LANG ?= vhdl
EXTRA_ARGS += --std=08
SIM_ARGS += --wave=wave.ghw

VHDL_SOURCES += $(PWD)/f_i2c_master.vhd
# use VHDL_SOURCES for VHDL files

# TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
# MODULE is the basename of the Python test file

#PYTHPNPATH is an environment variable that can be set to additional directories
#where python will look for modules and packages
export PYTHONPATH := $(PWD)/model:$(PYTHONPATH)

test:
		rm -rf sim_build
		$(MAKE) sim MODULE=testbench_i2c_master TOPLEVEL=f_i2c_master

formal :
		sby --yosys "yosys -m ghdl" -f i2c_master.sby
# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim