# Makefile

# defaults
SIM ?= ghdl
TOPLEVEL_LANG ?= vhdl
EXTRA_ARGS += --std=08
SIM_ARGS += --wave=wave.ghw

VHDL_SOURCES += $(PWD)/../rtl/axil_regs.vhd
VHDL_SOURCES += $(PWD)/../rtl/i2c_registers.vhd
VHDL_SOURCES += $(PWD)/../rtl/i2c_bit_controller.vhd
VHDL_SOURCES += $(PWD)/../rtl/i2c_byte_controller.vhd
VHDL_SOURCES += $(PWD)/../rtl/i2c_controller.vhd
VHDL_SOURCES += $(PWD)/../rtl/i2c_controller_axi.vhd
# use VHDL_SOURCES for VHDL files

# TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
# MODULE is the basename of the Python test file

test:
		rm -rf sim_build
		$(MAKE) sim MODULE=testbench TOPLEVEL=i2c_controller
		
test_axi:
		rm -rf sim_build
		$(MAKE) sim MODULE=testbench_axi TOPLEVEL=i2c_controller_axi
# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim