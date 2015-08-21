----------------------------------------------------------------------------------
-- Company:        IIHE - ULB
-- Engineer:       Thomas Lenzi (thomas.lenzi@cern.ch)
-- 
-- Create Date:    08:44:34 08/18/2015 
-- Design Name:    OptoHybrid v2
-- Module Name:    func_i2c - Behavioral 
-- Project Name:   OptoHybrid v2
-- Target Devices: xc6vlx130t-1ff1156
-- Tool versions:  ISE  P.20131013
-- Description:
--
-- Whishbone slave that handles communications to multiple VFAT2s
--
-- Register map:
-- 0..150 : VFAT2 registers
-- 256 : mask (24 bits)
-- 257 : read out the results (32 bits = 8x0 & 8 bits of vfat2 id & 8 bits of status & 8 bits of data
-- 258 : local reset
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.types_pkg.all;

entity func_i2c is
port(

    -- System signals
    ref_clk_i       : in std_logic;
    reset_i         : in std_logic;
    
    -- Wishbone slave
    wb_slv_req_i    : in wb_req_array_t(1 downto 0);
    wb_slv_res_o    : out wb_res_array_t(1 downto 0);
    
    -- Wishbone master
    wb_mst_req_o    : out wb_req_t;
    wb_mst_res_i    : in wb_res_t
    
);
end func_i2c;

architecture Behavioral of func_i2c is
    
    -- Local reset
    signal local_reset  : std_logic;
    
    -- Signals from the Wishbone Splitter
    signal wb_stb       : std_logic_vector(2 downto 0);
    signal wb_we        : std_logic;
    signal wb_addr      : std_logic_vector(31 downto 0);
    signal wb_data      : std_logic_vector(31 downto 0);
    
    -- Signals for the registers
    signal reg_ack      : std_logic_vector(2 downto 0);
    signal reg_err      : std_logic_vector(2 downto 0);
    signal reg_data     : std32_array_t(2 downto 0);
    
    -- Signals to the FIFO
    signal fifo_rst     : std_logic;
    signal fifo_we      : std_logic;
    signal fifo_din     : std_logic_vector(31 downto 0);

begin
    
    --==================--
    --== I2C extended ==--
    --==================--
    
    -- 0..150 : VFAT2 registers

    func_i2c_req_inst : entity work.func_i2c_req
    port map(
        ref_clk_i       => ref_clk_i,
        reset_i         => local_reset,
        wb_slv_req_i    => wb_slv_req_i(0),
        wb_slv_res_o    => wb_slv_res_o(0),
        wb_mst_req_o    => wb_mst_req_o,
        wb_mst_res_i    => wb_mst_res_i,
        req_mask_i      => reg_data(0)(23 downto 0),
        fifo_rst_o      => fifo_rst,
        fifo_we_o       => fifo_we,
        fifo_din_o      => fifo_din
    );

    --===============================--
    --== Wishbone request splitter ==--
    --===============================--

    wb_splitter_inst : entity work.wb_splitter
    generic map(
        SIZE        => 3
    )
    port map(
        ref_clk_i   => ref_clk_i,
        reset_i     => local_reset,
        wb_req_i    => wb_slv_req_i(1),
        wb_res_o    => wb_slv_res_o(1),
        stb_o       => wb_stb,
        we_o        => wb_we,
        addr_o      => wb_addr,
        data_o      => wb_data,
        ack_i       => reg_ack,
        err_i       => reg_err,
        data_i      => reg_data
    );
    
    --===============--
    --== Registers ==--
    --===============--
    
    -- 256 : mask (24 bits)

    registers_inst : entity work.registers
    generic map(
        SIZE        => 1
    )
    port map(
        ref_clk_i   => ref_clk_i,
        reset_i     => local_reset,
        stb_i       => wb_stb(0 downto 0),
        we_i        => wb_we,
        data_i      => wb_data,
        ack_o       => reg_ack(0 downto 0),
        err_o       => reg_err(0 downto 0),
        data_o      => reg_data(0 downto 0)
    );
    
    --=======================--
    --== FIFO with results ==--
    --=======================--

    -- 257 : read out the results (32 bits = 8x0 & 8 bits of vfat2 id & 8 bits of status & 8 bits of data

    fifo32x32_inst : entity work.fifo32x32
    port map(
        clk         => ref_clk_i,
        rst         => (fifo_rst or local_reset),
        wr_en       => fifo_we,
        din         => fifo_din,
        rd_en       => wb_stb(1),
        valid       => reg_ack(1),
        dout        => reg_data(1),
        underflow   => reg_err(1),
        full        => open,
        empty       => open
    );
    
    --=================--
    --== Local reset ==--
    --=================--
    
    -- 258 : local reset

    local_reset <= reset_i or wb_stb(2);
    
    -- Connect signals for automatic response
    reg_ack(2) <= wb_stb(2);
    reg_err(2) <= '0';
    reg_data(2) <= (others => '0');

end Behavioral;

