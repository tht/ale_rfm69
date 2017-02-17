defmodule AleRFM69 do
  @moduledoc """
  Documentation for AleRFM69.
  """

  use GenServer
  require Logger

  @interrupt 193 # AP-EINT1
  @reset 132 # CSID0

  def start_link do
    Logger.info "Starting RFM69 driver process"
    GenServer.start_link(__MODULE__, { }, name: __MODULE__)
  end

  def init(_args) do
    with {:ok, pid} <- Spi.start_link("spidev32766.0", speed_hz: 4000000),
         {:ok, int} <- Gpio.start_link(@interrupt, :input),
         :ok <- Gpio.set_int(int, :both)
      do
        Process.link pid
        Process.link int
        {:ok, %{ pid: pid }}
      else
        _ -> {:error, :init_failed}
    end
  end

  defp freq_to_register(freq) when freq < 100000000 do
    freq_to_register freq * 10
  end
  
  defp freq_to_register(freq) do
    <<f1, f2, f3>> = << round(freq / 61.03515625) :: size(24) >>
    [f1, f2, f3]
  end

  def setup(%{group_id: group, frequency: freq}) do
    [ f1, f2, f3 ] = freq |> freq_to_register
    [ {0x01, 0x04}, # opmode: STDBY
      {0x02, 0x00}, # packet mode, fsk
      {0x03, 0x02}, {0x04, 0x8A}, # bit rate 49,261 hz
      {0x05, 0x05}, {0x06, 0xC3}, # 90.3kHzFdev -> modulation index = 2
      {0x07,   f1}, {0x08,   f2}, {0x09, f3}, # Frequency
      {0x0B, 0x20}, # low M
      {0x19, 0x42}, {0x1A, 0x42}, # RxBw 125khz, AFCBw 125khz
      {0x1E, 0x0C}, # AFC auto-clear, auto-on
      {0x26, 0x07}, # disable clkout
      {0x29, 0xC4}, # RSSI thres -98dB
      {0x2B, 0x40}, # RSSI timeout after 128 bytes
      {0x2D, 0x05}, # Preamble 5 bytes
      {0x2E, 0x88}, # sync size 2 bytes
      {0x2F, 0x2D}, # sync1: 0x2D
      {0x30, group}, # sync2: network group
      {0x37, 0xD0}, # drop pkt if CRC fails
      {0x38, 0x42}, # max 62 byte payload
      {0x3C, 0x8F}, # fifo thres
      {0x3D, 0x12}, # PacketConfig2, interpkt = 1, autorxrestart on
      {0x6F, 0x20}, # Test DAGC
      # {0x71, 0x02}, # RegTestAfc
    ] |> Enum.each( fn({reg, val}) ->
        write_reg(reg, val)
    end )
  end

  def read_reg(addr) do
    GenServer.call __MODULE__, {:read_reg, addr}
  end

  def write_reg(addr, value) do
    GenServer.cast __MODULE__, {:write_reg, addr, value}
  end

  def dump_conf do
    GenServer.call __MODULE__, {:dump_conf}
  end

  def reset_module do
    GenServer.call __MODULE__, {:reset_module}
  end

  def get_pid do
    GenServer.call __MODULE__, {:get_pid}
  end

  # Read a single register and return content as number
  defp read_reg_i(pid, addr) do
    << _ :: size(8), res :: size(8) >> = Spi.transfer(pid, << 0 :: size(1), addr :: size(7), 0x00>>)
    res
  end

  # Writes a single register and return old content as number
  defp write_reg_i(pid, addr, value) do
    << _ :: size(8), res :: size(8) >> = Spi.transfer(pid, << 1 :: size(1), addr :: size(7), value>>)
    res
  end

  def handle_cast({:write_reg, addr, value}, %{pid: pid} = state) do
    write_reg_i(pid, addr, value)
    {:noreply, state}
  end

  def handle_call({:read_reg, addr}, _from, %{pid: pid} = state) do
    {:reply, read_reg_i(pid, addr), state}
  end

  def handle_call({:get_pid}, _from, %{pid: pid} = state) do
    {:reply, pid, state}
  end
  
  def handle_call({:dump_conf}, _from, %{pid: pid} = state) do
    {:reply, output_registers(pid), state}
  end

  def handle_call({:reset_module}, _from, state) do
    with {:ok, rpid} <- Gpio.start_link(@reset, :output),
          :ok        <- Gpio.write(rpid, 1),
          :ok        <- Process.sleep(1),
	  :ok        <- Gpio.write(rpid, 0),
	  :ok        <- Gpio.release(rpid),
          :ok        <- Process.sleep(5)
    do
      {:reply, :ok, state}
    else
      _ -> {:reply, :error, state}
    end
  end

  def handle_info({:gpio_interrupt, _pin, dir}, state) do
    Logger.info "Interrupt received: #{inspect dir}"
    {:noreply, state}
  end

  # Read a single register (except for 0x00) and return content as hex
  defp reg_as_hex(_pid, 0x00), do: "--"
  defp reg_as_hex(pid, addr), do: pid |> read_reg_i(addr) |> Integer.to_string(16) |> String.pad_leading(2, "0")

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
