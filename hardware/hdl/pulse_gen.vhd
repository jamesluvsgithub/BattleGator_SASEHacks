library ieee;
use ieee.std_logic_1164.all;

-- Generates a one-clock active-high pulse.

entity pulse_gen is
    port (
        clk   : in  std_logic;
        rst   : in  std_logic;
        go    : in  std_logic;
        pulse : out std_logic
    );
end entity pulse_gen;


architecture rtl of pulse_gen is

    signal go_prev : std_logic := '0';

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                go_prev <= '0';
                pulse <= '0';

            else
                pulse <= go and not go_prev;
                go_prev <= go;

            end if;
        end if;
    end process;

end architecture rtl;