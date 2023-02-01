--IIC (I2C) is a two-wire half-duplex data link

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity f_i2c_master is
	generic(
		g_sys_clk : natural := 400;				--system clock freq. in Hz
		g_bus_clk : natural := 60);				--i2c (bus) speed in Hz
	port(
		i_clk : in std_ulogic;							--system clock
		i_arst_n : in std_ulogic;						--asynchronous active low reset
		i_ena : in std_ulogic;							--ready/valid to latch in command
		i_rw  : in std_ulogic;							--'0' for write,'1' for read
		i_addr : in std_ulogic_vector(6 downto 0);		--slave address
		i_data : in std_ulogic_vector(7 downto 0);		--data to write to slave
		o_busy : out std_ulogic;						--master busy, transaction in progress
		o_ack_error : out std_ulogic;					--'1' if wrong acknowledge from slave
		io_sclk : inout std_ulogic;						--serial clock; bidirectional line 
		
		io_sda  : inout std_ulogic;						--serial data; bidirectional line
		o_data : out std_ulogic_vector(7 downto 0));	--data read from slave
end f_i2c_master;

architecture rtl of f_i2c_master is
	--create data and serial clock with 90 degress (quarter of a cycle) phase difference between them
	constant bus_clk_div_4 : natural := g_sys_clk/g_bus_clk/4;
	--distinguish between rising/falling edge of data clk for write/read sda purposes
	signal r_data_clk,r_data_clk_prev : std_ulogic;	
	--serial clock line under processing			
	signal r_sclk : std_ulogic;
	--signal to check whether the slave stretches sclk
	signal r_stretch : std_ulogic;

	--master i2c states
	type t_state is (ready,start,cmd,slv_ack1,wr,rd,slv_ack2,master_ack,stop);
	signal state : t_state;

	-- concatenation of slave address and rw option to send for first transfer (after start)
	signal r_addr_rw : std_ulogic_vector(7 downto 0);
	--data latched from user logic when ready/valid is asserted
	signal r_data : std_ulogic_vector(7 downto 0);
	--serial data line under processing
	signal r_sda : std_ulogic;

	--data (not ack) received from slave
	signal r_data_rx : std_ulogic_vector(7 downto 0);
	--enables the serial clock under processing to out
	signal r_sclk_en : std_ulogic;
	--internal register that is asserted in case of bad ack from slave
	signal r_ack_error : std_ulogic;
	--active low signal that enables the serial data line under construction to out
	signal w_sda_en_n : std_ulogic;

	signal cnt_bits : unsigned(2 downto 0);


	--signal io_sda : std_ulogic;
	signal io_sclk_prev : std_ulogic;

	--signal that help with verification (i2c slave functionality)
	signal sda : std_ulogic := '0';	
	signal data_rx : std_ulogic_vector(7 downto 0);
	signal addr_rw : std_ulogic_vector(7 downto 0);
	signal f_read_done : std_ulogic;
