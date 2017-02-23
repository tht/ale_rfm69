defmodule AleRFM69 do
  @moduledoc """
  Documentation for AleRFM69.

  For testing:
  {:ok, pid} = AleRFM69.start_link
  AleRFM69.setup %{group_id: 0x2a, frequency: 8683}

  AleRFM69.switch_opmode :rx

  # Reducte RSSI threshold
  AleRFM69.write_reg 0x29, 0xC4

  """

  use GenServer
  use Bitwise
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
         :ok <- Gpio.set_int(int, :none), # registering on *raising* only does not work
         :ok <- reset(@reset), # do a full reset first
         :ok <- Gpio.set_int(int, :rising)  # registering on *raising* only does not work
      do
        Process.link pid
        Process.link int
        {:ok, %{ pid: pid, int: int }}
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
  
  def get_int_level do
    GenServer.call __MODULE__, {:int_level}
  end

  def get_int_state do
    GenServer.call __MODULE__, {:int_state}
  end

  def switch_opmode(mode) do
    GenServer.call __MODULE__, {:switch_opmode, mode}
  end

  def handle_cast({:write_reg, addr, value}, %{pid: pid} = state) do
    write_register({addr, value}, pid)
    {:noreply, state}
  end
  
  def handle_call({:int_level}, _from, %{int: int} = state) do
    {:reply, Gpio.read(int), state}
  end

  def handle_call({:int_state}, _from, %{pid: pid} = state) do
    << mode_ready :: size(1), rx_ready :: size(1), tx_ready :: size(1), pll_lock :: size(1),
       rssi :: size(1), timeout :: size(1), auto_mode :: size(1), sync_match :: size(1) >>
       = << read_register(0x27, pid) >>
    flags1 = %{
      mode_ready: mode_ready, rx_ready: rx_ready, tx_ready: tx_ready, pll_lock: pll_lock,
      rssi: rssi, timeout: timeout, auto_mode: auto_mode, sync_match: sync_match
    }
    {:reply, flags1, state}
  end

  def handle_call({:setup, %{group_id: group, frequency: freq}}, _from, %{pid: pid} = state) do
    :ok = reset @reset # do a full reset first
    [ {0x01, 0x04}, # opmode: STDBY
      {0x02, 0x00}, # packet mode, fsk
      {0x03, [0x02, 0x8A]}, # bit rate 49,261 hz
      {0x05, [0x05, 0xC3]}, # 90.3kHzFdev -> modulation index = 2
      {0x07, freq_to_register(freq)}, # Frequency
      {0x0B, 0x20}, # low M
      {0x19, [0x42, 0x42]}, # RxBw 125khz, AFCBw 125khz
      {0x1E, 0x0C}, # AFC auto-clear, auto-on
      {0x26, 0x07}, # disable clkout
      # {0x29, 0xC4}, # RSSI thres -98dB
      {0x29, 0xE4}, # RSSI thres 
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

    irq_test = :ok #test_interrupt(pid, int)
    {:reply, irq_test, state}
  end

  def handle_call({:switch_opmode, mode}, _from, %{pid: pid} = state) do
    {:reply, switch_opmode(pid, mode), state}
  end

  def handle_call({:read_reg, addr}, _from, %{pid: pid} = state) do
    {:reply, read_register(addr, pid), state}
  end

  def handle_call({:get_pid}, _from, %{pid: pid} = state) do
    {:reply, pid, state}
  end
  
  def handle_call({:dump_conf}, _from, %{pid: pid} = state) do
    {:reply, output_registers(pid), state}
  end

  def handle_call({:reset_module}, _from, state), do: {:reply,reset(@reset), state}

  defp reset_receiver(pid) do
    switch_opmode(pid, :standby)
    switch_opmode(pid, :rx)
  end

  #def handle_info({:gpio_interrupt, _pin, :falling}, state) do
  #  Logger.info "Interrupt fallen"
  #  {:noreply, state}
  #end

  def handle_info({:gpio_interrupt, pin, :rising = dir}, %{pid: pid, int: int} = state) do
    #<< mode_ready :: size(1), rx_ready :: size(1), tx_ready :: size(1), pll_lock :: size(1),
    #   rssi :: size(1), timeout :: size(1), auto_mode :: size(1), sync_match :: size(1) >>
    #   = << read_register(0x27, pid) >>
    #<< fifo_full :: size(1), fifo_not_empty :: size(1), fifo_level :: size(1), fifo_overrun :: size(1),
    #   packet_sent :: size(1), payload_ready :: size(1), crc_ok :: size(1), low_bat :: size(1) >>
    #   = << read_register(0x28, pid) >>
    #flags = %{
    #  mode_ready: mode_ready, rx_ready: rx_ready, tx_ready: tx_ready, pll_lock: pll_lock,
    #  rssi: rssi, timeout: timeout, auto_mode: auto_mode, sync_match: sync_match,
    #  fifo_full: fifo_full, fifo_not_empty: fifo_not_empty, fifo_level: fifo_level, fifo_overrun: fifo_overrun,
    #  packet_sent: packet_sent, payload_ready: payload_ready, crc_ok: crc_ok, low_bat: low_bat
    #}
    case wait_for( fn() -> 
        case <<read_register(0x28, pid)>> do
          << _::size(5), 1::size(1), _::size(2) >>=reg -> reg
          _ -> false
        end
      end, 10) do
      :timeout -> Logger.error "No complete packet in time received"
                  reset_receiver(pid)
                  :timeout
      res      -> rssi = - read_register(0x24, pid)/2
                  << fei::integer-signed-size(16) >> = read_2register(0x21, pid)
		  Logger.info "RSSI: #{rssi}, FEI: #{fei}"
                  data = Spi.transfer(pid, String.duplicate(<<0>>, 67))
                  case res do
                    << _::size(6), 1::size(1), _::size(1) >> ->
		         << _ :: size(8), len :: size(8),  payload :: binary-size(len), _::binary >> = data
                         res = for << d :: size(8) <- payload >>, do: d |> Integer.to_string( 16) |> String.pad_leading(2, "0")
                         Logger.info "Received (len #{len}): #{res |> Enum.join(" ")}"
		    _ -> Logger.info "Received data but CRC is invalid: #{inspect data}"
		  end
    end
    case Gpio.read(int) do
      1 -> handle_info({:gpio_interrupt, pin, dir}, state)
      _ -> {:noreply, state}
    end
  end

  # Read a single register (except for 0x00) and return content as hex
  defp reg_as_hex(_pid, 0x00), do: "--"
  defp reg_as_hex(pid, addr), do: addr |> read_register(pid) |> Integer.to_string(16) |> String.pad_leading(2, "0")

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
