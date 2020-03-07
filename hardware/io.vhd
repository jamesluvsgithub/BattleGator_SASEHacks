
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity io is
    port (
        clk : in std_logic;
        rst : in std_logic;

        p1_row : in std_logic_vector(6 downto 0);
        p1_col : in std_logic_vector(6 downto 0);
        p1_special : in std_logic;

        p2_row : in std_logic_vector(6 downto 0);
        p2_col : in std_logic_vector(6 downto 0);
        p2_special : in std_logic;

        uart_tx_out : out std_logic
    );
end entity io;


architecture rtl of io is

    constant CLK_FREQ  : integer := 50_000_000;
    constant BAUD_RATE : integer := 115_200;
    constant DATA_BITS : integer := 8;

    constant SOF : std_logic_vector(7 downto 0) := x"FA";

    -- Checks whether a vector contains exactly one asserted bit.
    --  Useful because you can't choose more than one row/col at the same time
    function is_one_hot(data : std_logic_vector) return boolean is
        variable value : unsigned(data'range);
    begin
        value := unsigned(data);
        return (value /= 0) and ((value and (value - 1)) = 0);
    end function;


    type state_t is (
        IDLE,
        START_BYTE,
        WAIT_BUSY,
        WAIT_DONE
    );

    signal state : state_t := IDLE;

    -- for change / rising-edge detection.
    signal p1_row_prev : std_logic_vector(6 downto 0);
    signal p1_col_prev : std_logic_vector(6 downto 0);
    signal p2_row_prev : std_logic_vector(6 downto 0);
    signal p2_col_prev : std_logic_vector(6 downto 0);
    signal p1_special_prev : std_logic;
    signal p2_special_prev : std_logic;

    type packet_t is array (0 to 4) of std_logic_vector(7 downto 0);
    signal packet : packet_t;
    signal packet_pending : std_logic := '0';
    signal byte_index     : integer range 0 to 4 := 0;

    signal tx_data  : std_logic_vector(7 downto 0);
    signal tx_start : std_logic;
    signal tx_busy  : std_logic;

begin

    uart_inst : entity work.uart_tx
        generic map (
            CLK_FREQ  => CLK_FREQ,
            BAUD      => BAUD_RATE,
            DATA_BITS => DATA_BITS
        )
        port map (
            clk      => clk,
            rst      => rst,
            tx_data  => tx_data,
            tx_start => tx_start,
            tx_busy  => tx_busy,
            uart_tx  => uart_tx_out
        );


    tx_data <= packet(byte_index);

    -- Pulse tx_start for one clock cycle when starting a byte.
    tx_start <= '1' when state = START_BYTE else '0';


    process(clk)

        variable input_changed : boolean;
        variable pending_next  : std_logic;

    begin

        if rising_edge(clk) then

            -- Synchronous reset
            if rst = '1' then
                state <= IDLE;

                p1_row_prev <= (others => '0');
                p1_col_prev <= (others => '0');
                p2_row_prev <= (others => '0');
                p2_col_prev <= (others => '0');

                p1_special_prev <= '0';
                p2_special_prev <= '0';

                packet_pending <= '0';
                byte_index <= 0;

                packet <= (others => (others => '0'));

            else

                -- Detect valid selection changes and attack presses.
                input_changed :=
                    (is_one_hot(p1_row) and p1_row /= p1_row_prev) or
                    (is_one_hot(p1_col) and p1_col /= p1_col_prev) or
                    (is_one_hot(p2_row) and p2_row /= p2_row_prev) or
                    (is_one_hot(p2_col) and p2_col /= p2_col_prev) or
                    (p1_special = '1' and p1_special_prev = '0') or
                    (p2_special = '1' and p2_special_prev = '0');

                p1_row_prev <= p1_row;
                p1_col_prev <= p1_col;
                p2_row_prev <= p2_row;
                p2_col_prev <= p2_col;

                p1_special_prev <= p1_special;
                p2_special_prev <= p2_special;

                -- Preserve a pending update while the UART is busy.
                pending_next := packet_pending;

                if input_changed then
                    pending_next := '1';
                end if;


                case state is

                    when IDLE =>

                        if pending_next = '1' then

                            -- Capture a consistent input snapshot.
                            packet(0) <= SOF;
                            packet(1) <= p1_special & p1_row;
                            packet(2) <= '0' & p1_col;
                            packet(3) <= p2_special & p2_row;
                            packet(4) <= '0' & p2_col;

                            byte_index <= 0;
                            pending_next := '0';

                            state <= START_BYTE;
                        end if;


                    when START_BYTE =>

                        -- tx_start is asserted during this state. UART should begin transmitting.
                        state <= WAIT_BUSY;


                    when WAIT_BUSY =>

                        -- Wait until the UART acknowledges the start.
                        if tx_busy = '1' then
                            state <= WAIT_DONE;
                        end if;


                    when WAIT_DONE =>

                        -- Wait until the current UART byte finishes.
                        if tx_busy = '0' then

                            if byte_index = 4 then
                                state <= IDLE;
                            else
                                byte_index <= byte_index + 1;
                                state <= START_BYTE;
                            end if;

                        end if;

                end case;

                packet_pending <= pending_next;

            end if;
        end if;
    end process;

end architecture rtl;
