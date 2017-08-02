------------------------------------------------------------------------------------------------------------------------------------------------------
-- Company: TAMU
-- Engineer: Evaldas Juska (evaldas.juska@cern.ch, evka85@gmail.com)
--
-- Create Date:    02:35 2016-05-31
-- Module Name:    link_gbt_rx
-- Description:    this module provides GBT RX link decoding
------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

entity link_gbt_rx is
port(

    ttc_clk_40_i            : in std_logic;
    reset_i                 : in std_logic;

    req_en_o                : out std_logic;
    req_data_o              : out std_logic_vector(31 downto 0);

    gbt_rx_data_i           : in std_logic_vector(15 downto 0)

);
end link_gbt_rx;

architecture link_gbt_rx_arch of link_gbt_rx is

    type state_t is (HEADER, REG_DATA0, REG_DATA1);

    signal state            : state_t;

    signal req_valid        : std_logic := '0';

    signal header_valid     : std_logic := '0';

    signal oh_data          : std_logic_vector(15 downto 0) := (others => '0');
    signal oh_data_0        : std_logic_vector(15 downto 0) := (others => '0');

begin

    -- on OH v3a, two e-links are connected to the FPGA
    oh_data       <= gbt_rx_data_i(15 downto 0);

    header_valid  <= '1' when (oh_data(15 downto 0) = x"BCBC") else '0';

    --== STATE ==--

    process(ttc_clk_40_i)
    begin
        if (rising_edge(ttc_clk_40_i)) then
            if (reset_i = '1') then
                state <= HEADER;
            else
                case state is
                    when HEADER   =>
                        if (oh_data(15 downto 0) = x"3CBC") then
                            state <= REG_DATA0;
                        end if;
                    when REG_DATA0 => state <= REG_DATA1;
                    when REG_DATA1 => state <= HEADER;
                    when others =>
                        state <= HEADER;
                end case;
            end if;
        end if;
    end process;

    --== REQUEST ==--

    process(ttc_clk_40_i)
    begin
        if (rising_edge(ttc_clk_40_i)) then
            if (reset_i = '1') then
                req_en_o <= '0';
                req_data_o <= (others => '0');
                req_valid <= '0';
            else
                case state is
                    when HEADER    =>    req_en_o   <= '0';
                                         req_data_o <= (others => '0');
                                         req_valid  <= header_valid;

                    when REG_DATA0 =>    req_en_o   <= req_valid;
                                         oh_data_0  <= oh_data;

                    when REG_DATA1 =>    req_en_o   <= req_valid;
                                         req_data_o <= oh_data & oh_data_0;

                    when others    =>    req_en_o   <= '0';
                                         req_data_o <= (others => '0');
                end case;
            end if;
        end if;
    end process;

end link_gbt_rx_arch;
