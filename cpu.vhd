-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2023 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Mykola Vorontsov <login AT stud.fit.vutbr.cz>
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.all;
use IEEE.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic;                      -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'

   -- stavove signaly
   READY    : out std_logic;                      -- hodnota 1 znamena, ze byl procesor inicializovan a zacina vykonavat program
   DONE     : out std_logic                       -- hodnota 1 znamena, ze procesor ukoncil vykonavani programu (narazil na instrukci halt)
 );
end cpu;

-- -- mux2: 2-to-1 multiplexer with 12-bit data input and output
-- entity mux2 is
--  port (
--   SEL : in std_logic;
--   IN0 : in std_logic_vector(11 downto 0);
--   IN1 : in std_logic_vector(11 downto 0);
--   OUTP : out std_logic_vector(11 downto 0)
--  );
-- end mux2;

-- -- mux4: 4-to-1 multiplexer with 8-bit data input and output
-- entity mux4 is
--  port (
--   SEL : in std_logic_vector(1 downto 0);
--   IN0 : in std_logic_vector(7 downto 0);
--   IN1 : in std_logic_vector(7 downto 0);
--   IN2 : in std_logic_vector(7 downto 0);
--   IN3 : in std_logic_vector(7 downto 0);
--   OUTP : out std_logic_vector(7 downto 0)
--  );
-- end mux4;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
-- architecture dataflow of mux2 is
-- begin
--   OUTP <= IN0 when SEL = '0' else IN1;
-- end dataflow;

-- architecture dataflow of mux4 is
-- begin
--   OUTP <= IN0 when SEL = "00" else
--           IN1 when SEL = "01" else
--           IN2 when SEL = "10" else
--           IN3;
-- end dataflow;



architecture behavioral of cpu is

 -- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze 
 --   - nelze z vice procesu ovladat stejny signal,
 --   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
 --      - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a 
 --      - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly. 

  signal pc_out : std_logic_vector(12 downto 0);
  signal pc_inc : std_logic;
  signal pc_dec : std_logic;

  signal ptr_out : std_logic_vector(12 downto 0);
  signal ptr_inc : std_logic;
  signal ptr_dec : std_logic;
  signal ptr_rst : std_logic;

  signal cnt_out : std_logic_vector(7 downto 0);
  signal cnt_inc : std_logic;
  signal cnt_dec : std_logic;

  signal mx1_sel : std_logic;
  signal mx2_sel : std_logic_vector(1 downto 0);

  signal old_data : std_logic_vector(7 downto 0);

  -- component mux2
  --   port (
  --     SEL : in std_logic;
  --     IN0 : in std_logic_vector(11 downto 0);
  --     IN1 : in std_logic_vector(11 downto 0);
  --     OUTP : out std_logic_vector(11 downto 0)
  --   );
  -- end component;

  -- component mux4
  --   port (
  --     SEL : in std_logic_vector(1 downto 0);
  --     IN0 : in std_logic_vector(7 downto 0);
  --     IN1 : in std_logic_vector(7 downto 0);
  --     IN2 : in std_logic_vector(7 downto 0);
  --     IN3 : in std_logic_vector(7 downto 0);
  --     OUTP : out std_logic_vector(7 downto 0)
  --   );
  -- end component;

  type t_state is (
    state_startup,
    state_init,
    state_next_symbol,
    state_decode,
    state_end,
    state_inc_ptr,
    state_dec_ptr,
    state_inc_value_1,
    state_inc_value_2,
    state_dec_value
  );

  signal state : t_state;
  signal next_state : t_state;

