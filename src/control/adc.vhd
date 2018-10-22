----------------------------------------------------------------------------------
-- CMS Muon Endcap
-- GEM Collaboration
-- Optohybrid v3 Firmware -- System Monitor
-- T. Lenzi, A. Peck
----------------------------------------------------------------------------------
-- 2017/08/08 -- Remove auxillary inputs, add alarms
-- 2018/09/18 -- Add ipbus originating resets to counters & module
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.types_pkg.all;
use work.ipbus_pkg.all;
use work.param_pkg.all;
use work.registers.all;

entity adc is
port(

    clock_i       : in std_logic;
    reset_i         : in std_logic;

    -- IPbus
    ipb_reset_i       : in  std_logic;
    ipb_clk_i         : in  std_logic;
    ipb_mosi_i        : in  ipb_wbus;
    ipb_miso_o        : out ipb_rbus;

    -- Analog input
    adc_vp         : in  std_logic;
    adc_vn         : in  std_logic;

    cnt_snap : in std_logic

);
end adc;

architecture Behavioral of adc is
    --====================--
    --== System Monitor ==--
    --====================--

    signal reset : std_logic;

    signal daddr        : std_logic_vector  (6 downto 0);
    signal data_in      : std_logic_vector (15 downto 0);
    signal data_out     : std_logic_vector (15 downto 0);
    signal den          : std_logic;
    signal den_os       : std_logic;
    signal data_ready   : std_logic;
    signal reset_local  : std_logic;
    signal write_en     : std_logic;
    signal write_en_os  : std_logic; --write_en oneshot for Vivado bug https://www.xilinx.com/support/answers/67468.html
    signal overtemp     : std_logic;
    signal vccaux_alarm : std_logic;
    signal vccint_alarm : std_logic;

    component xadc
        port (
            daddr_in            : in   std_logic_vector (6 downto 0);  -- address bus for the dynamic reconfiguration port
            dclk_in             : in   std_logic;                      -- clock input for the dynamic reconfiguration port
            den_in              : in   std_logic;                      -- enable signal for the dynamic reconfiguration port
            di_in               : in   std_logic_vector (15 downto 0); -- input data bus for the dynamic reconfiguration port
            dwe_in              : in   std_logic;                      -- write enable for the dynamic reconfiguration port
            reset_in            : in   std_logic;                      -- reset signal for the system monitor control logic
            busy_out            : out  std_logic;                      -- adc busy signal
            channel_out         : out  std_logic_vector (4 downto 0);  -- channel selection outputs
            do_out              : out  std_logic_vector (15 downto 0); -- output data bus for dynamic reconfiguration port
            drdy_out            : out  std_logic;                      -- data ready signal for the dynamic reconfiguration port
            eoc_out             : out  std_logic;                      -- end of conversion signal
            eos_out             : out  std_logic;                      -- end of sequence signal
            vp_in               : in   std_logic;                      -- dedicated analog input pair
            vn_in               : in   std_logic;                      --
            ot_out              : out  std_logic;                      -- over-temperature alarm output
            vccaux_alarm_out    : out  std_logic;                      -- vccaux-sensor alarm output
            vccint_alarm_out    : out  std_logic                       -- vccint-sensor alarm output
    );
    end component;


    component xadc_a7
    port (
        daddr_in    : in  std_logic_vector(6 downto 0);
        dclk_in     : in  std_logic;
        den_in      : in  std_logic;
        di_in       : in  std_logic_vector(15 downto 0);
        dwe_in      : in  std_logic;
        reset_in    : in  std_logic;
        busy_out    : out std_logic;
        channel_out : out std_logic_vector(4 downto 0);
        do_out      : out std_logic_vector(15 downto 0);
        drdy_out    : out std_logic;
        eoc_out     : out std_logic;
        eos_out     : out std_logic;
        vp_in       : in  std_logic;
        vn_in       : in  std_logic;
        ot_out      : out std_logic;

        user_temp_alarm_out : out std_logic;
        alarm_out : out std_logic;

        vccaux_alarm_out : out std_logic;
        vccint_alarm_out : out std_logic
    );
    end component;

    ------ Register signals begin (this section is generated by <optohybrid_top>/tools/generate_registers.py -- do not edit)
    signal regs_read_arr        : t_std32_array(REG_ADC_NUM_REGS - 1 downto 0);
    signal regs_write_arr       : t_std32_array(REG_ADC_NUM_REGS - 1 downto 0);
    signal regs_addresses       : t_std32_array(REG_ADC_NUM_REGS - 1 downto 0);
    signal regs_defaults        : t_std32_array(REG_ADC_NUM_REGS - 1 downto 0) := (others => (others => '0'));
    signal regs_read_pulse_arr  : std_logic_vector(REG_ADC_NUM_REGS - 1 downto 0);
    signal regs_write_pulse_arr : std_logic_vector(REG_ADC_NUM_REGS - 1 downto 0);
    signal regs_read_ready_arr  : std_logic_vector(REG_ADC_NUM_REGS - 1 downto 0) := (others => '1');
    signal regs_write_done_arr  : std_logic_vector(REG_ADC_NUM_REGS - 1 downto 0) := (others => '1');
    signal regs_writable_arr    : std_logic_vector(REG_ADC_NUM_REGS - 1 downto 0) := (others => '0');
    -- Connect counter signal declarations
    signal cnt_overtemp : std_logic_vector (6 downto 0) := (others => '0');
    signal cnt_vccaux_alarm : std_logic_vector (6 downto 0) := (others => '0');
    signal cnt_vccint_alarm : std_logic_vector (6 downto 0) := (others => '0');
    ------ Register signals end ----------------------------------------------

