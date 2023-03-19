import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer,RisingEdge,FallingEdge,ClockCycles
from cocotb.result import TestFailure
import random
from cocotb_coverage.coverage import CoverPoint,coverage_db
from cocotb.binary import BinaryValue

covered_valued = []

global recv 

full = False
def notify():
	global full
	full = True

async def slave_read_sda(dut,recv_array):
	# pass
	global full
	global recv
	while (full != True):
		await RisingEdge(dut.i_clk)
		if(int(dut.i2c_byte_controller.w_cnt.value) >0 and dut.i2c_byte_controller.w_state ==4 and dut.i2c_bit_controller.w_scl.value == 1 and dut.i2c_bit_controller.w_scl_r.value == 0):
			recv_array[int(dut.i2c_byte_controller.w_cnt.value)] = dut.io_sda.value
		elif(dut.i2c_byte_controller.w_cnt.value == 0):
			recv_array[0] = dut.io_sda.value
			s = ""
			for i in recv_array:
				s = str(i)+s  				# the order of concatenation is important
			recv = BinaryValue(value=s,binaryRepresentation=0)


async def connect_tx_rx(dut):
	while full != True:
		await RisingEdge(dut.i_clk)
		# dut.f_sda.value = dut.io_sda.value

# at_least = value is superfluous, just shows how you can determine the amount of times that
# a bin must be hit to considered covered
@CoverPoint("top.i_data",xf = lambda x : x, bins = list(range(2**4)), at_least=1)
def number_cover(x):
	covered_valued.append(int(x))

async def reset(dut,cycles=1):
	dut.i_arstn.value = 0
	dut.i_we.value = 0 
	dut.i_data.value = 0
	dut.i_addr.value = 0

	await ClockCycles(dut.i_clk,cycles)
	dut.i_arstn.value = 1
	await RisingEdge(dut.i_clk)
	dut._log.info("the core was reset")

@cocotb.test()
async def test_tx(dut):
	"""Check results and coverage for i2c controller transmission"""
	data_rx = [0]*8

	global recv

	cocotb.start_soon(Clock(dut.i_clk, 10, units="ns").start())
	await reset(dut,5)	
	cocotb.start_soon(connect_tx_rx(dut))
	cocotb.start_soon(slave_read_sda(dut,data_rx))


	expected_value = 0
	rx_data = 0

	dut.i_addr.value = 0

	# initialization
	# set the enable bit of control regsiter(ctr)(02) 
	# write the upper and lower part of the value required for the scl period to registers 0 and 1

	# how to write data to slave
	# set slave address and read/write(0) bit to transmit register (txr)(3)
	# set the start and write fields in command register (cr)(4) , make sure the cmd is done(msg_done)
	# set slave address in txr 
	# set the write bit in command register and wait for the cmd to be done
	# set the data to be transferred in txr 
	# set the write bit in command register and wait for the cmd to be done
	# repeat the last two steps as longs as one wants to transmit data
	



	# configure UART core via interface
	# set databits(8), stopbits(1), parity_en(1), parity_type etc..

	dut.i_addr.value = 0
	dut.i_we.value = 1
	dut.i_data.value = 10 		#lsbyte of scl clock cycles

	await RisingEdge(dut.i_clk)

	dut.i_addr.value = 1
	dut.i_we.value = 1
	dut.i_data.value = 0 		#msbyte of scl clock cycles

	await RisingEdge(dut.i_clk)

	dut.i_addr.value = 2
	dut.i_we.value = 1
	dut.i_data.value = 128  #(x80)

	await RisingEdge(dut.i_clk)

	dut.i_addr.value = 3
	dut.i_we.value =1
	dut.i_data.value = 1

	await RisingEdge(dut.i_clk)

	dut.i_addr.value = 4
	dut.i_we.value = 1
	dut.i_data.value = 144  #(x90)

	await RisingEdge(dut.i2c_byte_controller.o_msg_done)

	dut.i_addr.value = 3
	dut.i_we.value =1
	dut.i_data.value = 0

	await RisingEdge(dut.i_clk)

	dut.i_addr.value = 4
	dut.i_we.value = 1
	dut.i_data.value = 16  #(x10)
	
	await RisingEdge(dut.i2c_byte_controller.o_msg_done)

	while(full != True):
		data = random.randint(0,2**4-1)
		while(data in covered_valued):
			data = random.randint(0,2**4-1)
		dut.i_addr.value = 3
		dut.i_we.value =1
		dut.i_data.value = data

		await RisingEdge(dut.i_clk)

		dut.i_addr.value = 4
		dut.i_we.value = 1
		dut.i_data.value = 16  #(x10)

		await RisingEdge(dut.i2c_byte_controller.o_msg_done)
		# check that the data received by a trivial i2c receiver logic matches
		# the transmitted data
		assert not (recv.integer != data),"Different expected to actual read data"
		coverage_db["top.i_data"].add_threshold_callback(notify, 100)
		number_cover(data)
		

	coverage_db.report_coverage(cocotb.log.info,bins=True)
	coverage_db.export_to_xml(filename="coverage.xml")


