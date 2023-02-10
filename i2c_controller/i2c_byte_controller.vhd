library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_byte_controller is
	port (
			--system clock and reset
			i_clk : in std_ulogic;
			i_arstn : in std_ulogic;

			--processor (parallel) bus
			i_start : in std_ulogic;
			i_rd : in std_ulogic;
			i_wr : in std_ulogic;
			i_stop : in std_ulogic;
			i_scl_cycles : in std_ulogic_vector(15 downto 0);
			i_ack : in std_ulogic;
			i_data : in std_ulogic_vector(7 downto 0);
			o_data : out std_ulogic_vector(7 downto 0);

			i_al : in std_ulogic;
			o_msg_done : out std_ulogic;
			o_ack : out std_ulogic;

			i_cmd_done : in std_ulogic;
			i_rx : in std_ulogic;
			o_tx : out std_ulogic;
			o_cmd : out std_ulogic_vector(3 downto 0));
end i2c_byte_controller;

architecture rtl of i2c_byte_controller is
	constant CMD_NOP : std_ulogic_vector(3 downto 0) := "0000";
	constant CMD_START : std_ulogic_vector(3 downto 0) := "0001";
	constant CMD_STOP : std_ulogic_vector(3 downto 0) := "0010";
	constant CMD_WRITE : std_ulogic_vector(3 downto 0) := "0100";
	constant CMD_READ : std_ulogic_vector(3 downto 0) := "1000";

	type t_state is (IDLE,START,STOP,READ,WRITE,ACK);
	signal w_state : t_state;

	signal w_sr : std_ulogic_vector(i_data'range);
	signal w_load : std_ulogic;
	signal w_shift : std_ulogic;

	signal w_cnt : unsigned(2 downto 0);
	signal w_cnt_done : std_ulogic;

begin
	manage_data_flow_proc : process(i_clk,i_arstn) is
	begin
		if(i_arstn = '0') then
			w_sr <= (others => '0');
		elsif (rising_edge(i_clk)) then
			if(w_load = '1') then
				w_sr <= i_data;
			elsif (w_shift = '1') then
				w_sr <= w_sr(w_sr'high-1 downto 0) & i_rx;
			end if;
		end if;
	end process; -- manage_data_flow_proc

	o_data <= w_sr;

	--count progress of read/write commands
	cnt_progr : process(i_clk,i_arstn) is
	begin
		if(i_arstn = '0') then
			w_cnt <= (others => '0');
		elsif (rising_edge(i_clk)) then
			if(w_load = '1') then
				w_cnt <= (others => '1');
			elsif (w_shift ='1') then
				w_cnt <= w_cnt -1;
			end if;
		end if;
	end process; -- cnt_progr

	w_cnt_done <= '1' when (w_cnt =0) else '0';

	byte_ctrl_FSM : process(i_clk,i_arstn) is
	begin
		if(i_arstn = '0') then
			w_state <= IDLE;
			o_cmd <= CMD_NOP;
			w_load <= '0';
			w_shift <= '0';
			o_tx <= '0';
			o_msg_done <= '0';
			o_ack <= '0';
		elsif(rising_edge(i_clk)) then
			if(i_al = '1') then
				w_state <= IDLE;
				o_cmd <= CMD_NOP;
				w_load <= '0';
				w_shift <= '0';
				o_tx <= '0';
				o_msg_done <= '0';
				o_ack <= '0';	
			else
				o_tx <= w_sr(w_sr'high);
				w_load <= '0';
				w_shift <= '0';
				o_msg_done <= '0';
				case w_state is 
					when IDLE =>
						if(i_start = '1') then
							w_state <= START;
							o_cmd <= CMD_START;
						elsif(i_rd = '1') then
							w_state <= READ;
							o_cmd <= CMD_READ;
						elsif(i_wr = '1') then
							w_state <= WRITE;
							o_cmd <= CMD_WRITE;
						end if;
						w_load <= '1';
					when START =>
						if(i_cmd_done = '1') then
							if(i_rd = '1') then
								w_state <= READ;
								o_cmd <= CMD_READ;
							else
								w_state <= WRITE;
								o_cmd <= CMD_WRITE;
							end if;
							w_load <= '1';
						end if;
					when WRITE =>
						if(i_cmd_done = '1') then
							if(w_cnt_done) then
								w_state <= ACK;
								o_cmd <= CMD_READ;
							else
								w_shift <= '1';
							end if;
						end if;
					when READ =>
						if(i_cmd_done = '1') then
							if(w_cnt_done = '1') then
								w_state <= ACK;
								o_cmd <= CMD_WRITE;
							else
								w_shift <= '1';
							end if;
							w_shift <= '1';
							o_tx <= i_ack;
						end if;
					when ACK =>
						if(i_cmd_done = '1') then
							if(i_stop = '1') then
								w_state <= STOP;
								o_cmd <= CMD_STOP;
							else
								w_state <= IDLE;
								o_cmd <= CMD_NOP;
								o_msg_done <= '1';
							end if;
							o_ack <= i_rx;
							o_tx <= '1';
						end if;
					when STOP =>
						if(i_cmd_done = '1') then
							w_state <= IDLE;
							o_cmd <= CMD_NOP;
							o_msg_done <= '1';
						end if;
					when others =>
						null;
				end case;
			end if;
		end if;
	end process; -- byte_ctrl_FSM
end rtl;