library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_controller_axi is
	generic(
		C_S_AXI_DATA_WIDTH : natural := 32;
		C_S_AXI_ADDR_WIDTH : natural :=4);
	port (
		--AXI4-Lite interface
		S_AXI_ACLK : in std_ulogic;
		S_AXI_ARESETN : in std_ulogic;
		--
		S_AXI_AWVALID : in std_ulogic;
		S_AXI_AWREADY : out std_ulogic;
		S_AXI_AWADDR : in std_ulogic_vector(C_S_AXI_ADDR_WIDTH -1 downto 0);
		S_AXI_AWPROT : in std_ulogic_vector(2 downto 0);
		--
		S_AXI_WVALID : in std_ulogic;
		S_AXI_WREADY : out std_ulogic;
		S_AXI_WDATA : in std_ulogic_vector(C_S_AXI_DATA_WIDTH -1 downto 0);
		S_AXI_WSTRB : in std_ulogic_vector(C_S_AXI_DATA_WIDTH/8 -1 downto 0);
		--
		S_AXI_BVALID : out std_ulogic;
		S_AXI_BREADY : in std_ulogic;
		S_AXI_BRESP : out std_ulogic_vector(1 downto 0);
		--
		S_AXI_ARVALID : in std_ulogic;
		S_AXI_ARREADY : out std_ulogic;
		S_AXI_ARADDR : in std_ulogic_vector(C_S_AXI_ADDR_WIDTH -1 downto 0);
		S_AXI_ARPROT : in std_ulogic_vector(2 downto 0);
		--
		S_AXI_RVALID : out std_ulogic;
		S_AXI_RREADY : in std_ulogic;
		S_AXI_RDATA : out std_ulogic_vector(C_S_AXI_DATA_WIDTH -1 downto 0);
		S_AXI_RRESP : out std_ulogic_vector(1 downto 0);


		o_data : out std_ulogic_vector(7 downto 0);

		--i2c bus
		io_scl : inout std_ulogic;
		f_sda : in std_ulogic;
		io_sda : inout std_ulogic);
end i2c_controller_axi;

architecture rtl of i2c_controller_axi is
	signal i_arstn, i_arst : std_ulogic;
	alias i_clk  : std_ulogic is S_AXI_ACLK;

	signal w_tx, w_rx : std_ulogic;
	signal w_clk_cycles : std_ulogic_vector(15 downto 0);
	signal w_txr, w_cr, w_ctr : std_ulogic_vector(7 downto 0);
	signal w_rd_data : std_ulogic_vector(7 downto 0);
	signal w_start, w_stop, w_rd, w_wr, w_ack_cr : std_ulogic;
	signal w_en : std_ulogic;
	signal w_cmd_done : std_ulogic;
	signal w_al, w_busy : std_ulogic;
	signal w_msg_done, w_ack, w_tip : std_ulogic;
	signal w_cmd : std_ulogic_vector(3 downto 0);
	signal w_sda, w_scl : std_ulogic;
	signal w_scl_en_n, w_sda_en_n : std_ulogic;

	signal f_in_transaction : std_ulogic;
	signal f_is_data_to_tx : std_ulogic;
begin

	i_arst <= not S_AXI_ARESETN;
	i_arstn <= S_AXI_ARESETN;

	w_start <= w_cr(7);
	w_stop <= w_cr(6);
	w_rd <= w_cr(5);
	w_wr <= w_cr(4);
	w_ack_cr <= w_cr(3);

	w_en <= w_ctr(7);

	f_in_transaction <= w_cr(5) or w_cr(4);
	f_is_data_to_tx <= '1' when (S_AXI_WVALID = '1' and S_AXI_AWVALID = '1' and unsigned(S_AXI_AWADDR) > 15 ) else '0';
	--f_is_data_to_tx <= '1' when(i_we = '1' and i_stb = '1' and  i_addr  = "011" and unsigned(i_data) > 15) else '0';

	i2c_byte_controller : entity work.i2c_byte_controller(rtl)
	port map(
		i_clk =>i_clk,
		i_arstn =>i_arstn,
		i_start =>w_start,
		i_rd =>w_rd,
		i_wr =>	w_wr,
		i_stop =>w_stop,
		i_ack =>w_ack_cr,
		i_data =>w_txr,
		o_data =>w_rd_data,

		i_al =>w_al,
		o_msg_done =>w_msg_done,
		o_tip => w_tip,
		o_ack =>w_ack,

		i_cmd_done =>w_cmd_done,
		i_rx =>w_rx,
		o_tx  =>w_tx,
		o_cmd =>w_cmd);

	i2c_bit_controller : entity work.i2c_bit_controller(rtl)
	port map(
		i_clk =>i_clk,
		i_arstn =>i_arstn,

		i_rx =>w_tx,
		o_tx =>w_rx,
		i_scl_cycles =>w_clk_cycles,	
		i_en =>w_en,
		i_cmd =>w_cmd,
		o_cmd_done =>w_cmd_done,
		o_busy  =>w_busy,
		o_al  =>w_al,

		--i2c bus
		i_scl =>io_scl,
		i_sda =>f_sda,
		o_scl  =>w_scl,
		o_sda  =>w_sda,
		o_scl_en_n  =>w_scl_en_n,
		o_sda_en_n =>w_sda_en_n);

	axil_regs : entity work.axil_regs(rtl)
	port map(
		i_clk =>i_clk,
		i_arst =>i_arst,

		S_AXI_AWVALID => S_AXI_AWVALID,
		S_AXI_AWREADY => S_AXI_AWREADY,
		S_AXI_AWADDR => S_AXI_AWADDR,
		S_AXI_AWPROT => S_AXI_AWPROT,
		--
		S_AXI_WVALID => S_AXI_WVALID,
		S_AXI_WREADY => S_AXI_WREADY,
		S_AXI_WDATA => S_AXI_WDATA,
		S_AXI_WSTRB => S_AXI_WSTRB,
		--
		S_AXI_BVALID => S_AXI_BVALID,
		S_AXI_BREADY => S_AXI_BREADY,
		S_AXI_BRESP => S_AXI_BRESP,
		--
		S_AXI_ARVALID => S_AXI_ARVALID,
		S_AXI_ARREADY => S_AXI_ARREADY,
		S_AXI_ARADDR => S_AXI_ARADDR,
		S_AXI_ARPROT => S_AXI_ARPROT,
		--
		S_AXI_RVALID => S_AXI_RVALID,
		S_AXI_RREADY => S_AXI_RREADY,
		S_AXI_RDATA => S_AXI_RDATA,
		S_AXI_RRESP => S_AXI_RRESP,

		i_i2c_rd_data => w_rd_data,
		
		o_scl_cycles =>w_clk_cycles,
		o_txr =>w_txr,
		o_ctr =>w_ctr,
		o_cr => w_cr);


	o_data <= S_AXI_RDATA(7 downto 0);

	--drive to 1 to avoid issues with cocotb simulation
	io_scl <= w_scl when (w_scl_en_n = '0') else '1';
	io_sda <= w_sda when (w_sda_en_n = '0') else '1';

	--because I2C is open-drain, scl and sda can basically be driven by a 
	--tri-state buffer with (scl/sda)_en_n as a control input and '0' as a data input.
	--the output of each of these buffers is scl/sda respectively.
	--io_scl <= w_scl when (w_scl_en_n = '0') else 'Z';
	--io_sda <= w_sda when (w_sda_en_n = '0') else 'Z';
end rtl;
