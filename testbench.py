# Functional test for spi_master
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer,RisingEdge,FallingEdge,ClockCycles
from cocotb.result import TestFailure
import random
from cocotb_coverage.coverage import CoverCross,CoverPoint,coverage_db
from cocotb_coverage import crv 

g_sys_clk = int(cocotb.top.g_sys_clk)
period_ns = 10**9 / g_sys_clk

class crv_inputs(crv.Randomized):
	def __init__(self,data):
		crv.Randomized.__init__(self)
		self.data = data
		self.add_rand("data",list(range(2**8)))


covered_value = []

full = False
# #Callback function to capture the bin content showing
def notify_full():
	global full
	full = True

# at_least = value is superfluous, just shows how you can determine the amount of times that
# a bin must be hit to considered covered
# actually the bins must go up to 2**8 and also add other coverage criteria regarding other features
# here i just exercize the basic functionality
@CoverPoint("top.o_data",xf = lambda x : x.o_data.value, bins = list(range(2**4)), at_least=1)
def number_cover(dut):
	covered_value.append(dut.o_data.value)

async def reset(dut,cycles=1):
	dut.i_arst_n.value = 0

	dut.i_ena.value = 0 
	dut.i_data.value = 0
	dut.i_rw.value = 0
	dut.i_addr.value = 0
	await ClockCycles(dut.i_clk,cycles)
	dut.i_arst_n.value = 1
	await RisingEdge(dut.i_clk)
	dut._log.info("the core was reset")

@cocotb.test()
async def test(dut):
	"""Check results and coverage for spi_master"""

	cocotb.start_soon(Clock(dut.i_clk, period_ns, units="ns").start())
	await reset(dut,5)	
	
	data_to_tx = 0
	data_rx = [0]*8
	sda = 0

	expected_value = 0
	rx_data = 0

	inputs = crv_inputs(0)
	inputs.randomize()


	dut.i_rw.value = 0
	dut.i_addr.value = 0
	dut.i_ena.value = 1
	dut.i_data.value = inputs.data

	dut.i_sda.value = sda
	expected_value = inputs.data

	# for i in range(1000):
	while(full != True):
		await RisingEdge(dut.i_clk)
		dut.i_sda.value = sda

		if(dut.r_data_clk.value == 1 and dut.r_data_clk_prev.value == 0):
			if(dut.state.value == 0):
				if(dut.i_ena.value == 1 and dut.i_rw.value == 0):
					data_to_tx = dut.i_data.value
			elif (dut.state.value == 6):
				if(dut.i_ena.value == 1):
					data_to_tx = dut.i_data.value
			elif (dut.state.value == 7):
				if(dut.i_ena.value == 1 and dut.i_rw.value == 0):
					data_to_tx = dut.i_data.value


		if(dut.io_sclk.value == 0 and dut.io_sclk_prev.value == 1):
			if(dut.state.value == 4):
				data_rx[dut.cnt_bits.value +1] = dut.r_sda.value
			if(dut.state.value == 6 and dut.cnt_bits.value == 7):
				data_rx[0] = dut.r_sda.value
				dut.i_ena.value = 0
				dut.i_rw.value = 1

			if(dut.state.value == 8):
				dut.i_ena.value = 1
		if(dut.io_sclk.value == 1 and dut.io_sclk_prev.value == 0):
			if(dut.state.value == 5):
				sda = data_rx[dut.cnt_bits.value.value]
				if(dut.cnt_bits.value ==0):
					dut.i_ena.value = 0
			if(dut.state.value == 8):
				dut.i_ena.value = 1
			if(dut.state.value == 7):
				dut.i_rw.value = 0
				assert not (expected_value != int(dut.o_data.value)),"Different expected to actual read data"
				number_cover(dut)
				coverage_db["top.o_data"].add_threshold_callback(notify_full, 100)
				inputs.randomize()
				while(inputs.data in covered_value):
					inputs.randomize()
				dut.i_data.value = inputs.data
				expected_value = inputs.data

	coverage_db.report_coverage(cocotb.log.info,bins=True)
	coverage_db.export_to_xml(filename="coverage.xml")

		
