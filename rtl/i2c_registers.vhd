library ieee;
use ieee.std_logic_1164.all;

entity i2c_registers is
	port (
			i_clk : in std_ulogic;
			i_arstn : in std_ulogic;

			--wishbone (slave) interface
			i_addr : in std_ulogic_vector(2 downto 0);
			i_we : in std_ulogic;
			i_stb : in std_ulogic;
			i_data : in std_ulogic_vector(7 downto 0);
			o_ack : out std_ulogic;
			o_data : out std_ulogic_vector(7 downto 0);

			--internal (hierarchy) signals
			i_i2c_rd_data : in std_ulogic_vector(7 downto 0);
			i_busy : in std_ulogic;
			i_done : in std_ulogic;
			i_al : in std_ulogic;
			i_ack : in std_ulogic;

			o_scl_cycles : out std_ulogic_vector(15 downto 0);
			o_txr : out std_ulogic_vector(7 downto 0);
			o_ctr : out std_ulogic_vector(7 downto 0);
			o_cr : out std_ulogic_vector(7 downto 0));
end i2c_registers;

architecture rtl of i2c_registers is
begin
	fill_regs : process(i_clk,i_arstn) is
	begin
		if(i_arstn = '0') then
			o_scl_cycles <= (others => '1');
			o_txr <= (others => '0');
			o_ctr <= (others => '0');
			o_cr <= (others => '0');
			o_ack <= '0';
		elsif (rising_edge(i_clk)) then
			o_ack <= '0';

			if(i_stb = '1' and i_we = '1') then
				o_ack <= '1';
				if(o_ctr(7) = '1' and i_addr = "100") then
					o_cr <= i_data;
				end if;
				case i_addr is 
					when "000" => 
						o_scl_cycles(7 downto 0) <= i_data;
					when "001" =>
						o_scl_cycles(15 downto 8) <= i_data;
					when "010" =>
						o_ctr <= i_data;
					when "011" =>
						o_txr <= i_data;
					when others =>
						null;
				end case; 
			elsif(i_stb = '1' and i_we = '0' and i_addr = "011") then
				o_ack <= '1';
				o_data <= i_i2c_rd_data;
			else
				if(i_done ='1' or i_al = '1') then
					o_cr(7 downto 4) <= "0000";
				end if;
				o_cr(2 downto 0) <= "000";
			end if;
		end if;
	end process; -- fill_regs
end rtl;