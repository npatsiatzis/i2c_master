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
	global full
	global recv
	while (full != True):
		await RisingEdge(dut.i_clk)
		if(int(dut.i2c_byte_controller.w_cnt.value) >0 and dut.i2c_byte_controller.w_state ==4 and dut.i2c_bit_controller.w_scl.value == 1 and dut.i2c_bit_controller.w_scl_r.value == 0):
			recv_array[int(dut.i2c_byte_controller.w_cnt.value)] = dut.io_sda.value
		elif(int(dut.i2c_byte_controller.w_cnt.value) == 0 and dut.i2c_byte_controller.w_state ==4 and dut.i2c_bit_controller.w_scl.value == 1 and dut.i2c_bit_controller.w_scl_r.value == 0):
			recv_array[0] = dut.io_sda.value
			s = ""
			for i in recv_array:
				s = str(i)+s  				# the order of concatenation is important
			recv = BinaryValue(value=s,binaryRepresentation=0)



async def slave_write_sda(dut,recv_array):
	global full
	while (full != True):
		await RisingEdge(dut.i_clk)
		if(int(dut.i2c_byte_controller.w_cnt.value) >0 and dut.i2c_byte_controller.w_state ==3 and dut.i2c_bit_controller.w_scl.value == 0 and dut.i2c_bit_controller.w_scl_r.value == 0):
			dut.f_sda.value = recv_array[int(dut.i2c_byte_controller.w_cnt.value)]
		elif(int(dut.i2c_byte_controller.w_cnt.value) == 0 and dut.i2c_byte_controller.w_state ==3 and dut.i2c_bit_controller.w_scl.value == 0 and dut.i2c_bit_controller.w_scl_r.value == 0):
			dut.f_sda.value = recv_array[0]
		elif(dut.i2c_byte_controller.w_state !=3):
			dut.f_sda.value = 1

# at_least = value is superfluous, just shows how you can determine the amount of times that
# a bin must be hit to considered covered
@CoverPoint("top.i_data",xf = lambda x : x, bins = list(range(2**4,2**5)), at_least=1)
def number_cover(x):
	covered_valued.append(int(x))

async def reset(dut,cycles=1):
	dut.i_arstn.value = 0
	dut.i_we.value = 0
	dut.i_stb. value = 0 
	dut.i_data.value = 0
	dut.i_addr.value = 0

	await ClockCycles(dut.i_clk,cycles)
	dut.i_arstn.value = 1
	await RisingEdge(dut.i_clk)
	dut._log.info("the core was reset")

