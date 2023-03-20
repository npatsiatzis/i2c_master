--module that works on bit-level on the i2c bus. It receives from the byte-level module
--a symbol (i.e a part of an i2c message) that it then implements on the bit-level
--by manipulating the serial clock (scl) and serial data (sda) lines.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_bit_controller is
	port (
			--system clock and reset
			i_clk : in std_ulogic;
			i_arstn : in std_ulogic;

			i_rx : in std_ulogic;
			o_tx : out std_ulogic;
			i_scl_cycles : in std_ulogic_vector(15 downto 0);	
			i_en : in std_ulogic;
			i_cmd : in std_ulogic_vector(3 downto 0);
			o_cmd_done : out std_ulogic;
			o_busy : out std_ulogic;
			o_al : out std_ulogic;

			--i2c bus
			i_scl : in std_ulogic;
			i_sda : in std_ulogic;
			o_scl : out std_ulogic;
			o_sda : out std_ulogic;
			o_scl_en_n : out std_ulogic;
			o_sda_en_n : out std_ulogic);
end i2c_bit_controller;

architecture rtl of i2c_bit_controller is 
	constant CMD_NOP : std_ulogic_vector(3 downto 0) := "0000";
	constant CMD_START : std_ulogic_vector(3 downto 0) := "0001";
	constant CMD_STOP : std_ulogic_vector(3 downto 0) := "0010";
	constant CMD_WRITE : std_ulogic_vector(3 downto 0) := "0100";
	constant CMD_READ : std_ulogic_vector(3 downto 0) := "1000";

	signal w_scl, w_scl_r : std_ulogic;
	signal w_sda, w_sda_r : std_ulogic;
	signal w_scl_en_n_r : std_ulogic;
	signal w_wait : std_ulogic;

	signal w_scl_cnt : unsigned(15 downto 0);
	signal w_scl_edge_rdy : std_ulogic;

	signal w_start, w_stop : std_ulogic;
	signal w_stop_issued : std_ulogic;
	--signal i_cmd : std_ulogic_vector(3 downto 0);

	type t_state is (IDLE,START1,START2,START3,START4,START5,
		STOP1,STOP2,STOP3,STOP4,READ1,READ2,READ3,READ4,
		WRITE1,WRITE2,WRITE3,WRITE4);
	signal w_state : t_state;