begin

    -- Note: The read/write operation is not valid or complete until the DRDY signal goes active.

    process (clock_i) begin
        if (rising_edge(clock_i)) then
            if (write_en_os='1') then write_en_os<='0';
            elsif (data_ready='1' and write_en='1') then write_en_os<='1';
            else                      write_en_os<='0';
            end if;

            if (den_os='1') then den_os<='0';
            elsif (data_ready='1' and den='1') then den_os<='1';
            else                 den_os<='0';
            end if;
        end if;
    end process;

    process (clock_i) begin
        if (rising_edge(clock_i)) then
            reset <= reset_i or reset_local;
        end if;
    end process;

    xadc_gen : IF (FPGA_TYPE="VIRTEX6") GENERATE

    xadc_inst : xadc
    port map(
        daddr_in         => daddr,        -- Address bus for the dynamic reconfiguration port
        dclk_in          => clock_i,      -- Clock input for the dynamic reconfiguration port
        den_in           => den_os,       -- Enable Signal for the dynamic reconfiguration port
        di_in            => data_in,      -- Input data bus for the dynamic reconfiguration port
        dwe_in           => write_en_os,  -- Write Enable for the dynamic reconfiguration port
        reset_in         => reset,        -- Reset signal for the System Monitor control logic
        busy_out         => open,         -- ADC Busy signal
        channel_out      => open,         -- Channel Selection Outputs
        do_out           => data_out,     -- Output data bus for dynamic reconfiguration port
        drdy_out         => data_ready,   -- Data ready signal for the dynamic reconfiguration port
        eoc_out          => open,         -- End of Conversion Signal
        eos_out          => open,         -- End of Sequence Signal
        vp_in            => adc_vp,       -- Dedicated Analog Input Pair
        vn_in            => adc_vn,       --
        ot_out           => overtemp,     -- Over-Temperature alarm output
        vccaux_alarm_out => vccaux_alarm, -- VCCAUX-sensor alarm output
        vccint_alarm_out => vccint_alarm  -- VCCINT-sensor alarm output
    );

    END GENERATE xadc_gen;

    xadc_gen_a7 : IF (FPGA_TYPE="ARTIX7") GENERATE

    xadc_inst : xadc_a7
    port map(
        daddr_in            => daddr,        -- Address bus for the dynamic reconfiguration port
        dclk_in             => clock_i,      -- Clock input for the dynamic reconfiguration port
        den_in              => den_os,       -- Enable Signal for the dynamic reconfiguration port
        di_in               => data_in,      -- Input data bus for the dynamic reconfiguration port
        dwe_in              => write_en_os,  -- Write Enable for the dynamic reconfiguration port
        reset_in            => reset,        -- Reset signal for the System Monitor control logic
        busy_out            => open,         -- ADC Busy signal
        channel_out         => open,         -- Channel Selection Outputs
        do_out              => data_out,     -- Output data bus for dynamic reconfiguration port
        drdy_out            => data_ready,   -- Data ready signal for the dynamic reconfiguration port
        eoc_out             => open,         -- End of Conversion Signal
        eos_out             => open,         -- End of Sequence Signal
        vp_in               => adc_vp,       -- Dedicated Analog Input Pair
        vn_in               => adc_vn,       --
        alarm_out           => overtemp,     -- Over-Temperature alarm output
        user_temp_alarm_out => open,         --
        vccaux_alarm_out    => vccaux_alarm, -- VCCAUX-sensor alarm output
        vccint_alarm_out    => vccint_alarm  -- VCCINT-sensor alarm output
    );

    END GENERATE xadc_gen_a7;

    --===============================================================================================
    -- (this section is generated by <optohybrid_top>/tools/generate_registers.py -- do not edit)
    --==== Registers begin ==========================================================================

    -- IPbus slave instanciation
    ipbus_slave_inst : entity work.ipbus_slave
        generic map(
           g_NUM_REGS             => REG_ADC_NUM_REGS,
           g_ADDR_HIGH_BIT        => REG_ADC_ADDRESS_MSB,
           g_ADDR_LOW_BIT         => REG_ADC_ADDRESS_LSB,
           g_USE_INDIVIDUAL_ADDRS => true
       )
       port map(
           ipb_reset_i            => ipb_reset_i,
           ipb_clk_i              => ipb_clk_i,
           ipb_mosi_i             => ipb_mosi_i,
           ipb_miso_o             => ipb_miso_o,
           usr_clk_i              => clock_i,
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
    regs_addresses(0)(REG_ADC_ADDRESS_MSB downto REG_ADC_ADDRESS_LSB) <= x"0";
    regs_addresses(1)(REG_ADC_ADDRESS_MSB downto REG_ADC_ADDRESS_LSB) <= x"1";
    regs_addresses(2)(REG_ADC_ADDRESS_MSB downto REG_ADC_ADDRESS_LSB) <= x"2";
    regs_addresses(3)(REG_ADC_ADDRESS_MSB downto REG_ADC_ADDRESS_LSB) <= x"3";

    -- Connect read signals
    regs_read_arr(0)(REG_ADC_CTRL_OVERTEMP_BIT) <= overtemp;
    regs_read_arr(0)(REG_ADC_CTRL_VCCAUX_ALARM_BIT) <= vccaux_alarm;
    regs_read_arr(0)(REG_ADC_CTRL_VCCINT_ALARM_BIT) <= vccint_alarm;
    regs_read_arr(0)(REG_ADC_CTRL_ADR_IN_MSB downto REG_ADC_CTRL_ADR_IN_LSB) <= daddr;
    regs_read_arr(0)(REG_ADC_CTRL_ENABLE_BIT) <= den;
    regs_read_arr(0)(REG_ADC_CTRL_CNT_OVERTEMP_MSB downto REG_ADC_CTRL_CNT_OVERTEMP_LSB) <= cnt_overtemp;
    regs_read_arr(0)(REG_ADC_CTRL_CNT_VCCAUX_ALARM_MSB downto REG_ADC_CTRL_CNT_VCCAUX_ALARM_LSB) <= cnt_vccaux_alarm;
    regs_read_arr(0)(REG_ADC_CTRL_CNT_VCCINT_ALARM_MSB downto REG_ADC_CTRL_CNT_VCCINT_ALARM_LSB) <= cnt_vccint_alarm;
    regs_read_arr(1)(REG_ADC_CTRL_DATA_IN_MSB downto REG_ADC_CTRL_DATA_IN_LSB) <= data_in;
    regs_read_arr(1)(REG_ADC_CTRL_DATA_OUT_MSB downto REG_ADC_CTRL_DATA_OUT_LSB) <= data_out;

    -- Connect write signals
    daddr <= regs_write_arr(0)(REG_ADC_CTRL_ADR_IN_MSB downto REG_ADC_CTRL_ADR_IN_LSB);
    den <= regs_write_arr(0)(REG_ADC_CTRL_ENABLE_BIT);
    data_in <= regs_write_arr(1)(REG_ADC_CTRL_DATA_IN_MSB downto REG_ADC_CTRL_DATA_IN_LSB);

    -- Connect write pulse signals
    reset_local <= regs_write_pulse_arr(2);
    write_en <= regs_write_pulse_arr(3);

    -- Connect write done signals

    -- Connect read pulse signals

    -- Connect counter instances

    COUNTER_ADC_CTRL_CNT_OVERTEMP : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 7
    )
    port map (
        ref_clk_i => clock_i,
        reset_i   => reset,
        en_i      => overtemp,
        snap_i    => cnt_snap,
        count_o   => cnt_overtemp
    );


    COUNTER_ADC_CTRL_CNT_VCCAUX_ALARM : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 7
    )
    port map (
        ref_clk_i => clock_i,
        reset_i   => reset,
        en_i      => vccaux_alarm,
        snap_i    => cnt_snap,
        count_o   => cnt_vccaux_alarm
    );


    COUNTER_ADC_CTRL_CNT_VCCINT_ALARM : entity work.counter_snap
    generic map (
        g_COUNTER_WIDTH  => 7
    )
    port map (
        ref_clk_i => clock_i,
        reset_i   => reset,
        en_i      => vccint_alarm,
        snap_i    => cnt_snap,
        count_o   => cnt_vccint_alarm
    );


    -- Connect rate instances

    -- Connect read ready signals
    regs_read_ready_arr(1) <= data_ready;

    -- Defaults
    regs_defaults(0)(REG_ADC_CTRL_ADR_IN_MSB downto REG_ADC_CTRL_ADR_IN_LSB) <= REG_ADC_CTRL_ADR_IN_DEFAULT;
    regs_defaults(0)(REG_ADC_CTRL_ENABLE_BIT) <= REG_ADC_CTRL_ENABLE_DEFAULT;
    regs_defaults(1)(REG_ADC_CTRL_DATA_IN_MSB downto REG_ADC_CTRL_DATA_IN_LSB) <= REG_ADC_CTRL_DATA_IN_DEFAULT;

    -- Define writable regs
    regs_writable_arr(0) <= '1';
    regs_writable_arr(1) <= '1';

    --==== Registers end ============================================================================

end Behavioral;