@cocotb.test()
async def test_tx(dut):
	"""Check results and coverage for i2c controller transmission and reception"""
	data_rx = [0]*8
	idx = 0

	global recv

	cocotb.start_soon(Clock(dut.i_clk, 10, units="ns").start())
	await reset(dut,5)	
	cocotb.start_soon(slave_read_sda(dut,data_rx))
	cocotb.start_soon(slave_write_sda(dut,data_rx))


	expected_value = 0
	rx_data = 0

	dut.i_addr.value = 0

		# 					REGISTER MAP

	# 			Address 		| 		Functionality
	#			   0 			|	system clock cycles to make scl (lower byte)
	#			   1 			|	system clock cycles to make scl (upper byte)
	#			   2 			|	control transfer register (ctr)
	#			   3 			|	data transfer register (i_we = '1')/ receive i2c data register (i_we = '0') 




	# initialization
	# set the enable bit of control regsiter(ctr)(02) 
	# write the upper and lower part of the value required for the scl period to registers 0 and 1

	# how to write data to slave
	# set slave address and read/write(0) bit to transmit register (txr)(3)
	# set the start and write fields in command register (cr)(4) , make sure the cmd is done(msg_done)
	# set in-slave  memory/register address in txr 
	# set the write bit in command register and wait for the cmd to be done
	# set the data to be transferred in txr 
	# set the write bit in command register and wait for the cmd to be done
	# repeat the last two steps as longs as one wants to transmit data
	
	#how to read data to slave
	# the procedure is simplified here to just issuing a read command by setting the 
	# read bit in command register and sending it over the bus. normally both the slave address
	# and the in-slave register/memory address have to be first exchanged as well.


	dut.i_addr.value = 0
	dut.i_stb.value = 1
	dut.i_we.value = 1
	dut.i_data.value = 20 		#lsbyte of scl clock cycles (e.g Fsys = 100 MHz Fi2c = 1MHz, F = 100/(5*1) = 20)
								#F is the frequency of the clock in i2c_bit_controller that generates scl

	await RisingEdge(dut.i_clk)

	dut.i_addr.value = 1
	dut.i_stb.value = 1
	dut.i_we.value = 1
	dut.i_data.value = 0 				#msbyte of scl clock cycles

	await RisingEdge(dut.i_clk)

	dut.i_addr.value = 2				#enable the core (wen for bit_controller)
	dut.i_stb.value = 1
	dut.i_we.value = 1
	dut.i_data.value = 128  #(x80)

	await RisingEdge(dut.i_clk)

	while(full != True):

		dut.i_addr.value = 3				#write txr
		dut.i_stb.value = 1
		dut.i_we.value =1
		dut.i_data.value = 0 				#7 bit address, '1' (read from slave) / '0' (write to slave)

		await RisingEdge(dut.i_clk)

		dut.i_addr.value = 4
		dut.i_stb.value = 1
		dut.i_we.value = 1
		dut.i_data.value = 144  #(x90) 		#START condition, WRITE condition

		if(idx >0):
			#check that the rx part of the master works correctly 
			await RisingEdge(dut.i2c_byte_controller.o_msg_done) 
			dut.i_addr.value = 3
			dut.i_stb.value = 1
			dut.i_we.value = 0
			await RisingEdge(dut.i_clk)
			await RisingEdge(dut.i_clk)
			assert not (data != dut.o_data.value),"Different expected to actual read data"

		await RisingEdge(dut.w_tip)


		dut.i_addr.value = 3
		dut.i_stb.value = 1
		dut.i_we.value =1
		dut.i_data.value = 0 				# set in-slave register/memory address

		await RisingEdge(dut.i_clk)

		dut.i_addr.value = 4
		dut.i_stb.value = 1
		dut.i_we.value = 1
		dut.i_data.value = 16  #(x10)		#WRITE condition
		await RisingEdge(dut.i_clk)

		# dut.i_stb.value = 0

		#wait for write of address an r/w bit to be done
		await RisingEdge(dut.i2c_byte_controller.o_msg_done) 

		await RisingEdge(dut.w_tip)
		

		# while(full != True):
			
		data = random.randint(2**4,2**5)
		while(data in covered_valued):
			data = random.randint(2**4,2**5)
		dut.i_addr.value = 3
		dut.i_stb.value = 1
		dut.i_we.value =1
		dut.i_data.value = data 		#set data to be written to previosuly provided address

		await RisingEdge(dut.i_clk)

		dut.i_addr.value = 4
		dut.i_stb.value = 1
		dut.i_we.value = 1
		# dut.i_data.value = 16  #(x10) 		#WRITE condition
		dut.i_data.value = 86  #(x50) 		#WRITE condition, STOP condition
		await RisingEdge(dut.i_clk)

		#wait for write of in-slave register/memory address to be done
		await RisingEdge(dut.i2c_byte_controller.o_msg_done)



		await RisingEdge(dut.w_tip)

		dut.i_addr.value = 4
		dut.i_stb.value = 1
		dut.i_we.value = 1
		dut.i_data.value = 224  #(xe0)	#START, READ, STOP conditions
		await RisingEdge(dut.i_clk)
		
		await RisingEdge(dut.i2c_byte_controller.o_msg_done)


		# check that the data received by a trivial i2c receiver logic matches
		# the transmitted data
		assert not (recv.integer != data),"Different expected to actual read data"
		coverage_db["top.i_data"].add_threshold_callback(notify, 100)
		number_cover(data)
		idx +=1


	coverage_db.report_coverage(cocotb.log.info,bins=True)
	coverage_db.export_to_xml(filename="coverage.xml")


