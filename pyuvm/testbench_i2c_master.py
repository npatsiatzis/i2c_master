from cocotb.triggers import RisingEdge,FallingEdge
from cocotb_coverage import crv
from cocotb.clock import Clock
from pyuvm import *
import random
import cocotb
import pyuvm
from utils import i2c_Bfm
from cocotb_coverage.coverage import CoverPoint,coverage_db
from cocotb.binary import BinaryValue

g_sys_clk = int(cocotb.top.g_sys_clk)
period_ns = 10**9 / g_sys_clk
covered_values = []


full = False
def notify():
    global full
    full = True

# at_least = value is superfluous, just shows how you can determine the amount of times that
# a bin must be hit to considered covered
@CoverPoint("top.i_tx_data",xf = lambda x : x, bins = list(range(2**8)), at_least=1)
def number_cover(x):
    pass


class crv_inputs(crv.Randomized):
    def __init__(self,tx_data):
        crv.Randomized.__init__(self)
        self.tx_data = tx_data
        self.add_rand("tx_data",list(range(2**8)))

# Sequence classes
class SeqItem(uvm_sequence_item):

    def __init__(self, name, i_en,rw,i_tx_data):
        super().__init__(name)
        self. i_en = i_en
        self.rw = rw
        self.i_crv = crv_inputs(i_tx_data)

    def randomize_operands(self):
        self.i_en = 1
        self.rw = 0
        self.i_crv.randomize()

    def randomize(self):
        self.randomize_operands()


class RandomSeq(uvm_sequence):

    async def body(self):
        while(len(covered_values) != 2**8):
            data_tr = SeqItem("data_tr", None,None,None)
            await self.start_item(data_tr)
            data_tr.randomize_operands()
            while((data_tr.i_crv.tx_data) in covered_values):
                data_tr.randomize_operands()
            covered_values.append((data_tr.i_crv.tx_data))
            await self.finish_item(data_tr)
            # change tx data before moving on to the ready state again, so as no to "lose" any cycles
            await RisingEdge(cocotb.top.f_read_done)
            # await FallingEdge(cocotb.top.o_busy)

class TestAllSeq(uvm_sequence):

    async def body(self):
        seqr = ConfigDB().get(None, "", "SEQR")
        random = RandomSeq("random")
        await random.start(seqr)

class Driver(uvm_driver):
    def build_phase(self):
        self.ap = uvm_analysis_port("ap", self)

    def start_of_simulation_phase(self):
        self.bfm = i2c_Bfm()

    async def launch_tb(self):
        await self.bfm.reset()
        self.bfm.start_bfm()

    async def run_phase(self):
        await self.launch_tb()
        while True:
            data = await self.seq_item_port.get_next_item()
            await self.bfm.send_data((data.i_en,data.rw,data.i_crv.tx_data))
            result = await self.bfm.get_result()
            self.ap.write(result)
            data.result = result
            self.seq_item_port.item_done()


class Coverage(uvm_subscriber):

    def end_of_elaboration_phase(self):
        self.cvg = set()

    def write(self, data):
        (i_en,i_rw,i_tx_data) = data
        number_cover(i_tx_data)
        if(int(i_tx_data) not in self.cvg):
            self.cvg.add(int(i_tx_data))

    def report_phase(self):
        try:
            disable_errors = ConfigDB().get(
                self, "", "DISABLE_COVERAGE_ERRORS")
        except UVMConfigItemNotFound:
            disable_errors = False
        if not disable_errors:
            if len(set(covered_values) - self.cvg) > 0:
                self.logger.error(
                    f"Functional coverage error. Missed: {set(covered_values)-self.cvg}")   
                assert False
            else:
                self.logger.info("Covered all input space")
                assert True


class Scoreboard(uvm_component):

    def build_phase(self):
        self.data_fifo = uvm_tlm_analysis_fifo("data_fifo", self)
        self.result_fifo = uvm_tlm_analysis_fifo("result_fifo", self)
        self.data_get_port = uvm_get_port("data_get_port", self)
        self.result_get_port = uvm_get_port("result_get_port", self)
        self.data_export = self.data_fifo.analysis_export
        self.result_export = self.result_fifo.analysis_export

    def connect_phase(self):
        self.data_get_port.connect(self.data_fifo.get_export)
        self.result_get_port.connect(self.result_fifo.get_export)

    def check_phase(self):
        passed = True
        rx_data = 0
        tx_data = 0
        try:
            self.errors = ConfigDB().get(self, "", "CREATE_ERRORS")
        except UVMConfigItemNotFound:
            self.errors = False
        while self.result_get_port.can_get():
            _, actual_result = self.result_get_port.try_get()
            data_success, data = self.data_get_port.try_get()
            if not data_success:
                self.logger.critical(f"result {actual_result} had no command")
            else:
                (i_en,i_rw,i_tx_data) = data
                old_rx_data = rx_data
                old_tx_data = tx_data

                rx_data = actual_result
                tx_data = i_tx_data

                # when new data are read at the same cycle the new tx data are set.
                # look at tx data of prev cycle to see if rx dat are correct
                if(old_rx_data != rx_data):
                    if int(old_tx_data) == int(actual_result):
                        self.logger.info("PASSED:")
                    else:
                        self.logger.error("FAILED:")

                        passed = False
        assert passed


class Monitor(uvm_component):
    def __init__(self, name, parent, method_name):
        super().__init__(name, parent)
        self.method_name = method_name

    def build_phase(self):
        self.ap = uvm_analysis_port("ap", self)
        self.bfm = i2c_Bfm()
        self.get_method = getattr(self.bfm, self.method_name)

    async def run_phase(self):
        while True:
            datum = await self.get_method()
            self.logger.debug(f"MONITORED {datum}")
            self.ap.write(datum)


class Env(uvm_env):

    def build_phase(self):
        self.seqr = uvm_sequencer("seqr", self)
        ConfigDB().set(None, "*", "SEQR", self.seqr)
        self.driver = Driver.create("driver", self)
        self.data_mon = Monitor("data_mon", self, "get_data")
        self.coverage = Coverage("coverage", self)
        self.scoreboard = Scoreboard("scoreboard", self)

    def connect_phase(self):
        self.driver.seq_item_port.connect(self.seqr.seq_item_export)
        self.data_mon.ap.connect(self.scoreboard.data_export)
        self.data_mon.ap.connect(self.coverage.analysis_export)
        self.driver.ap.connect(self.scoreboard.result_export)


@pyuvm.test()
class Test(uvm_test):
    """Test i2c rx-tx loopback with random values"""

    def build_phase(self):
        self.env = Env("env", self)
        self.bfm = i2c_Bfm()

    def end_of_elaboration_phase(self):
        self.test_all = TestAllSeq.create("test_all")

    async def run_phase(self):
        self.raise_objection()
        cocotb.start_soon(Clock(self.bfm.dut.i_clk, period_ns, units="ns").start())
        await self.test_all.start()

        coverage_db.report_coverage(cocotb.log.info,bins=True)
        coverage_db.export_to_xml(filename="coverage.xml")
        self.drop_objection()
