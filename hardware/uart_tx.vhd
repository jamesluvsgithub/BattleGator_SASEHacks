library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
    generic (
        CLK_FREQ  : positive := 50_000_000;
        BAUD_RATE : positive := 115_200;

        -- NOTE: currently only 8N1
        DATA_BITS : positive := 8
    );
    port (
        clk   : in std_logic;
        rst   : in std_logic;

        uart_tx : out std_logic;

        tx_data  : in  std_logic_vector((DATA_BITS - 1) downto 0);
        tx_start : in  std_logic;
        tx_busy  : out std_logic
    );
end entity uart_tx;



architecture rtl_8N1 of uart_tx is

    constant CLKS_PER_BIT : positive := CLK_FREQ / BAUD_RATE;

    -- TX SIGNALS
    type tx_state_t is (TX_IDLE, TX_START, TX_DATA, TX_STOP);
    signal tx_state : tx_state_t := TX_IDLE;

    signal tx_counter : integer range 0 to CLKS_PER_BIT-1 := 0;
    signal tx_index   : integer range 0 to (DATA_BITS - 1) := 0;
    signal tx_shift   : std_logic_vector((DATA_BITS - 1) downto 0) := (others => '0');

    signal tx_reg : std_logic := '1';

begin

    uart_tx  <= tx_reg;
    tx_busy  <= '0' when tx_state = TX_IDLE else '1';

    -- TX
    process(clk)
    begin
        if rising_edge(clk) then

            if rst = '1' then
                tx_state   <= TX_IDLE;
                tx_counter <= 0;
                tx_index   <= 0;
                tx_shift   <= (others => '0');
                tx_reg     <= '1';

            else
                case tx_state is

                    when TX_IDLE =>
                        -- Hold UART off.
                        tx_reg     <= '1';
                        tx_counter <= 0;

                        if tx_start = '1' then
                            -- Ensure data stays consistent.
                            tx_shift <= tx_data;
                            tx_state <= TX_START;
                        end if;

                    when TX_START =>
                        -- Begin UART frame.
                        tx_reg <= '0';

                        -- Use counter to adhere to baud rate.
                        if tx_counter = CLKS_PER_BIT-1 then
                            -- Initialize data transmit.
                            tx_counter <= 0;
                            tx_index   <= 0;
                            tx_state   <= TX_DATA;
                        else
                            tx_counter <= tx_counter + 1;
                        end if;

                    when TX_DATA =>
                        -- Load pin with current data bit.
                        tx_reg <= tx_shift(tx_index);

                        -- Use counter to adhere to baud rate.
                        if tx_counter = CLKS_PER_BIT-1 then
                            tx_counter <= 0;

                            -- Reached end of data transmit.
                            if tx_index = (DATA_BITS - 1) then
                                tx_state <= TX_STOP;
                            else
                                tx_index <= tx_index + 1;
                            end if;
                        else
                            tx_counter <= tx_counter + 1;
                        end if;

                    when TX_STOP =>
                        -- End UART frame.
                        tx_reg <= '1';

                        if tx_counter = CLKS_PER_BIT-1 then
                            tx_counter <= 0;
                            tx_state   <= TX_IDLE;
                        else
                            tx_counter <= tx_counter + 1;
                        end if;

                end case;
            end if;
        end if;
    end process;