begin

	register_inputs : process(i_clk,i_arstn) is
	begin
		if(i_arstn ='0') then
			w_scl <= '1';
			w_sda <= '1';
			w_scl_r <= '1';
			w_sda_r <= '1';
		elsif (rising_edge(i_clk)) then
			w_scl <= i_scl;
			w_sda <= i_sda;
			w_scl_r <= w_scl;
			w_sda_r <= w_sda;
		end if;
	end process; -- register_inputs

	--if the slave is not ready, it can stretch the clock, i.e pull SCL low
	w_wait <= '1' when (w_scl_en_n_r ='1' and w_scl = '0') else '0';

	delayed_scl_en : process(i_clk,i_arstn) is
	begin
		if(i_arstn = '0') then
			w_scl_en_n_r <= '0';
		elsif (rising_edge(i_clk)) then
			w_scl_en_n_r <= o_scl_en_n;
		end if;
	end process; -- delayed_scl_en

	--prepare the edge transitions of the serial clock line according to the required baud rate
	--to create all the events are required within a single scl cycle, we clearly need another (faster) clock.
	--called x_scl, where Fx_scl = x * Fi2c. The value of x corresponds to the implementation of events that constitute
	--one serial clock cycle, and the calculation for this specific case is drescribed below.

	--as seen in gen_scl_sda FSM, the serial clock's length is given by the distance (in cycles)
	--write3(posdge scl)->...->write3(posedge scl) and read3(posedge scl)->...->read3(posedge scl) respectively 
	--which is 5 cycles long.Given the desired frequency of the i2c's serial clock
	--and the system clock frequency, the frequency of this clock that manages the FSM we have : 
	--Fx_scl = Fsys/(5*Fi2c). If the implementation of the read/write symbols changes, this value has to be adapted 

	gen_scl : process(i_clk,i_arstn) is
	begin
		if(i_arstn = '0') then
			w_scl_cnt <= (others => '0');
			w_scl_edge_rdy <= '1';
		elsif (rising_edge(i_clk)) then
			if(w_scl_cnt = unsigned(i_scl_cycles)-1 or i_en = '0') then
				w_scl_cnt <= (others => '0');
				w_scl_edge_rdy <='1';
			elsif (w_wait = '1') then
				w_scl_edge_rdy <= '0';
			else
				w_scl_cnt <= w_scl_cnt +1;
				w_scl_edge_rdy <= '0';
			end if;
		end if;
	end process; -- gen_scl

	--generate start and stop condition indicators
	detect_start_stop : process(i_clk,i_arstn) is
	begin
		if(i_arstn = '0') then
			w_start <= '0';
			w_stop <= '0';
		elsif (rising_edge(i_clk)) then
			w_start <=  not(w_sda) and w_sda_r and w_scl;
			w_stop  <=  w_sda and not(w_sda_r) and w_scl;
		end if;
	end process; -- detect_start_stop

	--generate busy/ i2c transaction in progress signal

	identifier : process(i_clk,i_arstn) is
	begin
		if(i_arstn = '0') then
			o_busy <= '0';
		elsif(rising_edge(i_clk)) then
			o_busy <= (w_start or o_busy) and not (w_stop);
		end if;
	end process; -- identifier

	--arbitration lost logic (applicable in a multi-master scenario)
	-- arbitration lost when:
	-- 1) master drives the serial data line high, but the line is low
	-- 2) master detects a stop condition on the bus, which they have not issued

	gen_in_state_stop : process(i_clk,i_arstn) is
	begin
		if(i_arstn = '0') then
			w_stop_issued <= '0';
		elsif (rising_edge(i_clk)) then
			if(i_cmd = CMD_STOP) then
				w_stop_issued <= '1';
			else
				w_stop_issued <= '0';
			end if;
		end if;
	end process; -- gen_in_state_stop

	--arbitration lost logic

	gen_al : process(i_clk,i_arstn) is
	begin
		if(i_arstn = '0') then
			o_al <= '0';
		elsif(rising_edge(i_clk)) then
			if((w_sda = '0' and o_sda_en_n='1') or (w_state /= IDLE and w_stop_issued = '0' and w_stop ='1')) then
				o_al <= '1';
			else
				o_al <= '0';
			end if;
		end if;
	end process; -- gen_al

	--thanks to pull-up resistors of the i2c bus, tie sda and scl to the ground
	--and use the scl_en_n indicator to show when to drive 0 or let the bus to high

	o_scl <= '0';
	o_sda <= '0';


	gen_scl_sda : process(i_clk,i_arstn) is
	begin
		if(i_arstn = '0') then
			w_state <= IDLE;
			o_scl_en_n <= '1';
			o_sda_en_n <= '1';
			o_cmd_done <= '0';
		elsif (rising_edge(i_clk)) then
			if(o_al ='1') then
				w_state <= IDLE;
				o_scl_en_n <= '1';
				o_sda_en_n <= '1';
				o_cmd_done <= '0';
			else
				o_cmd_done <= '0';
				if(w_scl_edge_rdy = '1') then
					case w_state is 
						when IDLE =>
							case i_cmd is 
								when CMD_START =>
									w_state <= START1;
								when CMD_STOP =>
									w_state <= STOP1;
								when CMD_READ =>
									w_state <= READ1;
								when CMD_WRITE =>
									w_state <= WRITE1;
								when others =>
									w_state <= IDLE;
							end case;
		                -- generate START symbol
		                --	      1 | 2 | 3 | 4 | 5
		                --        _______
		                -- sda           \___________
		                --        _______________
		                -- scl                   \___
		                --

		                -- generate REPEATED START symbol
		                --	         1 | 2 | 3 | 4 | 5
		                --       	   ______
		                -- sda     ___/   	 \__________
		                --               ___________
		                -- scl    ______/           \___
		                --

		                --the implementation of the (repeated) START symbol
		                --does not affect F, F = Fsys/(5*Fi2c).
						when START1 =>
							w_state <= START2;
							o_sda_en_n <= '1';
						when START2 =>
							w_state <= START3;
							o_scl_en_n <= '1';
						when START3 =>
							w_state <= START4;
							o_sda_en_n <= '0';
						when START4 =>
							w_state <= START5;
							o_scl_en_n <= '1';
						when START5 =>
							w_state <= IDLE;
							o_scl_en_n <= '0';
							o_cmd_done <= '1';

		                -- generate STOP symbol
		                --	       1 | 2 | 3 | 4 |
		                --       		       ___
		                -- sda     ___________/   
		                --              ________
		                -- scl    _____/
		                --

		                --the implementation of the STOP symbol 
		                --does not affect F, F = Fsys/(5*Fi2c).
						when STOP1 =>	
							w_state <= STOP2;
							o_scl_en_n <= '0';
							o_sda_en_n <= '0';
						when STOP2 =>
							w_state <= STOP3;
							o_scl_en_n <= '1';
						when STOP3 =>
							w_state <= STOP4;
						when STOP4 =>
							w_state <= IDLE;
							o_sda_en_n <= '1';
							o_cmd_done <= '1';


		                -- generate READ symbol
		                --	       1 | 2 | 3 | 4 |
		                --       
		                -- sda     S=============
		                --             _______
		                -- scl    ____/       \___
		                --


		                --the implementation of the READ symbol
		                --affects F, F = Fsys/(5*Fi2c).
						when READ1 =>
							w_state <= READ2;
							o_scl_en_n <= '0';
							o_sda_en_n <= '1';
						when READ2 =>
							w_state <= READ3;
							o_scl_en_n <= '1';
						when READ3 =>
							w_state <= READ4;
							o_scl_en_n <= '1';
						when READ4 =>
							w_state <= IDLE;
							o_scl_en_n <= '0';
							o_cmd_done <= '1';

	                -- generate WRITE symbol
		                --	       1 | 2 | 3 | 4 |
		                --       
		                -- sda     M============   
		                --             _______
		                -- scl    ____/       \___
		                --


		                --the implementation of the WRITE symbol
		                --affects F, F = Fsys/(5*Fi2c).
						when WRITE1 =>
							w_state <= WRITE2;
							o_scl_en_n <= '0';
							o_sda_en_n <= i_rx;
						when WRITE2 =>
							w_state <= WRITE3;
							o_scl_en_n <= '1';
						when WRITE3 =>
							w_state <= WRITE4;
							o_scl_en_n <= '1';
						when WRITE4 =>
							w_state <= IDLE;
							o_scl_en_n <= '0';
							o_cmd_done <= '1';
						when others =>

							null;
					end case;
				end if;
			end if;
		end if;
	end process; -- gen_scl_sda

	--output received bits from the serial data line
	tx_sda : process(i_clk,i_arstn) is
	begin
		if (rising_edge(i_clk)) then
			if(w_scl = '1' and w_scl_r = '0') then
				o_tx <= w_sda;
			end if;
		end if;
	end process; -- tx_sda

end rtl;