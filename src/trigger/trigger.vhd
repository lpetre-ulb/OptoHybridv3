----------------------------------------------------------------------------------
-- CMS Muon Endcap
-- GEM Collaboration
-- Optohybrid v3 Firmware -- Trigger
-- A. Peck
----------------------------------------------------------------------------------
-- Description:
--   This module holds all the required functionality for the trigger S-bit alignment
--   and cluster building
----------------------------------------------------------------------------------
-- 2017/07/24 -- Initial
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.types_pkg.all;
use work.ipbus_pkg.all;
use work.param_pkg.all;
use work.trig_pkg.all;
use work.registers.all;

entity trigger is
port(

    -- ipbus wishbone

    ipb_mosi_i        : in  ipb_wbus;
    ipb_miso_o        : out ipb_rbus;

    -- links
    mgt_clk_p         : in std_logic_vector (1 downto 0); -- 160 MHz Reference Clock
    mgt_clk_n         : in std_logic_vector (1 downto 0); -- 160 MHz Reference Clock

    clk_40            : in std_logic;
    clk_80            : in std_logic;
    clk_160           : in std_logic;
    clk_200           : in std_logic;
    clk_160_90        : in std_logic;

    reset_i           : in std_logic;
    ttc_resync        : in std_logic;

    mgt_tx_p          : out std_logic_vector(3 downto 0);
    mgt_tx_n          : out std_logic_vector(3 downto 0);

    -- ttc

    trig_stop_i       : in std_logic;
    bxn_counter_i     : in std_logic_vector(11 downto 0);
    ttc_bx0_i         : in std_logic;

    -- cluster packer

    cluster_count_o   : out std_logic_vector (7 downto 0);
    overflow_o        : out std_logic;

    active_vfats_o    : out std_logic_vector (MXVFATS-1 downto 0);

    -- sbits
    vfat_sot_p        : in std_logic_vector (MXVFATS-1 downto 0);
    vfat_sot_n        : in std_logic_vector (MXVFATS-1 downto 0);

    vfat_sbits_p      : in std_logic_vector ((MXVFATS*8)-1 downto 0);
    vfat_sbits_n      : in std_logic_vector ((MXVFATS*8)-1 downto 0);

    -- sbits

    master_slave_p    : inout  std_logic_vector (11 downto 0);
    master_slave_n    : inout  std_logic_vector (11 downto 0);

    cnt_snap          : in std_logic

);
end trigger;

architecture Behavioral of trigger is

    signal cluster0 : std_logic_vector (13 downto 0);
    signal cluster1 : std_logic_vector (13 downto 0);
    signal cluster2 : std_logic_vector (13 downto 0);
    signal cluster3 : std_logic_vector (13 downto 0);
    signal cluster4 : std_logic_vector (13 downto 0);
    signal cluster5 : std_logic_vector (13 downto 0);
    signal cluster6 : std_logic_vector (13 downto 0);
    signal cluster7 : std_logic_vector (13 downto 0);

    signal sbit_overflow     : std_logic;
    signal sbit_clusters     : sbit_cluster_array_t (7  downto 0);
    signal valid_clusters_or : std_logic;
    signal valid_clusters    : std_logic_vector (7 downto 0);

    signal cnt_en            : std_logic_vector (MXVFATS-1 downto 0);

    signal active_vfats : std_logic_vector (MXVFATS-1 downto 0);

    signal vfat_mask : std_logic_vector (MXVFATS-1 downto 0);
    signal trig_deadtime : std_logic_vector (3 downto 0);

    signal sot_invert : std_logic_vector (MXVFATS-1 downto 0);     -- 24 or 12
    signal  tu_invert : std_logic_vector ((MXVFATS*8)-1 downto 0); -- 192 or 96
    signal  tu_mask   : std_logic_vector ((MXVFATS*8)-1 downto 0); -- 192 or 96

    signal aligned_count_to_ready : std_logic_vector (11 downto 0);

    signal reset     : std_logic;
    signal ipb_reset : std_logic;

    attribute EQUIVALENT_REGISTER_REMOVAL : string;
    attribute EQUIVALENT_REGISTER_REMOVAL of reset : signal is "NO";
    attribute EQUIVALENT_REGISTER_REMOVAL of ipb_reset : signal is "NO";

    signal sot_is_aligned      : std_logic_vector (MXVFATS-1 downto 0);
    signal sot_unstable        : std_logic_vector (MXVFATS-1 downto 0);

    signal sot_tap_delay       : t_std5_array (MXVFATS-1 downto 0);
    signal trig_tap_delay      : t_std5_array ((MXVFATS*8)-1 downto 0);

    signal sbits_mux_sel        : std_logic_vector  (4 downto 0);
    signal sbits_mux            : std_logic_vector (63 downto 0);

    -- control signals from gbt (verb, object)
    signal reset_counters       : std_logic;
    signal sbit_cnt_persist     : std_logic;
    signal sbit_cnt_time_max    : std_logic_vector (31 downto 0);

    signal sbit_cnt_snap        : std_logic;
    signal sbit_timer_snap      : std_logic;
    signal sbit_timer_reset     : std_logic;

    signal sbit_time_counter    : unsigned (31 downto 0);

    signal reset_links          : std_logic;

    signal cnt_pulse            : std_logic;

    -- reset signal (ORed with global reset)
    signal cnt_reset            : std_logic;
    signal cnt_reset_strobed    : std_logic;
    signal tx_link_reset        : std_logic;
    signal tx_reset_done        : std_logic_vector(3 downto 0);
    signal tx_pll_locked        : std_logic_vector(3 downto 0);

    ------ Register signals begin (this section is generated by <optohybrid_top>/tools/generate_registers.py -- do not edit)
    signal regs_read_arr        : t_std32_array(REG_TRIG_NUM_REGS - 1 downto 0) := (others => (others => '0'));
    signal regs_write_arr       : t_std32_array(REG_TRIG_NUM_REGS - 1 downto 0) := (others => (others => '0'));
    signal regs_addresses       : t_std32_array(REG_TRIG_NUM_REGS - 1 downto 0) := (others => (others => '0'));
    signal regs_defaults        : t_std32_array(REG_TRIG_NUM_REGS - 1 downto 0) := (others => (others => '0'));
    signal regs_read_pulse_arr  : std_logic_vector(REG_TRIG_NUM_REGS - 1 downto 0) := (others => '0');
    signal regs_write_pulse_arr : std_logic_vector(REG_TRIG_NUM_REGS - 1 downto 0) := (others => '0');
    signal regs_read_ready_arr  : std_logic_vector(REG_TRIG_NUM_REGS - 1 downto 0) := (others => '1');
    signal regs_write_done_arr  : std_logic_vector(REG_TRIG_NUM_REGS - 1 downto 0) := (others => '1');
    signal regs_writable_arr    : std_logic_vector(REG_TRIG_NUM_REGS - 1 downto 0) := (others => '0');
    -- Connect counter signal declarations
    signal cnt_sbit_overflow : std_logic_vector (15 downto 0) := (others => '0');
    signal cnt_vfat0 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_vfat1 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_vfat2 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_vfat3 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_vfat4 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_vfat5 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_vfat6 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_vfat7 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_vfat8 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_vfat9 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_vfat10 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_vfat11 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_vfat12 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_vfat13 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_vfat14 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_vfat15 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_vfat16 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_vfat17 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_vfat18 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_vfat19 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_vfat20 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_vfat21 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_vfat22 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_vfat23 : std_logic_vector (31 downto 0) := (others => '0');
    signal cnt_clusters : std_logic_vector (31 downto 0) := (others => '0');
    ------ Register signals end ----------------------------------------------

