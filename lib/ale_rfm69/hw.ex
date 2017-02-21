defmodule AleRFM69.HW do
  @moduledoc false
  use Bitwise

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
  def read_register(addr, pid) do
    << _ :: size(8), res :: size(8) >> = Spi.transfer(pid, << 0 :: size(1), addr :: size(7), 0x00>>)
    res
  end

  # Read two registers and return content as number
  def read_2register(addr, pid) do
    << _ :: size(8), rest :: binary-size(2) >> = Spi.transfer(pid, << 0 :: size(1), addr :: size(7), 0x00, 0x00>>)
    rest
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

  # Test interrupts - switch into FS mode and configure DIO0 to get an interrupt
  def test_interrupt(pid, _int_pid) do
    old_dio  = write_register({0x25, 0x00}, pid) # no interrupts
    old_mode = write_register({0x01, 0x08}, pid) # change mode (add busywaiting here until modeready == 1
    write_register({0x25, 0xC0}, pid)
    receive do
      {:gpio_interrupt, _, :rising} -> write_register({0x01, old_mode}, pid)
                                       write_register({0x25, old_dio}, pid)
                                       :ok
    after
      1000 -> :error
    end
  end

  # wait a maximum of *timeout* ms (default 10ms) until a function returns *not* nil
  # timeout (in ms) is always positive, negative numbers are used internally
  def wait_for(fun, timeout \\ 10)
  def wait_for(fun, timeout) when timeout > 0, do: wait_for(fun, 0 - :os.system_time(:milli_seconds) - timeout)
  def wait_for(fun, timeout) do
    cond do
      :os.system_time(:milli_seconds) + timeout >= 0 -> :timeout
      res = fun.() -> res
      true -> wait_for(fun, timeout)
    end
  end

  defp wait_for_modeready(pid) do
    case wait_for( fn() -> 0x80 &&& read_register(0x27, pid) end, 10) do
      :timeout -> :timeout
      _        -> :ok
    end
  end

  def switch_opmode(pid, mode, _diomapping \\ -1)
  def switch_opmode(pid, :sleep, _diomapping) do
    # Disable all interrupt sources and switch mode
    write_register {0x25, 0x00}, pid
    write_register {0x01, 0x00}, pid
    wait_for_modeready pid
  end

  def switch_opmode(pid, :standby, _diomapping) do
    # Disable all interrupt sources and switch mode
    write_register {0x25, 0x00}, pid
    write_register {0x01, 0x04}, pid
    wait_for_modeready pid
  end

  def switch_opmode(pid, :rx, _diomapping) do
    # Interrupt on rssi and switch mode
    write_register {0x25, 0x80}, pid
    write_register {0x01, 0x10}, pid
    wait_for_modeready pid
  end

end
