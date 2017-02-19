defmodule AleRFM69 do
  @moduledoc """
  Documentation for AleRFM69.
  """

  use GenServer
  require Logger
  import AleRFM69.HW

  @interrupt 193 # AP-EINT1
  @reset 132 # CSID0

  def start_link do
    Logger.info "Starting RFM69 driver process"
    GenServer.start_link(__MODULE__, { }, name: __MODULE__)
  end

  def init(_args) do
    with {:ok, pid} <- Spi.start_link("spidev32766.0", speed_hz: 4000000),
         {:ok, int} <- Gpio.start_link(@interrupt, :input),
         :ok <- Gpio.set_int(int, :both) # registering on *raising* only does not work
      do
        Process.link pid
        Process.link int
        {:ok, %{ pid: pid }}
      else
        _ -> {:error, :init_failed}
    end
  end


  def setup(data) do
    GenServer.call __MODULE__, {:setup, data}
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

  def handle_cast({:write_reg, addr, value}, %{pid: pid} = state) do
    write_register({addr, value}, pid)
    {:noreply, state}
  end

  def handle_call({:setup, %{group_id: group, frequency: freq}}, _from, %{pid: pid} = state) do
    :ok = reset @reset
    [ {0x01, 0x04}, # opmode: STDBY
      {0x02, 0x00}, # packet mode, fsk
      {0x03, [0x02, 0x8A]}, # bit rate 49,261 hz
      {0x05, [0x05, 0xC3]}, # 90.3kHzFdev -> modulation index = 2
      {0x07, freq_to_register(freq)}, # Frequency
      {0x0B, 0x20}, # low M
      {0x19, [0x42, 0x42]}, # RxBw 125khz, AFCBw 125khz
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
      # {0x71, 0x02}, #     ] |> write_registers(pid)
    ] |> write_registers(pid)

    :ok = test_interrupt(pid)
    {:reply, :ok, state}
  end

  def handle_call({:read_reg, addr}, _from, %{pid: pid} = state) do
    {:reply, read_register(pid, addr), state}
  end

  def handle_call({:get_pid}, _from, %{pid: pid} = state) do
    {:reply, pid, state}
  end
  
  def handle_call({:dump_conf}, _from, %{pid: pid} = state) do
    {:reply, output_registers(pid), state}
  end

  def handle_call({:reset_module}, _from, state), do: {:reply,reset(@reset), state}

  def handle_info({:gpio_interrupt, _pin, :falling}, state), do: {:noreply, state}

  def handle_info({:gpio_interrupt, _pin, :rising}, state) do
    Logger.info "Interrupt received!"
    {:noreply, state}
  end

  # Read a single register (except for 0x00) and return content as hex
  defp reg_as_hex(_pid, 0x00), do: "--"
  defp reg_as_hex(pid, addr), do: pid |> read_register(addr) |> Integer.to_string(16) |> String.pad_leading(2, "0")

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