begin

  -- mx1: mux2 port map (
  --   SEL => mx1_sel,
  --   IN0 => ptr_out,
  --   IN1 => pc_out,
  --   OUTP => mx1_out
  -- );

  -- mx2: mux4 port map (
  --   SEL => mx2_sel,
  --   IN0 => IN_DATA,
  --   IN1 => DATA_RDATA,
  --   IN2 => DATA_RDATA,
  --   IN3 => "00000000",
  --   OUTP => mx2_out
  -- );

  mx1: process (mx1_sel, ptr_out, pc_out)
  begin
    case mx1_sel is
      when '0' =>
        DATA_ADDR <= ptr_out;
      when '1' =>
        DATA_ADDR <= pc_out;
      when others =>
        DATA_ADDR <= (others => '0');
    end case;
  end process;

  mx2: process (mx2_sel, IN_DATA, DATA_RDATA)
  begin
    if (mx2_sel = "00") then
      DATA_WDATA <= IN_DATA;
    elsif (mx2_sel = "01") then
      DATA_WDATA <= DATA_RDATA + 1;
    elsif (mx2_sel = "10") then
      DATA_WDATA <= DATA_RDATA - 1;
    else
      DATA_WDATA <= "00000000";
    end if;
  end process;

  pc_cntr: process (CLK, RESET) 
  begin
    if (RESET = '1') then
      pc_out <= (others => '0');
    elsif (CLK'event) and (CLK='1') then
      if (pc_inc = '1') then 
        pc_out <= pc_out + 1;
      elsif (pc_dec = '1') then
        pc_out <= pc_out - 1;
      end if;
    end if;
  end process;

  ptr_cntr: process (CLK, RESET)
  begin
    if (RESET = '1') then
      ptr_out <= (others => '0');
    elsif (CLK'event) and (CLK='1') then
      if (ptr_inc = '1') then 
        ptr_out <= ptr_out + 1;
      elsif (ptr_dec = '1') then
        ptr_out <= ptr_out - 1;
      elsif (ptr_rst = '1') then
        ptr_out <= (others => '0');
      end if;
    end if;
  end process;

  cnt_cntr: process (CLK, RESET)
  begin
    if (RESET = '1') then
      cnt_out <= (others => '0');
    elsif (CLK'event) and (CLK='1') then
      if (cnt_inc = '1') then 
        cnt_out <= cnt_out + 1;
      elsif (cnt_dec = '1') then
        cnt_out <= cnt_out - 1;
      end if;
    end if;
  end process;

  state_register: process (CLK, RESET)
  begin
    if RESET = '1' then
      state <= state_startup;
    elsif (CLK'event) and (CLK='1') and (EN='1') then
      state <= next_state;
    end if;
  end process;

  state_logic: process (state, IN_VLD, DATA_RDATA)
  begin
    next_state <= state_startup;
    
    cnt_inc <= '0';
    cnt_dec <= '0';
    ptr_inc <= '0';
    ptr_dec <= '0';
    ptr_rst <= '0';
    pc_inc <= '0';
    pc_dec <= '0';

    mx1_sel <= '1';
    mx2_sel <= "00";

    IN_REQ <= '0';
    OUT_WE <= '0';
    DATA_RDWR <= '0';
    DATA_EN <= '1';

    DONE <= '0';
    READY <= '1';


    case state is
      when state_startup =>
        READY <= '0';
        next_state <= state_init;

      when state_init =>
        next_state <= state_decode;
        if (DATA_RDATA = "01000000") then
          READY <= '0';
          next_state <= state_decode;
        end if;
        pc_inc <= '1';

      when state_next_symbol =>
        pc_inc <= '1';
        next_state <= state_decode;

      when state_decode =>
        case DATA_RDATA is
          when "00000000" =>
            next_state <= state_end;
            
          when "00111110" =>
            next_state <= state_inc_ptr;

          when "00111100" =>
            next_state <= state_dec_ptr;

          when "00101011" =>
            next_state <= state_inc_value_1;

          when "00101101" =>
            next_state <= state_dec_value;

          -- when "00101000" =>
          --   next_state <= state_loop_start;

          -- when "00101100" =>
          --   next_state <= state_loop_end;

          -- when "00111001" =>
          --   next_state <= state_read;

          -- when "00110001" =>
          --   next_state <= state_write;
          

          when others =>
            next_state <= state_next_symbol;
        end case;

      when state_inc_ptr =>
        ptr_inc <= '1';
        next_state <= state_next_symbol;

      when state_dec_ptr =>
        ptr_dec <= '1';
        next_state <= state_next_symbol;

      when state_inc_value_1 =>
        mx1_sel <= '0';
        old_data <= DATA_RDATA;
        next_state <= state_inc_value_2;

      when state_inc_value_2 =>
        mx2_sel <= "01";
        DATA_RDWR <= '1';
        next_state <= state_next_symbol;

      when state_dec_value =>
        cnt_dec <= '1';
        next_state <= state_next_symbol;

      when state_end =>
        DONE <= '1';
        next_state <= state_end;

      when others =>
        next_state <= state_startup;
    end case;
  end process;

end behavioral;

