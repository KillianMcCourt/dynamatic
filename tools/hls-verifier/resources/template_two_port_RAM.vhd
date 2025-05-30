library ieee;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
-- Import template simulation package
use work.sim_package.all;

---------------------------------------------------------------------------
entity two_port_RAM is
  generic (
    -- File paths for read and write
    TV_IN  : string := "";
    TV_OUT : string := "";
    -- Memory depth for data
    DEPTH : integer;
    -- Bus widths for data and address
    DATA_WIDTH : integer := 32;
    ADDR_WIDTH : integer
  );
  port (
    clk  : in std_logic;
    rst  : in std_logic;
    done : in std_logic;
    -- RAM port-0
    ce0       : in  std_logic;
    we0       : in  std_logic;
    address0  : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    dout0 : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    din0  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- RAM port-1
    ce1       : in  std_logic;
    we1       : in  std_logic;
    address1  : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    dout1 : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    din1  : in  std_logic_vector(DATA_WIDTH - 1 downto 0)
  );
end two_port_RAM;

---------------------------------------------------------------------------
-- Main body of the entity: Two-Port RAM
architecture behav of two_port_RAM is
  -- Internal signals
  type array2D is
  array (0 to DEPTH - 1) of std_logic_vector(DATA_WIDTH - 1 downto 0);
  shared variable mem : array2D := (others => (others => '0'));
begin

  ---------------------------------------------------------------------------
  -- DATA READ --------------------------------------------------------------

  -- Transfer: text-file -> mem-array ---------------------------------------
  file_to_mem : process
    -- Internal signals
    file file_ptr        : text;
    variable file_status : file_open_status;
    variable line_num    : line;
    variable token       : string(1 to 128);
    variable index       : integer;
  begin

    -- Check if file path is defined
    if (TV_IN /= "") then
      -- Initialization
      index := 0;
      file_open(file_status, file_ptr, TV_IN, READ_MODE);

      if (file_status /= OPEN_OK) then
        assert false report "ERROR: Could not open file: " & TV_IN severity failure;
      end if;

      -- Use read_token procedure to read tokens from the file
      read_token(file_ptr, line_num, token);

      -- Read tokens with the HLS TB format
      if (token(1 to 13) /= "[[[runtime]]]") then
        assert false report "ERROR: Simulation failed." severity failure;
      end if;

      -- Parse through [[[runtime]]] scope
      read_token(file_ptr, line_num, token);
      while (token(1 to 14) /= "[[[/runtime]]]") loop
        if (token(1 to 15) /= "[[transaction]]") then
          assert false report "ERROR: Simulation failed." severity failure;
        end if;
        -- Discard [[transaction]] number
        read_token(file_ptr, line_num, token);

        -- Read data from file into mem-array (for every transaction)
        for i in 0 to DEPTH - 1 loop
          read_token(file_ptr, line_num, token);
          mem(i) := hex_str_to_logicVec(token, DATA_WIDTH);
        end loop;
        read_token(file_ptr, line_num, token);

        -- Check for end of [[transaction]]
        if (token(1 to 16) /= "[[/transaction]]") then
          assert false report "ERROR: Simulation failed." severity failure;
        end if;
        read_token(file_ptr, line_num, token);

        -- Increment index for next [[transaction]]
        index := index + 1;
      end loop;

      file_close(file_ptr);
    end if;
    wait;

  end process file_to_mem;

  -- Transfer: mem-array -> RTL ports ---------------------------------------
  mem_to_port0 : process (clk, rst)
  begin
    -- Simple memory read
    if (rst = '1') then
      dout0 <= (others => '0');
    elsif rising_edge(clk) then
      if (ce0 = '1' and ce1 = '1' and we1 = '1' and address0 = address1) then
        dout0 <= din1 after 0.1 ns;
      elsif (ce0 = '1' and (CONV_INTEGER(address0) < DEPTH)) then
        dout0 <= mem(CONV_INTEGER(address0)) after 0.1 ns;
      end if;
    end if;
  end process mem_to_port0;

  mem_to_port1 : process (clk, rst)
  begin
    -- Simple memory read
    if (rst = '1') then
      dout1 <= (others => '0');
    elsif rising_edge(clk) then
      if (ce0 = '1' and we0 = '1' and ce1 = '1' and address0 = address1) then
        dout1 <= din0 after 0.1 ns;
      elsif (ce1 = '1' and (CONV_INTEGER(address1) < DEPTH)) then
        dout1 <= mem(CONV_INTEGER(address1)) after 0.1 ns;
      end if;
    end if;
  end process mem_to_port1;

  ---------------------------------------------------------------------------
  -- DATA WRITE -------------------------------------------------------------

  -- Transfer: RTL ports -> mem-array ---------------------------------------
  port0_to_mem : process (clk)
  begin
    -- Simple memory write
    if rising_edge(clk) then
      if (ce0 = '1' and we0 = '1' and ce1 = '1' and we1 = '1' and address0 = address1) then
        mem(CONV_INTEGER(address0)) := din1;
      elsif (ce0 = '1' and we0 = '1') then
        mem(CONV_INTEGER(address0)) := din0;
      end if;
    end if;
  end process port0_to_mem;

  port1_to_mem : process (clk)
  begin
    -- Simple memory write
    if rising_edge(clk) then
      if (ce1 = '1' and we1 = '1') then
        mem(CONV_INTEGER(address1)) := din1;
      end if;
    end if;
  end process port1_to_mem;

  -- Transfer: mem-array -> text-file ---------------------------------------
  mem_to_file : process
    -- Internal signals
    file file_ptr        : text;
    variable file_status : file_open_status;
    variable line_num    : line;
    variable token       : string(1 to 128);
    variable index       : integer;
  begin

    -- Check if file path is defined
    if (TV_OUT /= "") then
      wait until done = '1';
      index := 0;

      -- Open file
      file_open(file_status, file_ptr, TV_OUT, APPEND_MODE);
      if (file_status /= OPEN_OK) then
        assert false report "ERROR: Could not open file " & TV_OUT severity failure;
      end if;

      -- Write [[transaction]] entries in HLS TB format
      write(line_num, "[[transaction]]    " & integer'image(index));
      writeline(file_ptr, line_num);
      --
      for i in 0 to DEPTH - 1 loop
        write(line_num, "0x" & hex_logicVec_to_str(mem(i)));
        writeline(file_ptr, line_num);
      end loop;
      --
      write(line_num, string'("[[/transaction]]"));
      writeline(file_ptr, line_num);

      -- Close file
      file_close(file_ptr);
    end if;
    wait;

  end process mem_to_file;

  ----------------------------------------------------------------------------
end behav;
-- End of code
