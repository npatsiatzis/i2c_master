library ieee;
use ieee.std_logic_1164.all;

entity i2c_controller is
	port (
			--system clock and reset
			i_clk : in std_ulogic;
			i_arstn : in std_ulogic;

			--cpu (parallel) bus
			i_we : in std_ulogic;
			i_addr : in std_ulogic_vector(2 downto 0);
			i_data : in std_ulogic_vector(7 downto 0);
			o_data : out std_ulogic_vector(7 downto 0);

			--i2c bus
			io_scl : inout std_ulogic;
			f_sda : in std_ulogic;
			io_sda : inout std_ulogic);
end i2c_controller;

architecture rtl of i2c_controller is
	signal w_tx, w_rx : std_ulogic;
	signal w_clk_cycles : std_ulogic_vector(15 downto 0);
	signal w_txr, w_cr, w_ctr : std_ulogic_vector(7 downto 0);
	signal w_start, w_stop, w_rd, w_wr, w_ack_cr : std_ulogic;
	signal w_en : std_ulogic;
	signal w_cmd_done : std_ulogic;
	signal w_al, w_busy : std_ulogic;
	signal w_msg_done, w_ack, w_tip : std_ulogic;
	signal w_cmd : std_ulogic_vector(3 downto 0);
	signal w_sda, w_scl : std_ulogic;
	signal w_scl_en_n, w_sda_en_n : std_ulogic;

	signal f_in_transaction : std_ulogic;
begin
	w_start <= w_cr(7);
	w_stop <= w_cr(6);
	w_rd <= w_cr(5);
	w_wr <= w_cr(4);
	w_ack_cr <= w_cr(3);

	w_en <= w_ctr(7);

	f_in_transaction <= w_cr(5) or w_cr(4);

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
		o_data =>o_data,

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

	i2c_registers : entity work.i2c_registers(rtl)
	port map(
		i_clk =>i_clk,
		i_arstn =>i_arstn,
		i_addr =>i_addr,
		i_we =>i_we,
		i_data =>i_data,

		i_busy =>w_busy,
		i_done =>w_msg_done,
		i_al =>w_al,
		i_ack =>w_ack,

		o_scl_cycles =>w_clk_cycles,
		o_txr =>w_txr,
		o_ctr =>w_ctr,
		o_cr => w_cr);

	--drive to 1 to avoid issues with cocotb simulation
	io_scl <= w_scl when (w_scl_en_n = '0') else '1';
	io_sda <= w_sda when (w_sda_en_n = '0') else '1';

	--because I2C is open-drain, scl and sda can basically be driven by a 
	--tri-state buffer with (scl/sda)_en_n as a control input and '0' as a data input.
	--the output of each of these buffers is scl/sda respectively.
	--io_scl <= w_scl when (w_scl_en_n = '0') else 'Z';
	--io_sda <= w_sda when (w_sda_en_n = '0') else 'Z';
end rtl;
