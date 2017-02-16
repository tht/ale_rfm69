defmodule AleRFM69 do
  @moduledoc """
  Documentation for AleRFM69.
  """

  # @interrupt 1013

  # Sets up SPI process
  def setup do
    Spi.start_link("spidev32766.0")
  end

  # Read a single register and return content as number
  def read_reg(pid, addr) do
    << _ :: size(8), res :: size(8) >> = Spi.transfer(pid, << 0 :: size(1), addr :: size(7), 0x00>>)
    res
  end

  # Read a single register (except for 0x00) and return content as hex
  defp reg_as_hex(_pid, 0x00), do: "--"
  defp reg_as_hex(pid, addr), do: pid |> read_reg(addr) |> Integer.to_string(16) |> String.pad_leading(2, "0")

  # Dump all registers to stdout
  def output_registers(pid, base \\ -1)
  def output_registers(pid, -1) do
    IO.puts "    " <> (0..15 |> Enum.map( &("_" <> Integer.to_string(&1, 16)) ) |> Enum.join(" "))
    output_registers pid, 0
  end

  def output_registers(_pid, 0x60), do: :ok

  def output_registers(pid, base) when base <= 0x50 do
    col  = base |> Integer.to_string(16) |> String.pad_leading(2, "0")
    data = 0..15 |> Enum.map( &(reg_as_hex pid, base + &1) ) |> Enum.join(" ")
    IO.puts "#{col}: #{data}"
    output_registers pid, base + 0x10
  end
    
end