begin
	--create the data clock and the serial clock
	data_clk_sclk : process(i_clk,i_arst_n)
		variable cnt : integer range 0 to bus_clk_div_4*4;
	begin
		if(i_arst_n = '0') then
			cnt := 0;
			r_data_clk <= '0';
			r_sclk <= '0';
			r_stretch <= '0';
		elsif (rising_edge(i_clk)) then
			--there are bus_clk_div_4*4 system clock ticks in a cycle of data clk /sclk
			if(cnt = bus_clk_div_4*4 -1) then
				cnt :=0;
			--slave can stretch the clock (hold slk to '0') to esentially
			--pause the transaction
			elsif (r_stretch = '0') then
				cnt := cnt +1;
			end if;

			--create the phase difference between the two clocka
			if(cnt <bus_clk_div_4 ) then
				r_data_clk <= '0';
				r_sclk <= '0';
			elsif (cnt < bus_clk_div_4*2) then
				r_data_clk <= '1';
				r_sclk <= '0';
			elsif (cnt < bus_clk_div_4*3) then
				r_data_clk <='1';
				r_sclk <= '1';
				--check if slave stretches the clock
				if(io_sclk = '0') then
					r_stretch <= '1';
				else
					r_stretch <= '0';
				end if;
			else
				r_data_clk <= '0';
				r_sclk <= '1';
			end if;
				
		end if;
	end process; -- data_clk_sclk



	i2c_master_fsm : process(i_clk,i_arst_n)
		--variable cnt_bits : unsigned(2 downto 0);
	begin
		if(i_arst_n = '0') then				--if rst asserted
			o_busy <= '1';					--i2c master busy, not available for transactions
			state <= ready;					
			cnt_bits <= (others => '1');	--inialize r/w pointer to msb
			r_sda <= '1';					--do not drive sda
			r_ack_error <= '0';				--clear acknowledge error
			r_sclk_en <= '0';				--deassert enable for serial clock to out
			o_data <= (others => '0');		--clear data read from slave
		elsif(rising_edge(i_clk)) then
			r_data_clk_prev <= r_data_clk;
			io_sclk_prev <= io_sclk;
			if(r_data_clk = '1' and r_data_clk_prev = '0') then	--rising edge of data clk
				case state is 
					when ready =>
						if(i_ena = '1') then						--if ready and valid data from user
							o_busy <= '1';							--assert busy flag
							r_addr_rw <= i_addr & i_rw;				--latch in data,addr,rw
							r_data <= i_data;
							state <= start;							--start transaction
						else
							o_busy <= '0';
							state <= ready;
						end if;
					--start condition is master pull sda low while sclk is high
					--given the phase between data clk and sclk, that can occur
					--only in the falling edge of the data clk. So don't drive sda
					--for the start condition from within here
					when start =>
						r_sda <= r_addr_rw(to_integer(cnt_bits));	--place the msb of the command on sda
						o_busy <= '1';
						state <= cmd;								--go to command state
						cnt_bits <= cnt_bits -1;				--manage r/w pointer
					when cmd =>										--send slave address and r/w msb first
						o_busy <= '1';
						if(cnt_bits >0) then						--if not whole command sent
							cnt_bits <= cnt_bits -1;				--manage r/w pointer
							r_sda <= r_addr_rw(to_integer(cnt_bits));	--drive sda with data
							state <= cmd;
						else           								--if done sending the command
							r_sda <= '1';							--deassert sda to read ack
							cnt_bits <= (others => '1');			--reinitialize r/w pointer
							state <= slv_ack1;						--go to slave ack 1 state
						end if;
					when slv_ack1 =>
						if(r_addr_rw(0) = '0') then					--if cmd lsb is 0 -> write
							r_sda <= r_data(to_integer(cnt_bits));	--latch msb of data to sda
							state <= wr;
							cnt_bits <= cnt_bits -1;				--manage r/w pointer
						else  										--if cmd lsb is 1 -> read
							r_sda <= '1';							--deassert sda to read
							state <= rd;
						end if;
					when wr =>
						o_busy <= '1';
						if(cnt_bits >0) then						--if not all data written
							cnt_bits <= cnt_bits -1;				--manage r/w pointer
							r_sda <= r_data(to_integer(cnt_bits));
							state <= wr;
						else  										--if data write transaction complete
							cnt_bits <= (others => '1');			--reinitialize r/w pointer		
							r_sda <= r_data(0);
							--r_sda <= '1';							--deassert sda to read ack
							state <= slv_ack2;						
						end if;
					when rd =>
						o_busy <= '1';
						if (cnt_bits >0) then						--if not all bits read
							cnt_bits <= cnt_bits -1;				--manage r/w pointer
							state <= rd;
						else
							--if read from slave complete and new read transaction from same slave
							if(i_ena = '1' and i_addr & i_rw = r_addr_rw) then	
								r_sda <= '0';						--send acknowledge to slave
							else
								r_sda <= '1';					--send no-acknowledge to slave
																--sent when final read tran. with that slave
							end if;
							cnt_bits <= (others => '1');
							o_data <= r_data_rx;					--data read from slave to output
							state <= master_ack;					--go to master acknowledge state
						end if;
					when slv_ack2 =>
						if(i_ena = '1') then						--if en from user for new transaction
							o_busy <= '0';							--pull busy low to indicate accept
							r_addr_rw <= i_addr & i_rw;				--latch in new data,addr,rw
							r_data <= i_data;
							if(r_addr_rw = i_addr & i_rw) then		--if same as previous transaction
								r_sda <= r_data(to_integer(cnt_bits));	--start sending new data
								state <= wr;
							else
								state <= start;						--other type of transaction(r) or address
							end if;									--go to start state
						else  										--if not ready/valid from user go to stop
							state <= stop;
					end if;
					when master_ack =>
						if(i_ena = '1') then						--if en from user for new transaction
							o_busy <= '0';							--pull busy low to indicate accept
							r_addr_rw <= i_addr & i_rw;				--latch in new data,addr,rw
							r_data <= i_data;
							if(r_addr_rw = i_addr & i_rw) then		--if same as previous transaction
								r_sda <= '1';						--deassert sda to start reading
								state <= rd;						--go to rd to read
							else
								state <= start;						--if other transaction(w) or address
							end if;									--go to start state
						else   										--if not ready/valid fron user go to stop
							state <= stop;
						end if;
					when stop => 									--deassert busy
						o_busy <= '0';								--go to ready to wait for ready from user
						state <= ready;
					when others =>
				end case;
			elsif(r_data_clk = '0' and r_data_clk_prev = '1') then	--falling edge of data clock(used for r)
				case state is 
					when start =>
						if(r_sclk_en = '0') then					--enable sclk to output
							r_sclk_en <= '1';
							r_ack_error <= '0';
						end if;
					when slv_ack1 =>									--read ack from slave
						if(sda /= '0' or r_ack_error = '1') then	--if wrong ack
							r_ack_error <= '1';							--assert ack error
						end if;
					when rd =>
						r_data_rx(to_integer(cnt_bits)) <= sda;		--read data from sda
					when slv_ack2 =>									--read ack from slave
						if(sda /= '0' or r_ack_error = '1') then	--if wrong ack
							r_ack_error <= '1';							--assert ack error
						end if;
					when stop =>										--deassert clk to out enable
						r_sclk_en <= '0';
					when others => 
						null;
				end case;
			end if;
		end if;
	end process; -- i2c_master_fsm

	o_ack_error <= r_ack_error;				
	--active low signal enable from under construction sda to output
	--special cases for start and stop condition.
	--send start ('0') in the falling edge of the data clk (sda -> '0' before sclk -> '0')
	--send stop  ('0') in the rising edge  of the data clk (sda -> '1' after  sclk -> '1')				
	with state select 												
		w_sda_en_n <= r_data_clk_prev when start,
					not r_data_clk_prev when stop,
					r_sda when others;

	io_sclk <= '0' when (r_sclk_en = '1' and r_sclk = '0') else '1';
	io_sda  <= '0' when (w_sda_en_n = '0') else '1';


	--i2c slave basic functionality emulation (loopback)
	process(i_clk,i_arst_n)
	begin
		if(i_arst_n = '0') then
			sda <= '0';
		elsif(rising_edge(i_clk)) then

			if(io_sclk = '0' and io_sclk_prev = '1') then
				case state is
					when cmd =>
						addr_rw(to_integer(cnt_bits)) <= r_sda;
					when wr =>
						data_rx(to_integer(cnt_bits+1)) <= r_sda;
					when slv_ack2 =>
						if(cnt_bits = 7) then
							data_rx(0) <= r_sda;
						end if;
					when others=>
						null;
				end case;
			elsif(io_sclk = '1' and io_sclk_prev = '0') then
				case state is
					when rd =>
						sda <= data_rx(to_integer(cnt_bits));
					when others =>
						null;
				end case;			
			end if;
		end if;
	end process;

	f_read_done <= '1' when (state = master_ack and i_ena = '1' and r_addr_rw /= i_addr & i_rw) else '0';
end rtl;