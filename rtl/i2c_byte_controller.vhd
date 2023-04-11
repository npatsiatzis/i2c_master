--module that manages i2c transactions/messages (message = byte-level operation on the bus). 
--each transaction may consist of one or more mesages 
--(multiple messages possible when one wants to perform the same operation
--on the same address). This module receives from the host interface the type of message and 
--transaction and breaks down the message in "symbols" which are then 
--implemeneted by a module that works on bit level on the i2c bus (i2c_bit_controller).

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
			i_ack : in std_ulogic;
			i_data : in std_ulogic_vector(7 downto 0);
			o_data : out std_ulogic_vector(7 downto 0);

			i_al : in std_ulogic;
			o_msg_done : out std_ulogic;
			o_tip : out std_ulogic;
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

	signal r_start, r_stop, r_read, r_write : std_ulogic;
	signal w_start, w_stop, w_read, w_write : std_ulogic;

	signal f_wr_done : std_ulogic;

begin

	reg_control_signals : process(i_clk,i_arstn) is
	begin
		if(i_arstn = '0') then
			r_start <= '0'; 
			r_stop <= '0';
			r_read <= '0';
			r_write <= '0';
		elsif (rising_edge(i_clk)) then
			r_start <= i_start;
			r_stop <= i_stop;
			r_read <= i_rd;
			r_write <= i_wr;
		end if;
	end process; -- reg_control_signals

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

	-- byte_ctrl_FSM describes the procedure for a master to acess a slave device
	--1) if master wants to SEND data to slave (master transmitter)
		--master sends START symbol/condition and address w. write flag to bus 
		--master sends data to bus
		--master terminates the transaction (possibly after multiple data messages) with STOP symbol

		--fsm paths:
			--IDLE->START->WRITE->ACK->STOP
			--IDLE->START->WRITE->ACK->IDLE->(REPEATED) START->......->STOP
	--2) if masster wants to RECEIVE data from slave (master receiver)
		--master sends START symbol/condition and address w. read flag to bus 
		--(master sends the register/address to read from)
		--master reads data from the bus
		--master terminates the transaction with STOP symbol

		--fsm paths:
			--IDLE->START->READ->ACK->STOP
			--IDLE->START->READ->ACK->IDLE->(REPEATED) START->......->STOP
			
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
			o_tip <= '0';
			f_wr_done <= '0';
		elsif(rising_edge(i_clk)) then
			if(i_al = '1') then
				w_state <= IDLE;
				o_cmd <= CMD_NOP;
				w_load <= '0';
				w_shift <= '0';
				o_tx <= '0';
				o_msg_done <= '0';
				o_tip <= '0';
				o_ack <= '0';	

				f_wr_done <= '0';
			else
				o_tx <= w_sr(w_sr'high);
				w_load <= '0';
				w_shift <= '0';
				o_msg_done <= '0';

				f_wr_done <= '0';
				case w_state is 
					when IDLE =>
						if(w_start = '1') then
							w_state <= START;
							o_cmd <= CMD_START;
							o_tip <= '1';
						elsif(w_read = '1') then
							w_state <= READ;
							o_cmd <= CMD_READ;
							o_tip <= '1';
						elsif(w_write = '1') then
							w_state <= WRITE;
							o_cmd <= CMD_WRITE;
							o_tip <= '1';
						else
							w_start <= r_start;
							w_stop <= r_stop;
							w_read <= r_read;
							w_write <= r_write;
						end if;
						w_load <= '1';
					when START =>
						if(i_cmd_done = '1') then
							if(w_read = '1') then
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
								f_wr_done <= '1';
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
							if(w_stop = '1') then
								w_state <= STOP;
								o_cmd <= CMD_STOP;
							else
							--repeated start condition
								w_state <= IDLE;
								o_cmd <= CMD_NOP;
								o_msg_done <= '1';
								o_tip <= '0';

								w_start <= r_start;
								w_stop <= r_stop;
								w_read <= r_read;
								w_write <= r_write;
							end if;
							o_ack <= i_rx;
							o_tx <= '1';
						end if;
					when STOP =>
						if(i_cmd_done = '1') then
							w_state <= IDLE;
							o_cmd <= CMD_NOP;
							o_msg_done <= '1';
							o_tip <= '0';

							w_start <= r_start;
							w_stop <= r_stop;
							w_read <= r_read;
							w_write <= r_write;
						end if;
					when others =>
						null;
				end case;
			end if;
		end if;
	end process; -- byte_ctrl_FSM
end rtl;