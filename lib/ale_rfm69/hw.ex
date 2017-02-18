defmodule AleRFM69.HW do
  @moduledoc false

  def freq_to_register(freq) when freq < 100000000, do: freq_to_register freq * 10
  
  def freq_to_register(freq) do
    <<f1, f2, f3>> = << round(freq / 61.03515625) :: size(24) >>
    [f1, f2, f3]
  end

  def write_registers({_addr, _val}=data, pid), do: write_register data, pid
  def write_registers([head | []], pid), do: write_register head, pid
  def write_registers([head | rest], pid) do
    write_register head, pid
    write_registers rest, pid
  end

  # @compile {:inline, write_register: 2}
  def write_register({addr, val}, pid) when is_list(val) do
    data = [<< 1 :: size(1), addr :: size(7)>> | Enum.map(val, &(<<&1>>)) ] |> Enum.join
    Spi.transfer(pid, data)
  end

  def write_register({addr, val}, pid) do
    << _ :: size(8), res :: size(8) >> = Spi.transfer(pid, << 1 :: size(1), addr :: size(7), val>>)
    res
  end

  # Read a single register and return content as number
  def read_register(pid, addr) do
    << _ :: size(8), res :: size(8) >> = Spi.transfer(pid, << 0 :: size(1), addr :: size(7), 0x00>>)
    res
  end

  
  def reset(reset_pin) do
    with {:ok, rpid} <- Gpio.start_link(reset_pin, :output),
          :ok        <- Gpio.write(rpid, 1),
          :ok        <- Process.sleep(1),
	  :ok        <- Gpio.write(rpid, 0),
	  :ok        <- Gpio.release(rpid),
          :ok        <- Process.sleep(5)
    do
      :ok
    else
      _ -> :error
    end
  end

end
