
from cocotb.triggers import Timer,RisingEdge,FallingEdge,ClockCycles
from cocotb.clock import Clock
from cocotb.queue import QueueEmpty, Queue
import cocotb
import enum
import random
from cocotb_coverage import crv 
from cocotb_coverage.coverage import CoverCross,CoverPoint,coverage_db
from pyuvm import utility_classes



class I2cBfm(metaclass=utility_classes.Singleton):
    def __init__(self):
        self.dut = cocotb.top
        self.driver_queue = Queue(maxsize=1)
        self.data_mon_queue = Queue(maxsize=0)
        self.result_mon_queue = Queue(maxsize=0)

    async def send_data(self, data):
        await self.driver_queue.put(data)

    async def get_data(self):
        data = await self.data_mon_queue.get()
        return data

    async def get_result(self):
        result = await self.result_mon_queue.get()
        return result

    async def reset(self):
        await RisingEdge(self.dut.i_clk)
        self.dut.i_arstn.value = 0
        self.dut.i_we.value = 0 
        self.dut.i_stb.value = 0
        self.dut.i_data.value = 0
        self.dut.i_addr.value = 0
        await ClockCycles(self.dut.i_clk,5)
        self.dut.i_arstn.value = 1


    async def driver_bfm(self):
        while True:
            await RisingEdge(self.dut.i_clk)
            self.dut.f_sda.value = self.dut.io_sda.value
            try:
                (i_we,i_stb,i_addr,i_data) = self.driver_queue.get_nowait()
                self.dut.i_we.value = i_we
                self.dut.i_stb.value = i_stb
                self.dut.i_addr.value = i_addr
                self.dut.i_data.value = i_data

            except QueueEmpty:
                pass

    async def data_mon_bfm(self):
        while True:
            # await RisingEdge(self.dut.o_tx_ready)
            # await RisingEdge(self.dut.i_addr == 3)
            await RisingEdge(self.dut.f_is_data_to_tx)
            i_data = self.dut.i_data.value 

            self.data_mon_queue.put_nowait(i_data)


    async def result_mon_bfm(self):
        while True:
            # await RisingEdge(self.dut.o_rx_ready)
            await RisingEdge(self.dut.f_is_data_to_tx)
            await FallingEdge(self.dut.i2c_byte_controller.o_msg_done)
            await RisingEdge(self.dut.i_clk)
            await RisingEdge(self.dut.i_clk)
            await RisingEdge(self.dut.i_clk)
            self.result_mon_queue.put_nowait(self.dut.o_data.value)


    def start_bfm(self):
        cocotb.start_soon(self.driver_bfm())
        cocotb.start_soon(self.data_mon_bfm())
        cocotb.start_soon(self.result_mon_bfm())