begin

    --------------------------------------------------------------------------------------------------------------------
    -- Resets
    --------------------------------------------------------------------------------------------------------------------

    process (clk_40) begin
        if (rising_edge(clk_40)) then
            reset     <= reset_i;
            ipb_reset <= reset;
        end if;
    end process;

    process (clk_40) begin
        if (rising_edge(clk_40)) then
            cnt_reset         <= reset or ttc_resync or reset_counters;
            cnt_reset_strobed <= reset or ttc_resync or reset_counters or (sbit_timer_reset and not sbit_cnt_persist);
        end if;
    end process;

    process (clk_40) begin
        if (rising_edge(clk_40)) then
            tx_link_reset <= reset or reset_links;
        end if;
    end process;

    --------------------------------------------------------------------------------------------------------------------
    -- Cnt_en static expression
    --------------------------------------------------------------------------------------------------------------------

    cnt_en_loop : for I in 0 to (MXVFATS-1) generate
    begin
    process (clk_40)
    begin
        if (rising_edge(clk_40)) then
            cnt_en(I) <= active_vfats(I) or cnt_pulse;
        end if;
    end process;
    end generate;

    --------------------------------------------------------------------------------------------------------------------
    -- Outputs
    --------------------------------------------------------------------------------------------------------------------

    overflow_o <= sbit_overflow;
    active_vfats_o <= active_vfats;

    --------------------------------------------------------------------------------------------------------------------
    -- Counter Snap
    --------------------------------------------------------------------------------------------------------------------

    process (clk_40) begin
        if (rising_edge(clk_40)) then

            sbit_cnt_snap <= (sbit_timer_snap or sbit_cnt_persist);

            if (reset = '1') then
                sbit_time_counter <= (others => '0');
                sbit_timer_reset <= '1';
                sbit_timer_snap  <= '1';
            else
                if (sbit_time_counter = unsigned(sbit_cnt_time_max)) then
                    sbit_time_counter <= (others => '0');
                    sbit_timer_reset  <= '1';
                    sbit_timer_snap   <= '1';
                else
                    sbit_time_counter <= sbit_time_counter + 1;
                    sbit_timer_reset  <= '0';
                    sbit_timer_snap   <= '0';
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------------------------------------------
    -- S-bit deserilization and cluster building
    --------------------------------------------------------------------------------------------------------------------

    sbits : entity work.sbits
    port map (

        trig_stop_i             => trig_stop_i,

        clk40_i                 => clk_40,
        clk80_i                 => clk_80,
        clk160_i                => clk_160,
        clk160_90_i             => clk_160_90,
        clk200_i                => clk_200,

        sbits_mux_sel_i         => sbits_mux_sel,
        sbits_mux_o             => sbits_mux,


        aligned_count_to_ready   => aligned_count_to_ready,

        reset_i                 => reset,

        sbits_p                  => vfat_sbits_p,
        sbits_n                  => vfat_sbits_n,

        start_of_frame_p         => vfat_sot_p,
        start_of_frame_n         => vfat_sot_n,

        vfat_mask_i  => vfat_mask (MXVFATS -1 downto 0),
        sot_invert_i => sot_invert (MXVFATS-1 downto 0),
        tu_invert_i  => tu_invert,
        tu_mask_i    => tu_mask,

        active_vfats_o          => active_vfats,

        vfat_sbit_clusters_o    => sbit_clusters,
        trigger_deadtime_i      => trig_deadtime,
        cluster_count_o         => cluster_count_o,
        overflow_o              => sbit_overflow,

        sot_tap_delay           => sot_tap_delay,
        trig_tap_delay          => trig_tap_delay,

        sot_is_aligned_o        => sot_is_aligned,
        sot_unstable_o          => sot_unstable

    );

    --------------------------------------------------------------------------------------------------------------------
    -- Fixed latency trigger links
    --------------------------------------------------------------------------------------------------------------------

    trigger_links_inst : entity work.trigger_links
    generic map (
        FPGA_TYPE_IS_VIRTEX6  => FPGA_TYPE_IS_VIRTEX6,
        FPGA_TYPE_IS_ARTIX7   => FPGA_TYPE_IS_ARTIX7
    )
    port map (

        mgt_clk_p  => mgt_clk_p, -- 160 MHz Reference Clock Positive
        mgt_clk_n  => mgt_clk_n, -- 160 MHz Reference Clock Negative

        clk_40     => clk_40,  -- 40 MHz  Logic Clock
        clk_80     => clk_80,  -- 80 MHz  User Clock 2
        clk_160    => clk_160, -- 160 MHz User Clock

        bxn_counter => bxn_counter_i,
        ttc_bx0     => ttc_bx0_i    ,

        reset_i    => tx_link_reset,
        pll_locked => tx_pll_locked,
        reset_done => tx_reset_done,

        trg_tx_p   => mgt_tx_p (3 downto 0),
        trg_tx_n   => mgt_tx_n (3 downto 0),

        cluster0   => sbit_clusters(0),
        cluster1   => sbit_clusters(1),
        cluster2   => sbit_clusters(2),
        cluster3   => sbit_clusters(3),
        cluster4   => sbit_clusters(4),
        cluster5   => sbit_clusters(5),
        cluster6   => sbit_clusters(6),
        cluster7   => sbit_clusters(7),

        valid_clusters    => valid_clusters,
        valid_clusters_or => valid_clusters_or,

        overflow   => sbit_overflow
    );

    --===============================================================================================
    -- (this section is generated by <optohybrid_top>/tools/generate_registers.py -- do not edit)
    --==== Registers begin ==========================================================================

    -- IPbus slave instanciation
    ipbus_slave_inst : entity work.ipbus_slave
        generic map(
           g_NUM_REGS             => REG_TRIG_NUM_REGS,
           g_ADDR_HIGH_BIT        => REG_TRIG_ADDRESS_MSB,
           g_ADDR_LOW_BIT         => REG_TRIG_ADDRESS_LSB,
           g_USE_INDIVIDUAL_ADDRS => true
       )
       port map(
           ipb_reset_i            => ipb_reset,
           ipb_clk_i              => clk_40,
           ipb_mosi_i             => ipb_mosi_i,
           ipb_miso_o             => ipb_miso_o,
           usr_clk_i              => clk_40,
           regs_read_arr_i        => regs_read_arr,
           regs_write_arr_o       => regs_write_arr,
           read_pulse_arr_o       => regs_read_pulse_arr,
           write_pulse_arr_o      => regs_write_pulse_arr,
           regs_read_ready_arr_i  => regs_read_ready_arr,
           regs_write_done_arr_i  => regs_write_done_arr,
           individual_addrs_arr_i => regs_addresses,
           regs_defaults_arr_i    => regs_defaults,
           writable_regs_i        => regs_writable_arr
      );

    -- Addresses
    regs_addresses(0)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"00";
    regs_addresses(1)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"01";
    regs_addresses(2)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"02";
    regs_addresses(3)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"03";
    regs_addresses(4)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"04";
    regs_addresses(5)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"05";
    regs_addresses(6)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"06";
    regs_addresses(7)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"07";
    regs_addresses(8)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"08";
    regs_addresses(9)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"09";
    regs_addresses(10)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"0a";
    regs_addresses(11)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"0b";
    regs_addresses(12)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"0e";
    regs_addresses(13)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"0f";
    regs_addresses(14)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"10";
    regs_addresses(15)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"11";
    regs_addresses(16)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"12";
    regs_addresses(17)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"13";
    regs_addresses(18)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"14";
    regs_addresses(19)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"15";
    regs_addresses(20)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"16";
    regs_addresses(21)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"17";
    regs_addresses(22)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"18";
    regs_addresses(23)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"19";
    regs_addresses(24)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"1a";
    regs_addresses(25)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"1b";
    regs_addresses(26)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"1c";
    regs_addresses(27)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"1d";
    regs_addresses(28)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"1e";
    regs_addresses(29)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"1f";
    regs_addresses(30)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"20";
    regs_addresses(31)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"21";
    regs_addresses(32)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"22";
    regs_addresses(33)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"23";
    regs_addresses(34)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"24";
    regs_addresses(35)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"25";
    regs_addresses(36)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"26";
    regs_addresses(37)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"27";
    regs_addresses(38)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"28";
    regs_addresses(39)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"29";
    regs_addresses(40)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"2a";
    regs_addresses(41)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"2b";
    regs_addresses(42)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"2c";
    regs_addresses(43)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"2d";
    regs_addresses(44)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"2e";
    regs_addresses(45)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"2f";
    regs_addresses(46)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"30";
    regs_addresses(47)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"31";
    regs_addresses(48)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"32";
    regs_addresses(49)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"33";
    regs_addresses(50)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"3b";
    regs_addresses(51)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"3c";
    regs_addresses(52)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"3d";
    regs_addresses(53)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"3e";
    regs_addresses(54)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"3f";
    regs_addresses(55)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"40";
    regs_addresses(56)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"41";
    regs_addresses(57)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"42";
    regs_addresses(58)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"43";
    regs_addresses(59)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"44";
    regs_addresses(60)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"45";
    regs_addresses(61)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"46";
    regs_addresses(62)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"47";
    regs_addresses(63)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"48";
    regs_addresses(64)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"49";
    regs_addresses(65)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"4a";
    regs_addresses(66)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"4b";
    regs_addresses(67)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"4c";
    regs_addresses(68)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"4d";
    regs_addresses(69)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"4e";
    regs_addresses(70)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"4f";
    regs_addresses(71)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"50";
    regs_addresses(72)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"51";
    regs_addresses(73)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"52";
    regs_addresses(74)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"53";
    regs_addresses(75)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"54";
    regs_addresses(76)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"55";
    regs_addresses(77)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"56";
    regs_addresses(78)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"57";
    regs_addresses(79)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"58";
    regs_addresses(80)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"59";
    regs_addresses(81)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"5a";
    regs_addresses(82)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"5b";
    regs_addresses(83)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"5c";
    regs_addresses(84)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"5d";
    regs_addresses(85)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"5e";
    regs_addresses(86)(REG_TRIG_ADDRESS_MSB downto REG_TRIG_ADDRESS_LSB) <= x"5f";

    -- Connect read signals
    regs_read_arr(0)(REG_TRIG_CTRL_VFAT_MASK_MSB downto REG_TRIG_CTRL_VFAT_MASK_LSB) <= vfat_mask;
    regs_read_arr(0)(REG_TRIG_CTRL_SBIT_DEADTIME_MSB downto REG_TRIG_CTRL_SBIT_DEADTIME_LSB) <= trig_deadtime;
    regs_read_arr(1)(REG_TRIG_CTRL_ACTIVE_VFATS_MSB downto REG_TRIG_CTRL_ACTIVE_VFATS_LSB) <= active_vfats;
    regs_read_arr(2)(REG_TRIG_CTRL_CNT_OVERFLOW_MSB downto REG_TRIG_CTRL_CNT_OVERFLOW_LSB) <= cnt_sbit_overflow;
    regs_read_arr(2)(REG_TRIG_CTRL_ALIGNED_COUNT_TO_READY_MSB downto REG_TRIG_CTRL_ALIGNED_COUNT_TO_READY_LSB) <= aligned_count_to_ready;
    regs_read_arr(3)(REG_TRIG_CTRL_SBIT_SOT_READY_MSB downto REG_TRIG_CTRL_SBIT_SOT_READY_LSB) <= sot_is_aligned;
    regs_read_arr(4)(REG_TRIG_CTRL_SBIT_SOT_UNSTABLE_MSB downto REG_TRIG_CTRL_SBIT_SOT_UNSTABLE_LSB) <= sot_unstable;
    regs_read_arr(5)(REG_TRIG_CTRL_INVERT_SOT_INVERT_MSB downto REG_TRIG_CTRL_INVERT_SOT_INVERT_LSB) <= sot_invert;
    regs_read_arr(6)(REG_TRIG_CTRL_INVERT_VFAT0_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT0_TU_INVERT_LSB) <= TU_INVERT (7 downto 0);
    regs_read_arr(6)(REG_TRIG_CTRL_INVERT_VFAT1_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT1_TU_INVERT_LSB) <= TU_INVERT (15 downto 8);
    regs_read_arr(6)(REG_TRIG_CTRL_INVERT_VFAT2_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT2_TU_INVERT_LSB) <= TU_INVERT (23 downto 16);
    regs_read_arr(6)(REG_TRIG_CTRL_INVERT_VFAT3_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT3_TU_INVERT_LSB) <= TU_INVERT (31 downto 24);
    regs_read_arr(7)(REG_TRIG_CTRL_INVERT_VFAT4_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT4_TU_INVERT_LSB) <= TU_INVERT (39 downto 32);
    regs_read_arr(7)(REG_TRIG_CTRL_INVERT_VFAT5_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT5_TU_INVERT_LSB) <= TU_INVERT (47 downto 40);
    regs_read_arr(7)(REG_TRIG_CTRL_INVERT_VFAT6_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT6_TU_INVERT_LSB) <= TU_INVERT (55 downto 48);
    regs_read_arr(7)(REG_TRIG_CTRL_INVERT_VFAT7_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT7_TU_INVERT_LSB) <= TU_INVERT (63 downto 56);
    regs_read_arr(8)(REG_TRIG_CTRL_INVERT_VFAT8_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT8_TU_INVERT_LSB) <= TU_INVERT (71 downto 64);
    regs_read_arr(8)(REG_TRIG_CTRL_INVERT_VFAT9_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT9_TU_INVERT_LSB) <= TU_INVERT (79 downto 72);
    regs_read_arr(8)(REG_TRIG_CTRL_INVERT_VFAT10_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT10_TU_INVERT_LSB) <= TU_INVERT (87 downto 80);
    regs_read_arr(8)(REG_TRIG_CTRL_INVERT_VFAT11_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT11_TU_INVERT_LSB) <= TU_INVERT (95 downto 88);
    regs_read_arr(9)(REG_TRIG_CTRL_INVERT_VFAT12_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT12_TU_INVERT_LSB) <= TU_INVERT (103 downto 96);
    regs_read_arr(9)(REG_TRIG_CTRL_INVERT_VFAT13_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT13_TU_INVERT_LSB) <= TU_INVERT (111 downto 104);
    regs_read_arr(9)(REG_TRIG_CTRL_INVERT_VFAT14_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT14_TU_INVERT_LSB) <= TU_INVERT (119 downto 112);
    regs_read_arr(9)(REG_TRIG_CTRL_INVERT_VFAT15_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT15_TU_INVERT_LSB) <= TU_INVERT (127 downto 120);
    regs_read_arr(10)(REG_TRIG_CTRL_INVERT_VFAT16_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT16_TU_INVERT_LSB) <= TU_INVERT (135 downto 128);
    regs_read_arr(10)(REG_TRIG_CTRL_INVERT_VFAT17_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT17_TU_INVERT_LSB) <= TU_INVERT (143 downto 136);
    regs_read_arr(10)(REG_TRIG_CTRL_INVERT_VFAT18_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT18_TU_INVERT_LSB) <= TU_INVERT (151 downto 144);
    regs_read_arr(10)(REG_TRIG_CTRL_INVERT_VFAT19_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT19_TU_INVERT_LSB) <= TU_INVERT (159 downto 152);
    regs_read_arr(11)(REG_TRIG_CTRL_INVERT_VFAT20_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT20_TU_INVERT_LSB) <= TU_INVERT (167 downto 160);
    regs_read_arr(11)(REG_TRIG_CTRL_INVERT_VFAT21_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT21_TU_INVERT_LSB) <= TU_INVERT (175 downto 168);
    regs_read_arr(11)(REG_TRIG_CTRL_INVERT_VFAT22_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT22_TU_INVERT_LSB) <= TU_INVERT (183 downto 176);
    regs_read_arr(11)(REG_TRIG_CTRL_INVERT_VFAT23_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT23_TU_INVERT_LSB) <= TU_INVERT (191 downto 184);
    regs_read_arr(12)(REG_TRIG_CTRL_SBITS_MUX_SBIT_MUX_SEL_MSB downto REG_TRIG_CTRL_SBITS_MUX_SBIT_MUX_SEL_LSB) <= sbits_mux_sel;
    regs_read_arr(13)(REG_TRIG_CTRL_SBITS_MUX_SBITS_MUX_LSB_MSB downto REG_TRIG_CTRL_SBITS_MUX_SBITS_MUX_LSB_LSB) <= sbits_mux(31 downto 0);
    regs_read_arr(14)(REG_TRIG_CTRL_SBITS_MUX_SBITS_MUX_MSB_MSB downto REG_TRIG_CTRL_SBITS_MUX_SBITS_MUX_MSB_LSB) <= sbits_mux(63 downto 32);
    regs_read_arr(15)(REG_TRIG_CTRL_TU_MASK_VFAT0_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT0_TU_MASK_LSB) <= TU_MASK (7 downto 0);
    regs_read_arr(15)(REG_TRIG_CTRL_TU_MASK_VFAT1_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT1_TU_MASK_LSB) <= TU_MASK (15 downto 8);
    regs_read_arr(15)(REG_TRIG_CTRL_TU_MASK_VFAT2_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT2_TU_MASK_LSB) <= TU_MASK (23 downto 16);
    regs_read_arr(15)(REG_TRIG_CTRL_TU_MASK_VFAT3_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT3_TU_MASK_LSB) <= TU_MASK (31 downto 24);
    regs_read_arr(16)(REG_TRIG_CTRL_TU_MASK_VFAT4_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT4_TU_MASK_LSB) <= TU_MASK (39 downto 32);
    regs_read_arr(16)(REG_TRIG_CTRL_TU_MASK_VFAT5_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT5_TU_MASK_LSB) <= TU_MASK (47 downto 40);
    regs_read_arr(16)(REG_TRIG_CTRL_TU_MASK_VFAT6_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT6_TU_MASK_LSB) <= TU_MASK (55 downto 48);
    regs_read_arr(16)(REG_TRIG_CTRL_TU_MASK_VFAT7_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT7_TU_MASK_LSB) <= TU_MASK (63 downto 56);
    regs_read_arr(17)(REG_TRIG_CTRL_TU_MASK_VFAT8_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT8_TU_MASK_LSB) <= TU_MASK (71 downto 64);
    regs_read_arr(17)(REG_TRIG_CTRL_TU_MASK_VFAT9_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT9_TU_MASK_LSB) <= TU_MASK (79 downto 72);
    regs_read_arr(17)(REG_TRIG_CTRL_TU_MASK_VFAT10_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT10_TU_MASK_LSB) <= TU_MASK (87 downto 80);
    regs_read_arr(17)(REG_TRIG_CTRL_TU_MASK_VFAT11_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT11_TU_MASK_LSB) <= TU_MASK (95 downto 88);
    regs_read_arr(18)(REG_TRIG_CTRL_TU_MASK_VFAT12_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT12_TU_MASK_LSB) <= TU_MASK (103 downto 96);
    regs_read_arr(18)(REG_TRIG_CTRL_TU_MASK_VFAT13_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT13_TU_MASK_LSB) <= TU_MASK (111 downto 104);
    regs_read_arr(18)(REG_TRIG_CTRL_TU_MASK_VFAT14_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT14_TU_MASK_LSB) <= TU_MASK (119 downto 112);
    regs_read_arr(18)(REG_TRIG_CTRL_TU_MASK_VFAT15_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT15_TU_MASK_LSB) <= TU_MASK (127 downto 120);
    regs_read_arr(19)(REG_TRIG_CTRL_TU_MASK_VFAT16_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT16_TU_MASK_LSB) <= TU_MASK (135 downto 128);
    regs_read_arr(19)(REG_TRIG_CTRL_TU_MASK_VFAT17_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT17_TU_MASK_LSB) <= TU_MASK (143 downto 136);
    regs_read_arr(19)(REG_TRIG_CTRL_TU_MASK_VFAT18_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT18_TU_MASK_LSB) <= TU_MASK (151 downto 144);
    regs_read_arr(19)(REG_TRIG_CTRL_TU_MASK_VFAT19_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT19_TU_MASK_LSB) <= TU_MASK (159 downto 152);
    regs_read_arr(20)(REG_TRIG_CTRL_TU_MASK_VFAT20_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT20_TU_MASK_LSB) <= TU_MASK (167 downto 160);
    regs_read_arr(20)(REG_TRIG_CTRL_TU_MASK_VFAT21_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT21_TU_MASK_LSB) <= TU_MASK (175 downto 168);
    regs_read_arr(20)(REG_TRIG_CTRL_TU_MASK_VFAT22_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT22_TU_MASK_LSB) <= TU_MASK (183 downto 176);
    regs_read_arr(20)(REG_TRIG_CTRL_TU_MASK_VFAT23_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT23_TU_MASK_LSB) <= TU_MASK (191 downto 184);
    regs_read_arr(21)(REG_TRIG_CNT_VFAT0_MSB downto REG_TRIG_CNT_VFAT0_LSB) <= cnt_vfat0;
    regs_read_arr(22)(REG_TRIG_CNT_VFAT1_MSB downto REG_TRIG_CNT_VFAT1_LSB) <= cnt_vfat1;
    regs_read_arr(23)(REG_TRIG_CNT_VFAT2_MSB downto REG_TRIG_CNT_VFAT2_LSB) <= cnt_vfat2;
    regs_read_arr(24)(REG_TRIG_CNT_VFAT3_MSB downto REG_TRIG_CNT_VFAT3_LSB) <= cnt_vfat3;
    regs_read_arr(25)(REG_TRIG_CNT_VFAT4_MSB downto REG_TRIG_CNT_VFAT4_LSB) <= cnt_vfat4;
    regs_read_arr(26)(REG_TRIG_CNT_VFAT5_MSB downto REG_TRIG_CNT_VFAT5_LSB) <= cnt_vfat5;
    regs_read_arr(27)(REG_TRIG_CNT_VFAT6_MSB downto REG_TRIG_CNT_VFAT6_LSB) <= cnt_vfat6;
    regs_read_arr(28)(REG_TRIG_CNT_VFAT7_MSB downto REG_TRIG_CNT_VFAT7_LSB) <= cnt_vfat7;
    regs_read_arr(29)(REG_TRIG_CNT_VFAT8_MSB downto REG_TRIG_CNT_VFAT8_LSB) <= cnt_vfat8;
    regs_read_arr(30)(REG_TRIG_CNT_VFAT9_MSB downto REG_TRIG_CNT_VFAT9_LSB) <= cnt_vfat9;
    regs_read_arr(31)(REG_TRIG_CNT_VFAT10_MSB downto REG_TRIG_CNT_VFAT10_LSB) <= cnt_vfat10;
    regs_read_arr(32)(REG_TRIG_CNT_VFAT11_MSB downto REG_TRIG_CNT_VFAT11_LSB) <= cnt_vfat11;
    regs_read_arr(33)(REG_TRIG_CNT_VFAT12_MSB downto REG_TRIG_CNT_VFAT12_LSB) <= cnt_vfat12;
    regs_read_arr(34)(REG_TRIG_CNT_VFAT13_MSB downto REG_TRIG_CNT_VFAT13_LSB) <= cnt_vfat13;
    regs_read_arr(35)(REG_TRIG_CNT_VFAT14_MSB downto REG_TRIG_CNT_VFAT14_LSB) <= cnt_vfat14;
    regs_read_arr(36)(REG_TRIG_CNT_VFAT15_MSB downto REG_TRIG_CNT_VFAT15_LSB) <= cnt_vfat15;
    regs_read_arr(37)(REG_TRIG_CNT_VFAT16_MSB downto REG_TRIG_CNT_VFAT16_LSB) <= cnt_vfat16;
    regs_read_arr(38)(REG_TRIG_CNT_VFAT17_MSB downto REG_TRIG_CNT_VFAT17_LSB) <= cnt_vfat17;
    regs_read_arr(39)(REG_TRIG_CNT_VFAT18_MSB downto REG_TRIG_CNT_VFAT18_LSB) <= cnt_vfat18;
    regs_read_arr(40)(REG_TRIG_CNT_VFAT19_MSB downto REG_TRIG_CNT_VFAT19_LSB) <= cnt_vfat19;
    regs_read_arr(41)(REG_TRIG_CNT_VFAT20_MSB downto REG_TRIG_CNT_VFAT20_LSB) <= cnt_vfat20;
    regs_read_arr(42)(REG_TRIG_CNT_VFAT21_MSB downto REG_TRIG_CNT_VFAT21_LSB) <= cnt_vfat21;
    regs_read_arr(43)(REG_TRIG_CNT_VFAT22_MSB downto REG_TRIG_CNT_VFAT22_LSB) <= cnt_vfat22;
    regs_read_arr(44)(REG_TRIG_CNT_VFAT23_MSB downto REG_TRIG_CNT_VFAT23_LSB) <= cnt_vfat23;
    regs_read_arr(46)(REG_TRIG_CNT_SBIT_CNT_PERSIST_BIT) <= sbit_cnt_persist;
    regs_read_arr(47)(REG_TRIG_CNT_SBIT_CNT_TIME_MAX_MSB downto REG_TRIG_CNT_SBIT_CNT_TIME_MAX_LSB) <= sbit_cnt_time_max;
    regs_read_arr(48)(REG_TRIG_CNT_CLUSTER_COUNT_MSB downto REG_TRIG_CNT_CLUSTER_COUNT_LSB) <= cnt_clusters;
    regs_read_arr(50)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT0_LSB) <= trig_tap_delay(0);
    regs_read_arr(50)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT1_LSB) <= trig_tap_delay(1);
    regs_read_arr(50)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT2_LSB) <= trig_tap_delay(2);
    regs_read_arr(50)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT3_LSB) <= trig_tap_delay(3);
    regs_read_arr(50)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT4_LSB) <= trig_tap_delay(4);
    regs_read_arr(50)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT5_LSB) <= trig_tap_delay(5);
    regs_read_arr(51)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT6_LSB) <= trig_tap_delay(6);
    regs_read_arr(51)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT7_LSB) <= trig_tap_delay(7);
    regs_read_arr(51)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT0_LSB) <= trig_tap_delay(8);
    regs_read_arr(51)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT1_LSB) <= trig_tap_delay(9);
    regs_read_arr(51)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT2_LSB) <= trig_tap_delay(10);
    regs_read_arr(51)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT3_LSB) <= trig_tap_delay(11);
    regs_read_arr(52)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT4_LSB) <= trig_tap_delay(12);
    regs_read_arr(52)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT5_LSB) <= trig_tap_delay(13);
    regs_read_arr(52)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT6_LSB) <= trig_tap_delay(14);
    regs_read_arr(52)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT7_LSB) <= trig_tap_delay(15);
    regs_read_arr(52)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT0_LSB) <= trig_tap_delay(16);
    regs_read_arr(52)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT1_LSB) <= trig_tap_delay(17);
    regs_read_arr(53)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT2_LSB) <= trig_tap_delay(18);
    regs_read_arr(53)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT3_LSB) <= trig_tap_delay(19);
    regs_read_arr(53)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT4_LSB) <= trig_tap_delay(20);
    regs_read_arr(53)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT5_LSB) <= trig_tap_delay(21);
    regs_read_arr(53)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT6_LSB) <= trig_tap_delay(22);
    regs_read_arr(53)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT7_LSB) <= trig_tap_delay(23);
    regs_read_arr(54)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT0_LSB) <= trig_tap_delay(24);
    regs_read_arr(54)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT1_LSB) <= trig_tap_delay(25);
    regs_read_arr(54)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT2_LSB) <= trig_tap_delay(26);
    regs_read_arr(54)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT3_LSB) <= trig_tap_delay(27);
    regs_read_arr(54)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT4_LSB) <= trig_tap_delay(28);
    regs_read_arr(54)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT5_LSB) <= trig_tap_delay(29);
    regs_read_arr(55)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT6_LSB) <= trig_tap_delay(30);
    regs_read_arr(55)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT7_LSB) <= trig_tap_delay(31);
    regs_read_arr(55)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT0_LSB) <= trig_tap_delay(32);
    regs_read_arr(55)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT1_LSB) <= trig_tap_delay(33);
    regs_read_arr(55)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT2_LSB) <= trig_tap_delay(34);
    regs_read_arr(55)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT3_LSB) <= trig_tap_delay(35);
    regs_read_arr(56)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT4_LSB) <= trig_tap_delay(36);
    regs_read_arr(56)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT5_LSB) <= trig_tap_delay(37);
    regs_read_arr(56)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT6_LSB) <= trig_tap_delay(38);
    regs_read_arr(56)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT7_LSB) <= trig_tap_delay(39);
    regs_read_arr(56)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT0_LSB) <= trig_tap_delay(40);
    regs_read_arr(56)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT1_LSB) <= trig_tap_delay(41);
    regs_read_arr(57)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT2_LSB) <= trig_tap_delay(42);
    regs_read_arr(57)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT3_LSB) <= trig_tap_delay(43);
    regs_read_arr(57)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT4_LSB) <= trig_tap_delay(44);
    regs_read_arr(57)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT5_LSB) <= trig_tap_delay(45);
    regs_read_arr(57)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT6_LSB) <= trig_tap_delay(46);
    regs_read_arr(57)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT7_LSB) <= trig_tap_delay(47);
    regs_read_arr(58)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT0_LSB) <= trig_tap_delay(48);
    regs_read_arr(58)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT1_LSB) <= trig_tap_delay(49);
    regs_read_arr(58)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT2_LSB) <= trig_tap_delay(50);
    regs_read_arr(58)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT3_LSB) <= trig_tap_delay(51);
    regs_read_arr(58)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT4_LSB) <= trig_tap_delay(52);
    regs_read_arr(58)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT5_LSB) <= trig_tap_delay(53);
    regs_read_arr(59)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT6_LSB) <= trig_tap_delay(54);
    regs_read_arr(59)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT7_LSB) <= trig_tap_delay(55);
    regs_read_arr(59)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT0_LSB) <= trig_tap_delay(56);
    regs_read_arr(59)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT1_LSB) <= trig_tap_delay(57);
    regs_read_arr(59)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT2_LSB) <= trig_tap_delay(58);
    regs_read_arr(59)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT3_LSB) <= trig_tap_delay(59);
    regs_read_arr(60)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT4_LSB) <= trig_tap_delay(60);
    regs_read_arr(60)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT5_LSB) <= trig_tap_delay(61);
    regs_read_arr(60)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT6_LSB) <= trig_tap_delay(62);
    regs_read_arr(60)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT7_LSB) <= trig_tap_delay(63);
    regs_read_arr(60)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT0_LSB) <= trig_tap_delay(64);
    regs_read_arr(60)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT1_LSB) <= trig_tap_delay(65);
    regs_read_arr(61)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT2_LSB) <= trig_tap_delay(66);
    regs_read_arr(61)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT3_LSB) <= trig_tap_delay(67);
    regs_read_arr(61)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT4_LSB) <= trig_tap_delay(68);
    regs_read_arr(61)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT5_LSB) <= trig_tap_delay(69);
    regs_read_arr(61)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT6_LSB) <= trig_tap_delay(70);
    regs_read_arr(61)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT7_LSB) <= trig_tap_delay(71);
    regs_read_arr(62)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT0_LSB) <= trig_tap_delay(72);
    regs_read_arr(62)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT1_LSB) <= trig_tap_delay(73);
    regs_read_arr(62)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT2_LSB) <= trig_tap_delay(74);
    regs_read_arr(62)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT3_LSB) <= trig_tap_delay(75);
    regs_read_arr(62)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT4_LSB) <= trig_tap_delay(76);
    regs_read_arr(62)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT5_LSB) <= trig_tap_delay(77);
    regs_read_arr(63)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT6_LSB) <= trig_tap_delay(78);
    regs_read_arr(63)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT7_LSB) <= trig_tap_delay(79);
    regs_read_arr(63)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT0_LSB) <= trig_tap_delay(80);
    regs_read_arr(63)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT1_LSB) <= trig_tap_delay(81);
    regs_read_arr(63)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT2_LSB) <= trig_tap_delay(82);
    regs_read_arr(63)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT3_LSB) <= trig_tap_delay(83);
    regs_read_arr(64)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT4_LSB) <= trig_tap_delay(84);
    regs_read_arr(64)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT5_LSB) <= trig_tap_delay(85);
    regs_read_arr(64)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT6_LSB) <= trig_tap_delay(86);
    regs_read_arr(64)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT7_LSB) <= trig_tap_delay(87);
    regs_read_arr(64)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT0_LSB) <= trig_tap_delay(88);
    regs_read_arr(64)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT1_LSB) <= trig_tap_delay(89);
    regs_read_arr(65)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT2_LSB) <= trig_tap_delay(90);
    regs_read_arr(65)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT3_LSB) <= trig_tap_delay(91);
    regs_read_arr(65)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT4_LSB) <= trig_tap_delay(92);
    regs_read_arr(65)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT5_LSB) <= trig_tap_delay(93);
    regs_read_arr(65)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT6_LSB) <= trig_tap_delay(94);
    regs_read_arr(65)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT7_LSB) <= trig_tap_delay(95);
    regs_read_arr(66)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT0_LSB) <= trig_tap_delay(96);
    regs_read_arr(66)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT1_LSB) <= trig_tap_delay(97);
    regs_read_arr(66)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT2_LSB) <= trig_tap_delay(98);
    regs_read_arr(66)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT3_LSB) <= trig_tap_delay(99);
    regs_read_arr(66)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT4_LSB) <= trig_tap_delay(100);
    regs_read_arr(66)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT5_LSB) <= trig_tap_delay(101);
    regs_read_arr(67)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT6_LSB) <= trig_tap_delay(102);
    regs_read_arr(67)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT7_LSB) <= trig_tap_delay(103);
    regs_read_arr(67)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT0_LSB) <= trig_tap_delay(104);
    regs_read_arr(67)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT1_LSB) <= trig_tap_delay(105);
    regs_read_arr(67)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT2_LSB) <= trig_tap_delay(106);
    regs_read_arr(67)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT3_LSB) <= trig_tap_delay(107);
    regs_read_arr(68)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT4_LSB) <= trig_tap_delay(108);
    regs_read_arr(68)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT5_LSB) <= trig_tap_delay(109);
    regs_read_arr(68)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT6_LSB) <= trig_tap_delay(110);
    regs_read_arr(68)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT7_LSB) <= trig_tap_delay(111);
    regs_read_arr(68)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT0_LSB) <= trig_tap_delay(112);
    regs_read_arr(68)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT1_LSB) <= trig_tap_delay(113);
    regs_read_arr(69)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT2_LSB) <= trig_tap_delay(114);
    regs_read_arr(69)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT3_LSB) <= trig_tap_delay(115);
    regs_read_arr(69)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT4_LSB) <= trig_tap_delay(116);
    regs_read_arr(69)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT5_LSB) <= trig_tap_delay(117);
    regs_read_arr(69)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT6_LSB) <= trig_tap_delay(118);
    regs_read_arr(69)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT7_LSB) <= trig_tap_delay(119);
    regs_read_arr(70)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT0_LSB) <= trig_tap_delay(120);
    regs_read_arr(70)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT1_LSB) <= trig_tap_delay(121);
    regs_read_arr(70)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT2_LSB) <= trig_tap_delay(122);
    regs_read_arr(70)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT3_LSB) <= trig_tap_delay(123);
    regs_read_arr(70)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT4_LSB) <= trig_tap_delay(124);
    regs_read_arr(70)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT5_LSB) <= trig_tap_delay(125);
    regs_read_arr(71)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT6_LSB) <= trig_tap_delay(126);
    regs_read_arr(71)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT7_LSB) <= trig_tap_delay(127);
    regs_read_arr(71)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT0_LSB) <= trig_tap_delay(128);
    regs_read_arr(71)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT1_LSB) <= trig_tap_delay(129);
    regs_read_arr(71)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT2_LSB) <= trig_tap_delay(130);
    regs_read_arr(71)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT3_LSB) <= trig_tap_delay(131);
    regs_read_arr(72)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT4_LSB) <= trig_tap_delay(132);
    regs_read_arr(72)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT5_LSB) <= trig_tap_delay(133);
    regs_read_arr(72)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT6_LSB) <= trig_tap_delay(134);
    regs_read_arr(72)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT7_LSB) <= trig_tap_delay(135);
    regs_read_arr(72)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT0_LSB) <= trig_tap_delay(136);
    regs_read_arr(72)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT1_LSB) <= trig_tap_delay(137);
    regs_read_arr(73)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT2_LSB) <= trig_tap_delay(138);
    regs_read_arr(73)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT3_LSB) <= trig_tap_delay(139);
    regs_read_arr(73)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT4_LSB) <= trig_tap_delay(140);
    regs_read_arr(73)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT5_LSB) <= trig_tap_delay(141);
    regs_read_arr(73)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT6_LSB) <= trig_tap_delay(142);
    regs_read_arr(73)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT7_LSB) <= trig_tap_delay(143);
    regs_read_arr(74)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT0_LSB) <= trig_tap_delay(144);
    regs_read_arr(74)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT1_LSB) <= trig_tap_delay(145);
    regs_read_arr(74)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT2_LSB) <= trig_tap_delay(146);
    regs_read_arr(74)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT3_LSB) <= trig_tap_delay(147);
    regs_read_arr(74)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT4_LSB) <= trig_tap_delay(148);
    regs_read_arr(74)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT5_LSB) <= trig_tap_delay(149);
    regs_read_arr(75)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT6_LSB) <= trig_tap_delay(150);
    regs_read_arr(75)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT7_LSB) <= trig_tap_delay(151);
    regs_read_arr(75)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT0_LSB) <= trig_tap_delay(152);
    regs_read_arr(75)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT1_LSB) <= trig_tap_delay(153);
    regs_read_arr(75)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT2_LSB) <= trig_tap_delay(154);
    regs_read_arr(75)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT3_LSB) <= trig_tap_delay(155);
    regs_read_arr(76)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT4_LSB) <= trig_tap_delay(156);
    regs_read_arr(76)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT5_LSB) <= trig_tap_delay(157);
    regs_read_arr(76)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT6_LSB) <= trig_tap_delay(158);
    regs_read_arr(76)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT7_LSB) <= trig_tap_delay(159);
    regs_read_arr(76)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT0_LSB) <= trig_tap_delay(160);
    regs_read_arr(76)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT1_LSB) <= trig_tap_delay(161);
    regs_read_arr(77)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT2_LSB) <= trig_tap_delay(162);
    regs_read_arr(77)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT3_LSB) <= trig_tap_delay(163);
    regs_read_arr(77)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT4_LSB) <= trig_tap_delay(164);
    regs_read_arr(77)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT5_LSB) <= trig_tap_delay(165);
    regs_read_arr(77)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT6_LSB) <= trig_tap_delay(166);
    regs_read_arr(77)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT7_LSB) <= trig_tap_delay(167);
    regs_read_arr(78)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT0_LSB) <= trig_tap_delay(168);
    regs_read_arr(78)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT1_LSB) <= trig_tap_delay(169);
    regs_read_arr(78)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT2_LSB) <= trig_tap_delay(170);
    regs_read_arr(78)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT3_LSB) <= trig_tap_delay(171);
    regs_read_arr(78)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT4_LSB) <= trig_tap_delay(172);
    regs_read_arr(78)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT5_LSB) <= trig_tap_delay(173);
    regs_read_arr(79)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT6_LSB) <= trig_tap_delay(174);
    regs_read_arr(79)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT7_LSB) <= trig_tap_delay(175);
    regs_read_arr(79)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT0_LSB) <= trig_tap_delay(176);
    regs_read_arr(79)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT1_LSB) <= trig_tap_delay(177);
    regs_read_arr(79)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT2_LSB) <= trig_tap_delay(178);
    regs_read_arr(79)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT3_LSB) <= trig_tap_delay(179);
    regs_read_arr(80)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT4_LSB) <= trig_tap_delay(180);
    regs_read_arr(80)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT5_LSB) <= trig_tap_delay(181);
    regs_read_arr(80)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT6_LSB) <= trig_tap_delay(182);
    regs_read_arr(80)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT7_LSB) <= trig_tap_delay(183);
    regs_read_arr(80)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT0_LSB) <= trig_tap_delay(184);
    regs_read_arr(80)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT1_LSB) <= trig_tap_delay(185);
    regs_read_arr(81)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT2_LSB) <= trig_tap_delay(186);
    regs_read_arr(81)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT3_LSB) <= trig_tap_delay(187);
    regs_read_arr(81)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT4_LSB) <= trig_tap_delay(188);
    regs_read_arr(81)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT5_LSB) <= trig_tap_delay(189);
    regs_read_arr(81)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT6_LSB) <= trig_tap_delay(190);
    regs_read_arr(81)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT7_LSB) <= trig_tap_delay(191);
    regs_read_arr(82)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT0_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT0_LSB) <= sot_tap_delay(0);
    regs_read_arr(82)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT1_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT1_LSB) <= sot_tap_delay(1);
    regs_read_arr(82)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT2_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT2_LSB) <= sot_tap_delay(2);
    regs_read_arr(82)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT3_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT3_LSB) <= sot_tap_delay(3);
    regs_read_arr(82)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT4_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT4_LSB) <= sot_tap_delay(4);
    regs_read_arr(82)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT5_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT5_LSB) <= sot_tap_delay(5);
    regs_read_arr(83)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT6_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT6_LSB) <= sot_tap_delay(6);
    regs_read_arr(83)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT7_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT7_LSB) <= sot_tap_delay(7);
    regs_read_arr(83)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT8_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT8_LSB) <= sot_tap_delay(8);
    regs_read_arr(83)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT9_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT9_LSB) <= sot_tap_delay(9);
    regs_read_arr(83)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT10_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT10_LSB) <= sot_tap_delay(10);
    regs_read_arr(83)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT11_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT11_LSB) <= sot_tap_delay(11);
    regs_read_arr(84)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT12_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT12_LSB) <= sot_tap_delay(12);
    regs_read_arr(84)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT13_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT13_LSB) <= sot_tap_delay(13);
    regs_read_arr(84)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT14_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT14_LSB) <= sot_tap_delay(14);
    regs_read_arr(84)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT15_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT15_LSB) <= sot_tap_delay(15);
    regs_read_arr(84)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT16_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT16_LSB) <= sot_tap_delay(16);
    regs_read_arr(84)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT17_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT17_LSB) <= sot_tap_delay(17);
    regs_read_arr(85)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT18_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT18_LSB) <= sot_tap_delay(18);
    regs_read_arr(85)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT19_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT19_LSB) <= sot_tap_delay(19);
    regs_read_arr(85)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT20_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT20_LSB) <= sot_tap_delay(20);
    regs_read_arr(85)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT21_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT21_LSB) <= sot_tap_delay(21);
    regs_read_arr(85)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT22_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT22_LSB) <= sot_tap_delay(22);
    regs_read_arr(85)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT23_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT23_LSB) <= sot_tap_delay(23);
    regs_read_arr(86)(REG_TRIG_LINKS_TX_PLL_LOCKED_MSB downto REG_TRIG_LINKS_TX_PLL_LOCKED_LSB) <= tx_pll_locked;
    regs_read_arr(86)(REG_TRIG_LINKS_TX_RESET_DONE_MSB downto REG_TRIG_LINKS_TX_RESET_DONE_LSB) <= tx_reset_done;

    -- Connect write signals
    vfat_mask <= regs_write_arr(0)(REG_TRIG_CTRL_VFAT_MASK_MSB downto REG_TRIG_CTRL_VFAT_MASK_LSB);
    trig_deadtime <= regs_write_arr(0)(REG_TRIG_CTRL_SBIT_DEADTIME_MSB downto REG_TRIG_CTRL_SBIT_DEADTIME_LSB);
    aligned_count_to_ready <= regs_write_arr(2)(REG_TRIG_CTRL_ALIGNED_COUNT_TO_READY_MSB downto REG_TRIG_CTRL_ALIGNED_COUNT_TO_READY_LSB);
    sot_invert <= regs_write_arr(5)(REG_TRIG_CTRL_INVERT_SOT_INVERT_MSB downto REG_TRIG_CTRL_INVERT_SOT_INVERT_LSB);
    TU_INVERT (7 downto 0) <= regs_write_arr(6)(REG_TRIG_CTRL_INVERT_VFAT0_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT0_TU_INVERT_LSB);
    TU_INVERT (15 downto 8) <= regs_write_arr(6)(REG_TRIG_CTRL_INVERT_VFAT1_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT1_TU_INVERT_LSB);
    TU_INVERT (23 downto 16) <= regs_write_arr(6)(REG_TRIG_CTRL_INVERT_VFAT2_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT2_TU_INVERT_LSB);
    TU_INVERT (31 downto 24) <= regs_write_arr(6)(REG_TRIG_CTRL_INVERT_VFAT3_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT3_TU_INVERT_LSB);
    TU_INVERT (39 downto 32) <= regs_write_arr(7)(REG_TRIG_CTRL_INVERT_VFAT4_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT4_TU_INVERT_LSB);
    TU_INVERT (47 downto 40) <= regs_write_arr(7)(REG_TRIG_CTRL_INVERT_VFAT5_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT5_TU_INVERT_LSB);
    TU_INVERT (55 downto 48) <= regs_write_arr(7)(REG_TRIG_CTRL_INVERT_VFAT6_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT6_TU_INVERT_LSB);
    TU_INVERT (63 downto 56) <= regs_write_arr(7)(REG_TRIG_CTRL_INVERT_VFAT7_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT7_TU_INVERT_LSB);
    TU_INVERT (71 downto 64) <= regs_write_arr(8)(REG_TRIG_CTRL_INVERT_VFAT8_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT8_TU_INVERT_LSB);
    TU_INVERT (79 downto 72) <= regs_write_arr(8)(REG_TRIG_CTRL_INVERT_VFAT9_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT9_TU_INVERT_LSB);
    TU_INVERT (87 downto 80) <= regs_write_arr(8)(REG_TRIG_CTRL_INVERT_VFAT10_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT10_TU_INVERT_LSB);
    TU_INVERT (95 downto 88) <= regs_write_arr(8)(REG_TRIG_CTRL_INVERT_VFAT11_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT11_TU_INVERT_LSB);
    TU_INVERT (103 downto 96) <= regs_write_arr(9)(REG_TRIG_CTRL_INVERT_VFAT12_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT12_TU_INVERT_LSB);
    TU_INVERT (111 downto 104) <= regs_write_arr(9)(REG_TRIG_CTRL_INVERT_VFAT13_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT13_TU_INVERT_LSB);
    TU_INVERT (119 downto 112) <= regs_write_arr(9)(REG_TRIG_CTRL_INVERT_VFAT14_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT14_TU_INVERT_LSB);
    TU_INVERT (127 downto 120) <= regs_write_arr(9)(REG_TRIG_CTRL_INVERT_VFAT15_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT15_TU_INVERT_LSB);
    TU_INVERT (135 downto 128) <= regs_write_arr(10)(REG_TRIG_CTRL_INVERT_VFAT16_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT16_TU_INVERT_LSB);
    TU_INVERT (143 downto 136) <= regs_write_arr(10)(REG_TRIG_CTRL_INVERT_VFAT17_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT17_TU_INVERT_LSB);
    TU_INVERT (151 downto 144) <= regs_write_arr(10)(REG_TRIG_CTRL_INVERT_VFAT18_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT18_TU_INVERT_LSB);
    TU_INVERT (159 downto 152) <= regs_write_arr(10)(REG_TRIG_CTRL_INVERT_VFAT19_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT19_TU_INVERT_LSB);
    TU_INVERT (167 downto 160) <= regs_write_arr(11)(REG_TRIG_CTRL_INVERT_VFAT20_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT20_TU_INVERT_LSB);
    TU_INVERT (175 downto 168) <= regs_write_arr(11)(REG_TRIG_CTRL_INVERT_VFAT21_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT21_TU_INVERT_LSB);
    TU_INVERT (183 downto 176) <= regs_write_arr(11)(REG_TRIG_CTRL_INVERT_VFAT22_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT22_TU_INVERT_LSB);
    TU_INVERT (191 downto 184) <= regs_write_arr(11)(REG_TRIG_CTRL_INVERT_VFAT23_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT23_TU_INVERT_LSB);
    sbits_mux_sel <= regs_write_arr(12)(REG_TRIG_CTRL_SBITS_MUX_SBIT_MUX_SEL_MSB downto REG_TRIG_CTRL_SBITS_MUX_SBIT_MUX_SEL_LSB);
    TU_MASK (7 downto 0) <= regs_write_arr(15)(REG_TRIG_CTRL_TU_MASK_VFAT0_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT0_TU_MASK_LSB);
    TU_MASK (15 downto 8) <= regs_write_arr(15)(REG_TRIG_CTRL_TU_MASK_VFAT1_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT1_TU_MASK_LSB);
    TU_MASK (23 downto 16) <= regs_write_arr(15)(REG_TRIG_CTRL_TU_MASK_VFAT2_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT2_TU_MASK_LSB);
    TU_MASK (31 downto 24) <= regs_write_arr(15)(REG_TRIG_CTRL_TU_MASK_VFAT3_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT3_TU_MASK_LSB);
    TU_MASK (39 downto 32) <= regs_write_arr(16)(REG_TRIG_CTRL_TU_MASK_VFAT4_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT4_TU_MASK_LSB);
    TU_MASK (47 downto 40) <= regs_write_arr(16)(REG_TRIG_CTRL_TU_MASK_VFAT5_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT5_TU_MASK_LSB);
    TU_MASK (55 downto 48) <= regs_write_arr(16)(REG_TRIG_CTRL_TU_MASK_VFAT6_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT6_TU_MASK_LSB);
    TU_MASK (63 downto 56) <= regs_write_arr(16)(REG_TRIG_CTRL_TU_MASK_VFAT7_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT7_TU_MASK_LSB);
    TU_MASK (71 downto 64) <= regs_write_arr(17)(REG_TRIG_CTRL_TU_MASK_VFAT8_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT8_TU_MASK_LSB);
    TU_MASK (79 downto 72) <= regs_write_arr(17)(REG_TRIG_CTRL_TU_MASK_VFAT9_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT9_TU_MASK_LSB);
    TU_MASK (87 downto 80) <= regs_write_arr(17)(REG_TRIG_CTRL_TU_MASK_VFAT10_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT10_TU_MASK_LSB);
    TU_MASK (95 downto 88) <= regs_write_arr(17)(REG_TRIG_CTRL_TU_MASK_VFAT11_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT11_TU_MASK_LSB);
    TU_MASK (103 downto 96) <= regs_write_arr(18)(REG_TRIG_CTRL_TU_MASK_VFAT12_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT12_TU_MASK_LSB);
    TU_MASK (111 downto 104) <= regs_write_arr(18)(REG_TRIG_CTRL_TU_MASK_VFAT13_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT13_TU_MASK_LSB);
    TU_MASK (119 downto 112) <= regs_write_arr(18)(REG_TRIG_CTRL_TU_MASK_VFAT14_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT14_TU_MASK_LSB);
    TU_MASK (127 downto 120) <= regs_write_arr(18)(REG_TRIG_CTRL_TU_MASK_VFAT15_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT15_TU_MASK_LSB);
    TU_MASK (135 downto 128) <= regs_write_arr(19)(REG_TRIG_CTRL_TU_MASK_VFAT16_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT16_TU_MASK_LSB);
    TU_MASK (143 downto 136) <= regs_write_arr(19)(REG_TRIG_CTRL_TU_MASK_VFAT17_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT17_TU_MASK_LSB);
    TU_MASK (151 downto 144) <= regs_write_arr(19)(REG_TRIG_CTRL_TU_MASK_VFAT18_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT18_TU_MASK_LSB);
    TU_MASK (159 downto 152) <= regs_write_arr(19)(REG_TRIG_CTRL_TU_MASK_VFAT19_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT19_TU_MASK_LSB);
    TU_MASK (167 downto 160) <= regs_write_arr(20)(REG_TRIG_CTRL_TU_MASK_VFAT20_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT20_TU_MASK_LSB);
    TU_MASK (175 downto 168) <= regs_write_arr(20)(REG_TRIG_CTRL_TU_MASK_VFAT21_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT21_TU_MASK_LSB);
    TU_MASK (183 downto 176) <= regs_write_arr(20)(REG_TRIG_CTRL_TU_MASK_VFAT22_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT22_TU_MASK_LSB);
    TU_MASK (191 downto 184) <= regs_write_arr(20)(REG_TRIG_CTRL_TU_MASK_VFAT23_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT23_TU_MASK_LSB);
    sbit_cnt_persist <= regs_write_arr(46)(REG_TRIG_CNT_SBIT_CNT_PERSIST_BIT);
    sbit_cnt_time_max <= regs_write_arr(47)(REG_TRIG_CNT_SBIT_CNT_TIME_MAX_MSB downto REG_TRIG_CNT_SBIT_CNT_TIME_MAX_LSB);
    trig_tap_delay(0) <= regs_write_arr(50)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT0_LSB);
    trig_tap_delay(1) <= regs_write_arr(50)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT1_LSB);
    trig_tap_delay(2) <= regs_write_arr(50)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT2_LSB);
    trig_tap_delay(3) <= regs_write_arr(50)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT3_LSB);
    trig_tap_delay(4) <= regs_write_arr(50)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT4_LSB);
    trig_tap_delay(5) <= regs_write_arr(50)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT5_LSB);
    trig_tap_delay(6) <= regs_write_arr(51)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT6_LSB);
    trig_tap_delay(7) <= regs_write_arr(51)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT7_LSB);
    trig_tap_delay(8) <= regs_write_arr(51)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT0_LSB);
    trig_tap_delay(9) <= regs_write_arr(51)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT1_LSB);
    trig_tap_delay(10) <= regs_write_arr(51)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT2_LSB);
    trig_tap_delay(11) <= regs_write_arr(51)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT3_LSB);
    trig_tap_delay(12) <= regs_write_arr(52)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT4_LSB);
    trig_tap_delay(13) <= regs_write_arr(52)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT5_LSB);
    trig_tap_delay(14) <= regs_write_arr(52)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT6_LSB);
    trig_tap_delay(15) <= regs_write_arr(52)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT7_LSB);
    trig_tap_delay(16) <= regs_write_arr(52)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT0_LSB);
    trig_tap_delay(17) <= regs_write_arr(52)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT1_LSB);
    trig_tap_delay(18) <= regs_write_arr(53)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT2_LSB);
    trig_tap_delay(19) <= regs_write_arr(53)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT3_LSB);
    trig_tap_delay(20) <= regs_write_arr(53)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT4_LSB);
    trig_tap_delay(21) <= regs_write_arr(53)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT5_LSB);
    trig_tap_delay(22) <= regs_write_arr(53)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT6_LSB);
    trig_tap_delay(23) <= regs_write_arr(53)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT7_LSB);
    trig_tap_delay(24) <= regs_write_arr(54)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT0_LSB);
    trig_tap_delay(25) <= regs_write_arr(54)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT1_LSB);
    trig_tap_delay(26) <= regs_write_arr(54)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT2_LSB);
    trig_tap_delay(27) <= regs_write_arr(54)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT3_LSB);
    trig_tap_delay(28) <= regs_write_arr(54)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT4_LSB);
    trig_tap_delay(29) <= regs_write_arr(54)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT5_LSB);
    trig_tap_delay(30) <= regs_write_arr(55)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT6_LSB);
    trig_tap_delay(31) <= regs_write_arr(55)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT7_LSB);
    trig_tap_delay(32) <= regs_write_arr(55)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT0_LSB);
    trig_tap_delay(33) <= regs_write_arr(55)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT1_LSB);
    trig_tap_delay(34) <= regs_write_arr(55)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT2_LSB);
    trig_tap_delay(35) <= regs_write_arr(55)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT3_LSB);
    trig_tap_delay(36) <= regs_write_arr(56)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT4_LSB);
    trig_tap_delay(37) <= regs_write_arr(56)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT5_LSB);
    trig_tap_delay(38) <= regs_write_arr(56)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT6_LSB);
    trig_tap_delay(39) <= regs_write_arr(56)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT7_LSB);
    trig_tap_delay(40) <= regs_write_arr(56)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT0_LSB);
    trig_tap_delay(41) <= regs_write_arr(56)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT1_LSB);
    trig_tap_delay(42) <= regs_write_arr(57)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT2_LSB);
    trig_tap_delay(43) <= regs_write_arr(57)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT3_LSB);
    trig_tap_delay(44) <= regs_write_arr(57)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT4_LSB);
    trig_tap_delay(45) <= regs_write_arr(57)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT5_LSB);
    trig_tap_delay(46) <= regs_write_arr(57)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT6_LSB);
    trig_tap_delay(47) <= regs_write_arr(57)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT7_LSB);
    trig_tap_delay(48) <= regs_write_arr(58)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT0_LSB);
    trig_tap_delay(49) <= regs_write_arr(58)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT1_LSB);
    trig_tap_delay(50) <= regs_write_arr(58)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT2_LSB);
    trig_tap_delay(51) <= regs_write_arr(58)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT3_LSB);
    trig_tap_delay(52) <= regs_write_arr(58)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT4_LSB);
    trig_tap_delay(53) <= regs_write_arr(58)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT5_LSB);
    trig_tap_delay(54) <= regs_write_arr(59)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT6_LSB);
    trig_tap_delay(55) <= regs_write_arr(59)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT7_LSB);
    trig_tap_delay(56) <= regs_write_arr(59)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT0_LSB);
    trig_tap_delay(57) <= regs_write_arr(59)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT1_LSB);
    trig_tap_delay(58) <= regs_write_arr(59)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT2_LSB);
    trig_tap_delay(59) <= regs_write_arr(59)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT3_LSB);
    trig_tap_delay(60) <= regs_write_arr(60)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT4_LSB);
    trig_tap_delay(61) <= regs_write_arr(60)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT5_LSB);
    trig_tap_delay(62) <= regs_write_arr(60)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT6_LSB);
    trig_tap_delay(63) <= regs_write_arr(60)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT7_LSB);
    trig_tap_delay(64) <= regs_write_arr(60)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT0_LSB);
    trig_tap_delay(65) <= regs_write_arr(60)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT1_LSB);
    trig_tap_delay(66) <= regs_write_arr(61)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT2_LSB);
    trig_tap_delay(67) <= regs_write_arr(61)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT3_LSB);
    trig_tap_delay(68) <= regs_write_arr(61)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT4_LSB);
    trig_tap_delay(69) <= regs_write_arr(61)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT5_LSB);
    trig_tap_delay(70) <= regs_write_arr(61)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT6_LSB);
    trig_tap_delay(71) <= regs_write_arr(61)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT7_LSB);
    trig_tap_delay(72) <= regs_write_arr(62)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT0_LSB);
    trig_tap_delay(73) <= regs_write_arr(62)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT1_LSB);
    trig_tap_delay(74) <= regs_write_arr(62)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT2_LSB);
    trig_tap_delay(75) <= regs_write_arr(62)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT3_LSB);
    trig_tap_delay(76) <= regs_write_arr(62)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT4_LSB);
    trig_tap_delay(77) <= regs_write_arr(62)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT5_LSB);
    trig_tap_delay(78) <= regs_write_arr(63)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT6_LSB);
    trig_tap_delay(79) <= regs_write_arr(63)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT7_LSB);
    trig_tap_delay(80) <= regs_write_arr(63)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT0_LSB);
    trig_tap_delay(81) <= regs_write_arr(63)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT1_LSB);
    trig_tap_delay(82) <= regs_write_arr(63)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT2_LSB);
    trig_tap_delay(83) <= regs_write_arr(63)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT3_LSB);
    trig_tap_delay(84) <= regs_write_arr(64)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT4_LSB);
    trig_tap_delay(85) <= regs_write_arr(64)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT5_LSB);
    trig_tap_delay(86) <= regs_write_arr(64)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT6_LSB);
    trig_tap_delay(87) <= regs_write_arr(64)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT7_LSB);
    trig_tap_delay(88) <= regs_write_arr(64)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT0_LSB);
    trig_tap_delay(89) <= regs_write_arr(64)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT1_LSB);
    trig_tap_delay(90) <= regs_write_arr(65)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT2_LSB);
    trig_tap_delay(91) <= regs_write_arr(65)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT3_LSB);
    trig_tap_delay(92) <= regs_write_arr(65)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT4_LSB);
    trig_tap_delay(93) <= regs_write_arr(65)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT5_LSB);
    trig_tap_delay(94) <= regs_write_arr(65)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT6_LSB);
    trig_tap_delay(95) <= regs_write_arr(65)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT7_LSB);
    trig_tap_delay(96) <= regs_write_arr(66)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT0_LSB);
    trig_tap_delay(97) <= regs_write_arr(66)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT1_LSB);
    trig_tap_delay(98) <= regs_write_arr(66)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT2_LSB);
    trig_tap_delay(99) <= regs_write_arr(66)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT3_LSB);
    trig_tap_delay(100) <= regs_write_arr(66)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT4_LSB);
    trig_tap_delay(101) <= regs_write_arr(66)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT5_LSB);
    trig_tap_delay(102) <= regs_write_arr(67)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT6_LSB);
    trig_tap_delay(103) <= regs_write_arr(67)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT7_LSB);
    trig_tap_delay(104) <= regs_write_arr(67)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT0_LSB);
    trig_tap_delay(105) <= regs_write_arr(67)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT1_LSB);
    trig_tap_delay(106) <= regs_write_arr(67)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT2_LSB);
    trig_tap_delay(107) <= regs_write_arr(67)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT3_LSB);
    trig_tap_delay(108) <= regs_write_arr(68)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT4_LSB);
    trig_tap_delay(109) <= regs_write_arr(68)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT5_LSB);
    trig_tap_delay(110) <= regs_write_arr(68)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT6_LSB);
    trig_tap_delay(111) <= regs_write_arr(68)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT7_LSB);
    trig_tap_delay(112) <= regs_write_arr(68)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT0_LSB);
    trig_tap_delay(113) <= regs_write_arr(68)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT1_LSB);
    trig_tap_delay(114) <= regs_write_arr(69)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT2_LSB);
    trig_tap_delay(115) <= regs_write_arr(69)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT3_LSB);
    trig_tap_delay(116) <= regs_write_arr(69)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT4_LSB);
    trig_tap_delay(117) <= regs_write_arr(69)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT5_LSB);
    trig_tap_delay(118) <= regs_write_arr(69)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT6_LSB);
    trig_tap_delay(119) <= regs_write_arr(69)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT7_LSB);
    trig_tap_delay(120) <= regs_write_arr(70)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT0_LSB);
    trig_tap_delay(121) <= regs_write_arr(70)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT1_LSB);
    trig_tap_delay(122) <= regs_write_arr(70)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT2_LSB);
    trig_tap_delay(123) <= regs_write_arr(70)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT3_LSB);
    trig_tap_delay(124) <= regs_write_arr(70)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT4_LSB);
    trig_tap_delay(125) <= regs_write_arr(70)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT5_LSB);
    trig_tap_delay(126) <= regs_write_arr(71)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT6_LSB);
    trig_tap_delay(127) <= regs_write_arr(71)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT7_LSB);
    trig_tap_delay(128) <= regs_write_arr(71)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT0_LSB);
    trig_tap_delay(129) <= regs_write_arr(71)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT1_LSB);
    trig_tap_delay(130) <= regs_write_arr(71)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT2_LSB);
    trig_tap_delay(131) <= regs_write_arr(71)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT3_LSB);
    trig_tap_delay(132) <= regs_write_arr(72)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT4_LSB);
    trig_tap_delay(133) <= regs_write_arr(72)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT5_LSB);
    trig_tap_delay(134) <= regs_write_arr(72)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT6_LSB);
    trig_tap_delay(135) <= regs_write_arr(72)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT7_LSB);
    trig_tap_delay(136) <= regs_write_arr(72)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT0_LSB);
    trig_tap_delay(137) <= regs_write_arr(72)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT1_LSB);
    trig_tap_delay(138) <= regs_write_arr(73)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT2_LSB);
    trig_tap_delay(139) <= regs_write_arr(73)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT3_LSB);
    trig_tap_delay(140) <= regs_write_arr(73)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT4_LSB);
    trig_tap_delay(141) <= regs_write_arr(73)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT5_LSB);
    trig_tap_delay(142) <= regs_write_arr(73)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT6_LSB);
    trig_tap_delay(143) <= regs_write_arr(73)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT7_LSB);
    trig_tap_delay(144) <= regs_write_arr(74)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT0_LSB);
    trig_tap_delay(145) <= regs_write_arr(74)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT1_LSB);
    trig_tap_delay(146) <= regs_write_arr(74)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT2_LSB);
    trig_tap_delay(147) <= regs_write_arr(74)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT3_LSB);
    trig_tap_delay(148) <= regs_write_arr(74)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT4_LSB);
    trig_tap_delay(149) <= regs_write_arr(74)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT5_LSB);
    trig_tap_delay(150) <= regs_write_arr(75)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT6_LSB);
    trig_tap_delay(151) <= regs_write_arr(75)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT7_LSB);
    trig_tap_delay(152) <= regs_write_arr(75)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT0_LSB);
    trig_tap_delay(153) <= regs_write_arr(75)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT1_LSB);
    trig_tap_delay(154) <= regs_write_arr(75)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT2_LSB);
    trig_tap_delay(155) <= regs_write_arr(75)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT3_LSB);
    trig_tap_delay(156) <= regs_write_arr(76)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT4_LSB);
    trig_tap_delay(157) <= regs_write_arr(76)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT5_LSB);
    trig_tap_delay(158) <= regs_write_arr(76)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT6_LSB);
    trig_tap_delay(159) <= regs_write_arr(76)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT7_LSB);
    trig_tap_delay(160) <= regs_write_arr(76)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT0_LSB);
    trig_tap_delay(161) <= regs_write_arr(76)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT1_LSB);
    trig_tap_delay(162) <= regs_write_arr(77)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT2_LSB);
    trig_tap_delay(163) <= regs_write_arr(77)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT3_LSB);
    trig_tap_delay(164) <= regs_write_arr(77)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT4_LSB);
    trig_tap_delay(165) <= regs_write_arr(77)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT5_LSB);
    trig_tap_delay(166) <= regs_write_arr(77)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT6_LSB);
    trig_tap_delay(167) <= regs_write_arr(77)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT7_LSB);
    trig_tap_delay(168) <= regs_write_arr(78)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT0_LSB);
    trig_tap_delay(169) <= regs_write_arr(78)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT1_LSB);
    trig_tap_delay(170) <= regs_write_arr(78)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT2_LSB);
    trig_tap_delay(171) <= regs_write_arr(78)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT3_LSB);
    trig_tap_delay(172) <= regs_write_arr(78)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT4_LSB);
    trig_tap_delay(173) <= regs_write_arr(78)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT5_LSB);
    trig_tap_delay(174) <= regs_write_arr(79)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT6_LSB);
    trig_tap_delay(175) <= regs_write_arr(79)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT7_LSB);
    trig_tap_delay(176) <= regs_write_arr(79)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT0_LSB);
    trig_tap_delay(177) <= regs_write_arr(79)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT1_LSB);
    trig_tap_delay(178) <= regs_write_arr(79)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT2_LSB);
    trig_tap_delay(179) <= regs_write_arr(79)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT3_LSB);
    trig_tap_delay(180) <= regs_write_arr(80)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT4_LSB);
    trig_tap_delay(181) <= regs_write_arr(80)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT5_LSB);
    trig_tap_delay(182) <= regs_write_arr(80)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT6_LSB);
    trig_tap_delay(183) <= regs_write_arr(80)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT7_LSB);
    trig_tap_delay(184) <= regs_write_arr(80)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT0_LSB);
    trig_tap_delay(185) <= regs_write_arr(80)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT1_LSB);
    trig_tap_delay(186) <= regs_write_arr(81)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT2_LSB);
    trig_tap_delay(187) <= regs_write_arr(81)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT3_LSB);
    trig_tap_delay(188) <= regs_write_arr(81)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT4_LSB);
    trig_tap_delay(189) <= regs_write_arr(81)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT5_LSB);
    trig_tap_delay(190) <= regs_write_arr(81)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT6_LSB);
    trig_tap_delay(191) <= regs_write_arr(81)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT7_LSB);
    sot_tap_delay(0) <= regs_write_arr(82)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT0_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT0_LSB);
    sot_tap_delay(1) <= regs_write_arr(82)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT1_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT1_LSB);
    sot_tap_delay(2) <= regs_write_arr(82)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT2_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT2_LSB);
    sot_tap_delay(3) <= regs_write_arr(82)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT3_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT3_LSB);
    sot_tap_delay(4) <= regs_write_arr(82)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT4_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT4_LSB);
    sot_tap_delay(5) <= regs_write_arr(82)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT5_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT5_LSB);
    sot_tap_delay(6) <= regs_write_arr(83)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT6_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT6_LSB);
    sot_tap_delay(7) <= regs_write_arr(83)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT7_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT7_LSB);
    sot_tap_delay(8) <= regs_write_arr(83)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT8_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT8_LSB);
    sot_tap_delay(9) <= regs_write_arr(83)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT9_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT9_LSB);
    sot_tap_delay(10) <= regs_write_arr(83)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT10_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT10_LSB);
    sot_tap_delay(11) <= regs_write_arr(83)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT11_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT11_LSB);
    sot_tap_delay(12) <= regs_write_arr(84)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT12_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT12_LSB);
    sot_tap_delay(13) <= regs_write_arr(84)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT13_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT13_LSB);
    sot_tap_delay(14) <= regs_write_arr(84)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT14_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT14_LSB);
    sot_tap_delay(15) <= regs_write_arr(84)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT15_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT15_LSB);
    sot_tap_delay(16) <= regs_write_arr(84)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT16_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT16_LSB);
    sot_tap_delay(17) <= regs_write_arr(84)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT17_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT17_LSB);
    sot_tap_delay(18) <= regs_write_arr(85)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT18_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT18_LSB);
    sot_tap_delay(19) <= regs_write_arr(85)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT19_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT19_LSB);
    sot_tap_delay(20) <= regs_write_arr(85)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT20_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT20_LSB);
    sot_tap_delay(21) <= regs_write_arr(85)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT21_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT21_LSB);
    sot_tap_delay(22) <= regs_write_arr(85)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT22_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT22_LSB);
    sot_tap_delay(23) <= regs_write_arr(85)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT23_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT23_LSB);

    -- Connect write pulse signals
    reset_counters <= regs_write_pulse_arr(45);
    cnt_pulse <= regs_write_pulse_arr(49);
    reset_links <= regs_write_pulse_arr(85);

    -- Connect write done signals

    -- Connect read pulse signals

    -- Connect counter instances

    COUNTER_TRIG_CTRL_CNT_OVERFLOW : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 16
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset,
        en_i      => sbit_overflow,
        snap_i    => cnt_snap,
        count_o   => cnt_sbit_overflow
    );


    COUNTER_TRIG_CNT_VFAT0 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(0) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat0
    );


    COUNTER_TRIG_CNT_VFAT1 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(1) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat1
    );


    COUNTER_TRIG_CNT_VFAT2 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(2) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat2
    );


    COUNTER_TRIG_CNT_VFAT3 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(3) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat3
    );


    COUNTER_TRIG_CNT_VFAT4 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(4) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat4
    );


    COUNTER_TRIG_CNT_VFAT5 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(5) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat5
    );


    COUNTER_TRIG_CNT_VFAT6 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(6) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat6
    );


    COUNTER_TRIG_CNT_VFAT7 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(7) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat7
    );


    COUNTER_TRIG_CNT_VFAT8 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(8) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat8
    );


    COUNTER_TRIG_CNT_VFAT9 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(9) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat9
    );


    COUNTER_TRIG_CNT_VFAT10 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(10) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat10
    );


    COUNTER_TRIG_CNT_VFAT11 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(11) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat11
    );


    COUNTER_TRIG_CNT_VFAT12 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(12) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat12
    );


    COUNTER_TRIG_CNT_VFAT13 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(13) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat13
    );


    COUNTER_TRIG_CNT_VFAT14 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(14) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat14
    );


    COUNTER_TRIG_CNT_VFAT15 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(15) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat15
    );


    COUNTER_TRIG_CNT_VFAT16 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(16) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat16
    );


    COUNTER_TRIG_CNT_VFAT17 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(17) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat17
    );


    COUNTER_TRIG_CNT_VFAT18 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(18) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat18
    );


    COUNTER_TRIG_CNT_VFAT19 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(19) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat19
    );


    COUNTER_TRIG_CNT_VFAT20 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(20) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat20
    );


    COUNTER_TRIG_CNT_VFAT21 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(21) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat21
    );


    COUNTER_TRIG_CNT_VFAT22 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(22) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat22
    );


    COUNTER_TRIG_CNT_VFAT23 : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => active_vfats(23) or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_vfat23
    );


    COUNTER_TRIG_CNT_CLUSTER_COUNT : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 32
    )
    port map (
        ref_clk_i => clk_40,
        reset_i   => cnt_reset_strobed,
        en_i      => valid_clusters_or or cnt_pulse,
        snap_i    => sbit_cnt_snap,
        count_o   => cnt_clusters
    );


    -- Connect rate instances

    -- Connect read ready signals

    -- Defaults
    regs_defaults(0)(REG_TRIG_CTRL_VFAT_MASK_MSB downto REG_TRIG_CTRL_VFAT_MASK_LSB) <= REG_TRIG_CTRL_VFAT_MASK_DEFAULT;
    regs_defaults(0)(REG_TRIG_CTRL_SBIT_DEADTIME_MSB downto REG_TRIG_CTRL_SBIT_DEADTIME_LSB) <= REG_TRIG_CTRL_SBIT_DEADTIME_DEFAULT;
    regs_defaults(2)(REG_TRIG_CTRL_ALIGNED_COUNT_TO_READY_MSB downto REG_TRIG_CTRL_ALIGNED_COUNT_TO_READY_LSB) <= REG_TRIG_CTRL_ALIGNED_COUNT_TO_READY_DEFAULT;
    regs_defaults(5)(REG_TRIG_CTRL_INVERT_SOT_INVERT_MSB downto REG_TRIG_CTRL_INVERT_SOT_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_SOT_INVERT_DEFAULT;
    regs_defaults(6)(REG_TRIG_CTRL_INVERT_VFAT0_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT0_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT0_TU_INVERT_DEFAULT;
    regs_defaults(6)(REG_TRIG_CTRL_INVERT_VFAT1_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT1_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT1_TU_INVERT_DEFAULT;
    regs_defaults(6)(REG_TRIG_CTRL_INVERT_VFAT2_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT2_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT2_TU_INVERT_DEFAULT;
    regs_defaults(6)(REG_TRIG_CTRL_INVERT_VFAT3_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT3_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT3_TU_INVERT_DEFAULT;
    regs_defaults(7)(REG_TRIG_CTRL_INVERT_VFAT4_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT4_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT4_TU_INVERT_DEFAULT;
    regs_defaults(7)(REG_TRIG_CTRL_INVERT_VFAT5_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT5_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT5_TU_INVERT_DEFAULT;
    regs_defaults(7)(REG_TRIG_CTRL_INVERT_VFAT6_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT6_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT6_TU_INVERT_DEFAULT;
    regs_defaults(7)(REG_TRIG_CTRL_INVERT_VFAT7_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT7_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT7_TU_INVERT_DEFAULT;
    regs_defaults(8)(REG_TRIG_CTRL_INVERT_VFAT8_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT8_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT8_TU_INVERT_DEFAULT;
    regs_defaults(8)(REG_TRIG_CTRL_INVERT_VFAT9_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT9_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT9_TU_INVERT_DEFAULT;
    regs_defaults(8)(REG_TRIG_CTRL_INVERT_VFAT10_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT10_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT10_TU_INVERT_DEFAULT;
    regs_defaults(8)(REG_TRIG_CTRL_INVERT_VFAT11_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT11_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT11_TU_INVERT_DEFAULT;
    regs_defaults(9)(REG_TRIG_CTRL_INVERT_VFAT12_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT12_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT12_TU_INVERT_DEFAULT;
    regs_defaults(9)(REG_TRIG_CTRL_INVERT_VFAT13_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT13_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT13_TU_INVERT_DEFAULT;
    regs_defaults(9)(REG_TRIG_CTRL_INVERT_VFAT14_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT14_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT14_TU_INVERT_DEFAULT;
    regs_defaults(9)(REG_TRIG_CTRL_INVERT_VFAT15_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT15_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT15_TU_INVERT_DEFAULT;
    regs_defaults(10)(REG_TRIG_CTRL_INVERT_VFAT16_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT16_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT16_TU_INVERT_DEFAULT;
    regs_defaults(10)(REG_TRIG_CTRL_INVERT_VFAT17_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT17_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT17_TU_INVERT_DEFAULT;
    regs_defaults(10)(REG_TRIG_CTRL_INVERT_VFAT18_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT18_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT18_TU_INVERT_DEFAULT;
    regs_defaults(10)(REG_TRIG_CTRL_INVERT_VFAT19_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT19_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT19_TU_INVERT_DEFAULT;
    regs_defaults(11)(REG_TRIG_CTRL_INVERT_VFAT20_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT20_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT20_TU_INVERT_DEFAULT;
    regs_defaults(11)(REG_TRIG_CTRL_INVERT_VFAT21_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT21_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT21_TU_INVERT_DEFAULT;
    regs_defaults(11)(REG_TRIG_CTRL_INVERT_VFAT22_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT22_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT22_TU_INVERT_DEFAULT;
    regs_defaults(11)(REG_TRIG_CTRL_INVERT_VFAT23_TU_INVERT_MSB downto REG_TRIG_CTRL_INVERT_VFAT23_TU_INVERT_LSB) <= REG_TRIG_CTRL_INVERT_VFAT23_TU_INVERT_DEFAULT;
    regs_defaults(12)(REG_TRIG_CTRL_SBITS_MUX_SBIT_MUX_SEL_MSB downto REG_TRIG_CTRL_SBITS_MUX_SBIT_MUX_SEL_LSB) <= REG_TRIG_CTRL_SBITS_MUX_SBIT_MUX_SEL_DEFAULT;
    regs_defaults(15)(REG_TRIG_CTRL_TU_MASK_VFAT0_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT0_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT0_TU_MASK_DEFAULT;
    regs_defaults(15)(REG_TRIG_CTRL_TU_MASK_VFAT1_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT1_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT1_TU_MASK_DEFAULT;
    regs_defaults(15)(REG_TRIG_CTRL_TU_MASK_VFAT2_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT2_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT2_TU_MASK_DEFAULT;
    regs_defaults(15)(REG_TRIG_CTRL_TU_MASK_VFAT3_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT3_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT3_TU_MASK_DEFAULT;
    regs_defaults(16)(REG_TRIG_CTRL_TU_MASK_VFAT4_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT4_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT4_TU_MASK_DEFAULT;
    regs_defaults(16)(REG_TRIG_CTRL_TU_MASK_VFAT5_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT5_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT5_TU_MASK_DEFAULT;
    regs_defaults(16)(REG_TRIG_CTRL_TU_MASK_VFAT6_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT6_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT6_TU_MASK_DEFAULT;
    regs_defaults(16)(REG_TRIG_CTRL_TU_MASK_VFAT7_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT7_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT7_TU_MASK_DEFAULT;
    regs_defaults(17)(REG_TRIG_CTRL_TU_MASK_VFAT8_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT8_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT8_TU_MASK_DEFAULT;
    regs_defaults(17)(REG_TRIG_CTRL_TU_MASK_VFAT9_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT9_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT9_TU_MASK_DEFAULT;
    regs_defaults(17)(REG_TRIG_CTRL_TU_MASK_VFAT10_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT10_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT10_TU_MASK_DEFAULT;
    regs_defaults(17)(REG_TRIG_CTRL_TU_MASK_VFAT11_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT11_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT11_TU_MASK_DEFAULT;
    regs_defaults(18)(REG_TRIG_CTRL_TU_MASK_VFAT12_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT12_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT12_TU_MASK_DEFAULT;
    regs_defaults(18)(REG_TRIG_CTRL_TU_MASK_VFAT13_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT13_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT13_TU_MASK_DEFAULT;
    regs_defaults(18)(REG_TRIG_CTRL_TU_MASK_VFAT14_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT14_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT14_TU_MASK_DEFAULT;
    regs_defaults(18)(REG_TRIG_CTRL_TU_MASK_VFAT15_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT15_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT15_TU_MASK_DEFAULT;
    regs_defaults(19)(REG_TRIG_CTRL_TU_MASK_VFAT16_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT16_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT16_TU_MASK_DEFAULT;
    regs_defaults(19)(REG_TRIG_CTRL_TU_MASK_VFAT17_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT17_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT17_TU_MASK_DEFAULT;
    regs_defaults(19)(REG_TRIG_CTRL_TU_MASK_VFAT18_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT18_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT18_TU_MASK_DEFAULT;
    regs_defaults(19)(REG_TRIG_CTRL_TU_MASK_VFAT19_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT19_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT19_TU_MASK_DEFAULT;
    regs_defaults(20)(REG_TRIG_CTRL_TU_MASK_VFAT20_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT20_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT20_TU_MASK_DEFAULT;
    regs_defaults(20)(REG_TRIG_CTRL_TU_MASK_VFAT21_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT21_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT21_TU_MASK_DEFAULT;
    regs_defaults(20)(REG_TRIG_CTRL_TU_MASK_VFAT22_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT22_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT22_TU_MASK_DEFAULT;
    regs_defaults(20)(REG_TRIG_CTRL_TU_MASK_VFAT23_TU_MASK_MSB downto REG_TRIG_CTRL_TU_MASK_VFAT23_TU_MASK_LSB) <= REG_TRIG_CTRL_TU_MASK_VFAT23_TU_MASK_DEFAULT;
    regs_defaults(46)(REG_TRIG_CNT_SBIT_CNT_PERSIST_BIT) <= REG_TRIG_CNT_SBIT_CNT_PERSIST_DEFAULT;
    regs_defaults(47)(REG_TRIG_CNT_SBIT_CNT_TIME_MAX_MSB downto REG_TRIG_CNT_SBIT_CNT_TIME_MAX_LSB) <= REG_TRIG_CNT_SBIT_CNT_TIME_MAX_DEFAULT;
    regs_defaults(50)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT0_DEFAULT;
    regs_defaults(50)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT1_DEFAULT;
    regs_defaults(50)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT2_DEFAULT;
    regs_defaults(50)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT3_DEFAULT;
    regs_defaults(50)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT4_DEFAULT;
    regs_defaults(50)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT5_DEFAULT;
    regs_defaults(51)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT6_DEFAULT;
    regs_defaults(51)(REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT0_BIT7_DEFAULT;
    regs_defaults(51)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT0_DEFAULT;
    regs_defaults(51)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT1_DEFAULT;
    regs_defaults(51)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT2_DEFAULT;
    regs_defaults(51)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT3_DEFAULT;
    regs_defaults(52)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT4_DEFAULT;
    regs_defaults(52)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT5_DEFAULT;
    regs_defaults(52)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT6_DEFAULT;
    regs_defaults(52)(REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT1_BIT7_DEFAULT;
    regs_defaults(52)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT0_DEFAULT;
    regs_defaults(52)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT1_DEFAULT;
    regs_defaults(53)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT2_DEFAULT;
    regs_defaults(53)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT3_DEFAULT;
    regs_defaults(53)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT4_DEFAULT;
    regs_defaults(53)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT5_DEFAULT;
    regs_defaults(53)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT6_DEFAULT;
    regs_defaults(53)(REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT2_BIT7_DEFAULT;
    regs_defaults(54)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT0_DEFAULT;
    regs_defaults(54)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT1_DEFAULT;
    regs_defaults(54)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT2_DEFAULT;
    regs_defaults(54)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT3_DEFAULT;
    regs_defaults(54)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT4_DEFAULT;
    regs_defaults(54)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT5_DEFAULT;
    regs_defaults(55)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT6_DEFAULT;
    regs_defaults(55)(REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT3_BIT7_DEFAULT;
    regs_defaults(55)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT0_DEFAULT;
    regs_defaults(55)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT1_DEFAULT;
    regs_defaults(55)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT2_DEFAULT;
    regs_defaults(55)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT3_DEFAULT;
    regs_defaults(56)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT4_DEFAULT;
    regs_defaults(56)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT5_DEFAULT;
    regs_defaults(56)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT6_DEFAULT;
    regs_defaults(56)(REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT4_BIT7_DEFAULT;
    regs_defaults(56)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT0_DEFAULT;
    regs_defaults(56)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT1_DEFAULT;
    regs_defaults(57)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT2_DEFAULT;
    regs_defaults(57)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT3_DEFAULT;
    regs_defaults(57)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT4_DEFAULT;
    regs_defaults(57)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT5_DEFAULT;
    regs_defaults(57)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT6_DEFAULT;
    regs_defaults(57)(REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT5_BIT7_DEFAULT;
    regs_defaults(58)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT0_DEFAULT;
    regs_defaults(58)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT1_DEFAULT;
    regs_defaults(58)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT2_DEFAULT;
    regs_defaults(58)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT3_DEFAULT;
    regs_defaults(58)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT4_DEFAULT;
    regs_defaults(58)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT5_DEFAULT;
    regs_defaults(59)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT6_DEFAULT;
    regs_defaults(59)(REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT6_BIT7_DEFAULT;
    regs_defaults(59)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT0_DEFAULT;
    regs_defaults(59)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT1_DEFAULT;
    regs_defaults(59)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT2_DEFAULT;
    regs_defaults(59)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT3_DEFAULT;
    regs_defaults(60)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT4_DEFAULT;
    regs_defaults(60)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT5_DEFAULT;
    regs_defaults(60)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT6_DEFAULT;
    regs_defaults(60)(REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT7_BIT7_DEFAULT;
    regs_defaults(60)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT0_DEFAULT;
    regs_defaults(60)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT1_DEFAULT;
    regs_defaults(61)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT2_DEFAULT;
    regs_defaults(61)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT3_DEFAULT;
    regs_defaults(61)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT4_DEFAULT;
    regs_defaults(61)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT5_DEFAULT;
    regs_defaults(61)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT6_DEFAULT;
    regs_defaults(61)(REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT8_BIT7_DEFAULT;
    regs_defaults(62)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT0_DEFAULT;
    regs_defaults(62)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT1_DEFAULT;
    regs_defaults(62)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT2_DEFAULT;
    regs_defaults(62)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT3_DEFAULT;
    regs_defaults(62)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT4_DEFAULT;
    regs_defaults(62)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT5_DEFAULT;
    regs_defaults(63)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT6_DEFAULT;
    regs_defaults(63)(REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT9_BIT7_DEFAULT;
    regs_defaults(63)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT0_DEFAULT;
    regs_defaults(63)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT1_DEFAULT;
    regs_defaults(63)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT2_DEFAULT;
    regs_defaults(63)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT3_DEFAULT;
    regs_defaults(64)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT4_DEFAULT;
    regs_defaults(64)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT5_DEFAULT;
    regs_defaults(64)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT6_DEFAULT;
    regs_defaults(64)(REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT10_BIT7_DEFAULT;
    regs_defaults(64)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT0_DEFAULT;
    regs_defaults(64)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT1_DEFAULT;
    regs_defaults(65)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT2_DEFAULT;
    regs_defaults(65)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT3_DEFAULT;
    regs_defaults(65)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT4_DEFAULT;
    regs_defaults(65)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT5_DEFAULT;
    regs_defaults(65)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT6_DEFAULT;
    regs_defaults(65)(REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT11_BIT7_DEFAULT;
    regs_defaults(66)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT0_DEFAULT;
    regs_defaults(66)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT1_DEFAULT;
    regs_defaults(66)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT2_DEFAULT;
    regs_defaults(66)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT3_DEFAULT;
    regs_defaults(66)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT4_DEFAULT;
    regs_defaults(66)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT5_DEFAULT;
    regs_defaults(67)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT6_DEFAULT;
    regs_defaults(67)(REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT12_BIT7_DEFAULT;
    regs_defaults(67)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT0_DEFAULT;
    regs_defaults(67)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT1_DEFAULT;
    regs_defaults(67)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT2_DEFAULT;
    regs_defaults(67)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT3_DEFAULT;
    regs_defaults(68)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT4_DEFAULT;
    regs_defaults(68)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT5_DEFAULT;
    regs_defaults(68)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT6_DEFAULT;
    regs_defaults(68)(REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT13_BIT7_DEFAULT;
    regs_defaults(68)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT0_DEFAULT;
    regs_defaults(68)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT1_DEFAULT;
    regs_defaults(69)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT2_DEFAULT;
    regs_defaults(69)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT3_DEFAULT;
    regs_defaults(69)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT4_DEFAULT;
    regs_defaults(69)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT5_DEFAULT;
    regs_defaults(69)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT6_DEFAULT;
    regs_defaults(69)(REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT14_BIT7_DEFAULT;
    regs_defaults(70)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT0_DEFAULT;
    regs_defaults(70)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT1_DEFAULT;
    regs_defaults(70)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT2_DEFAULT;
    regs_defaults(70)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT3_DEFAULT;
    regs_defaults(70)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT4_DEFAULT;
    regs_defaults(70)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT5_DEFAULT;
    regs_defaults(71)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT6_DEFAULT;
    regs_defaults(71)(REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT15_BIT7_DEFAULT;
    regs_defaults(71)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT0_DEFAULT;
    regs_defaults(71)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT1_DEFAULT;
    regs_defaults(71)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT2_DEFAULT;
    regs_defaults(71)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT3_DEFAULT;
    regs_defaults(72)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT4_DEFAULT;
    regs_defaults(72)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT5_DEFAULT;
    regs_defaults(72)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT6_DEFAULT;
    regs_defaults(72)(REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT16_BIT7_DEFAULT;
    regs_defaults(72)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT0_DEFAULT;
    regs_defaults(72)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT1_DEFAULT;
    regs_defaults(73)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT2_DEFAULT;
    regs_defaults(73)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT3_DEFAULT;
    regs_defaults(73)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT4_DEFAULT;
    regs_defaults(73)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT5_DEFAULT;
    regs_defaults(73)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT6_DEFAULT;
    regs_defaults(73)(REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT17_BIT7_DEFAULT;
    regs_defaults(74)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT0_DEFAULT;
    regs_defaults(74)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT1_DEFAULT;
    regs_defaults(74)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT2_DEFAULT;
    regs_defaults(74)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT3_DEFAULT;
    regs_defaults(74)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT4_DEFAULT;
    regs_defaults(74)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT5_DEFAULT;
    regs_defaults(75)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT6_DEFAULT;
    regs_defaults(75)(REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT18_BIT7_DEFAULT;
    regs_defaults(75)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT0_DEFAULT;
    regs_defaults(75)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT1_DEFAULT;
    regs_defaults(75)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT2_DEFAULT;
    regs_defaults(75)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT3_DEFAULT;
    regs_defaults(76)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT4_DEFAULT;
    regs_defaults(76)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT5_DEFAULT;
    regs_defaults(76)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT6_DEFAULT;
    regs_defaults(76)(REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT19_BIT7_DEFAULT;
    regs_defaults(76)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT0_DEFAULT;
    regs_defaults(76)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT1_DEFAULT;
    regs_defaults(77)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT2_DEFAULT;
    regs_defaults(77)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT3_DEFAULT;
    regs_defaults(77)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT4_DEFAULT;
    regs_defaults(77)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT5_DEFAULT;
    regs_defaults(77)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT6_DEFAULT;
    regs_defaults(77)(REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT20_BIT7_DEFAULT;
    regs_defaults(78)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT0_DEFAULT;
    regs_defaults(78)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT1_DEFAULT;
    regs_defaults(78)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT2_DEFAULT;
    regs_defaults(78)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT3_DEFAULT;
    regs_defaults(78)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT4_DEFAULT;
    regs_defaults(78)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT5_DEFAULT;
    regs_defaults(79)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT6_DEFAULT;
    regs_defaults(79)(REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT21_BIT7_DEFAULT;
    regs_defaults(79)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT0_DEFAULT;
    regs_defaults(79)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT1_DEFAULT;
    regs_defaults(79)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT2_DEFAULT;
    regs_defaults(79)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT3_DEFAULT;
    regs_defaults(80)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT4_DEFAULT;
    regs_defaults(80)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT5_DEFAULT;
    regs_defaults(80)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT6_DEFAULT;
    regs_defaults(80)(REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT22_BIT7_DEFAULT;
    regs_defaults(80)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT0_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT0_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT0_DEFAULT;
    regs_defaults(80)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT1_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT1_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT1_DEFAULT;
    regs_defaults(81)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT2_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT2_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT2_DEFAULT;
    regs_defaults(81)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT3_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT3_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT3_DEFAULT;
    regs_defaults(81)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT4_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT4_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT4_DEFAULT;
    regs_defaults(81)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT5_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT5_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT5_DEFAULT;
    regs_defaults(81)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT6_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT6_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT6_DEFAULT;
    regs_defaults(81)(REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT7_MSB downto REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT7_LSB) <= REG_TRIG_TIMING_TAP_DELAY_VFAT23_BIT7_DEFAULT;
    regs_defaults(82)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT0_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT0_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT0_DEFAULT;
    regs_defaults(82)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT1_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT1_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT1_DEFAULT;
    regs_defaults(82)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT2_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT2_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT2_DEFAULT;
    regs_defaults(82)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT3_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT3_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT3_DEFAULT;
    regs_defaults(82)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT4_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT4_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT4_DEFAULT;
    regs_defaults(82)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT5_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT5_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT5_DEFAULT;
    regs_defaults(83)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT6_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT6_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT6_DEFAULT;
    regs_defaults(83)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT7_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT7_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT7_DEFAULT;
    regs_defaults(83)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT8_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT8_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT8_DEFAULT;
    regs_defaults(83)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT9_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT9_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT9_DEFAULT;
    regs_defaults(83)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT10_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT10_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT10_DEFAULT;
    regs_defaults(83)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT11_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT11_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT11_DEFAULT;
    regs_defaults(84)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT12_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT12_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT12_DEFAULT;
    regs_defaults(84)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT13_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT13_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT13_DEFAULT;
    regs_defaults(84)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT14_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT14_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT14_DEFAULT;
    regs_defaults(84)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT15_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT15_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT15_DEFAULT;
    regs_defaults(84)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT16_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT16_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT16_DEFAULT;
    regs_defaults(84)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT17_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT17_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT17_DEFAULT;
    regs_defaults(85)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT18_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT18_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT18_DEFAULT;
    regs_defaults(85)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT19_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT19_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT19_DEFAULT;
    regs_defaults(85)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT20_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT20_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT20_DEFAULT;
    regs_defaults(85)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT21_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT21_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT21_DEFAULT;
    regs_defaults(85)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT22_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT22_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT22_DEFAULT;
    regs_defaults(85)(REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT23_MSB downto REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT23_LSB) <= REG_TRIG_TIMING_SOT_TAP_DELAY_VFAT23_DEFAULT;

    -- Define writable regs
    regs_writable_arr(0) <= '1';
    regs_writable_arr(2) <= '1';
    regs_writable_arr(5) <= '1';
    regs_writable_arr(6) <= '1';
    regs_writable_arr(7) <= '1';
    regs_writable_arr(8) <= '1';
    regs_writable_arr(9) <= '1';
    regs_writable_arr(10) <= '1';
    regs_writable_arr(11) <= '1';
    regs_writable_arr(12) <= '1';
    regs_writable_arr(15) <= '1';
    regs_writable_arr(16) <= '1';
    regs_writable_arr(17) <= '1';
    regs_writable_arr(18) <= '1';
    regs_writable_arr(19) <= '1';
    regs_writable_arr(20) <= '1';
    regs_writable_arr(46) <= '1';
    regs_writable_arr(47) <= '1';
    regs_writable_arr(50) <= '1';
    regs_writable_arr(51) <= '1';
    regs_writable_arr(52) <= '1';
    regs_writable_arr(53) <= '1';
    regs_writable_arr(54) <= '1';
    regs_writable_arr(55) <= '1';
    regs_writable_arr(56) <= '1';
    regs_writable_arr(57) <= '1';
    regs_writable_arr(58) <= '1';
    regs_writable_arr(59) <= '1';
    regs_writable_arr(60) <= '1';
    regs_writable_arr(61) <= '1';
    regs_writable_arr(62) <= '1';
    regs_writable_arr(63) <= '1';
    regs_writable_arr(64) <= '1';
    regs_writable_arr(65) <= '1';
    regs_writable_arr(66) <= '1';
    regs_writable_arr(67) <= '1';
    regs_writable_arr(68) <= '1';
    regs_writable_arr(69) <= '1';
    regs_writable_arr(70) <= '1';
    regs_writable_arr(71) <= '1';
    regs_writable_arr(72) <= '1';
    regs_writable_arr(73) <= '1';
    regs_writable_arr(74) <= '1';
    regs_writable_arr(75) <= '1';
    regs_writable_arr(76) <= '1';
    regs_writable_arr(77) <= '1';
    regs_writable_arr(78) <= '1';
    regs_writable_arr(79) <= '1';
    regs_writable_arr(80) <= '1';
    regs_writable_arr(81) <= '1';
    regs_writable_arr(82) <= '1';
    regs_writable_arr(83) <= '1';
    regs_writable_arr(84) <= '1';
    regs_writable_arr(85) <= '1';

    --==== Registers end ============================================================================

end Behavioral;
