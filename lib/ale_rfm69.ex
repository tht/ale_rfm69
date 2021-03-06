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
  use Bitwise, only_operators: true
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
Process.send_after(self(), {:"$gen_cast", {:dump_int} }, 1000)
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
  
  def handle_cast({:dump_int}, state) do
    {:reply, res, state} = handle_call({:int_state}, nil, state)
    #Process.send_after(self(), {:"$gen_cast", {:dump_int} }, 1000)
    IO.puts inspect res
    {:noreply, state}
  end

  def handle_cast({:rssi, val}, %{pid: pid}=state) do
    << rssi :: size(8) >> = read_register(0x29, pid)
    new_rssi = rssi + val
    Logger.warn "RSSI threshold changed to: -#{new_rssi/2}"
    write_register {0x29, new_rssi}, pid
    {:noreply, state}
  end

  def handle_call({:int_level}, _from, %{int: int} = state) do
    {:reply, Gpio.read(int), state}
  end

  def handle_call({:int_state}, _from, %{pid: pid} = state) do
    << mode_ready :: size(1), rx_ready :: size(1), tx_ready :: size(1), pll_lock :: size(1),
       rssi :: size(1), timeout :: size(1), auto_mode :: size(1), sync_match :: size(1) >>
       = read_register(0x27, pid)
    flags1 = %{
      mode_ready: mode_ready, rx_ready: rx_ready, tx_ready: tx_ready, pll_lock: pll_lock,
      rssi: rssi, timeout: timeout, auto_mode: auto_mode, sync_match: sync_match
    }
    {:reply, flags1, state}
  end

  def handle_call({:setup, %{group_id: group, frequency: freq}}, _from, %{pid: pid, int: int} = state) do
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
      #{0x29, 0xE4}, # RSSI thres 
      {0x2B, 0x40}, # RSSI timeout after 128 bytes
      {0x2D, 0x05}, # Preamble 5 bytes
      {0x2E, 0x88}, # sync size 2 bytes
      {0x2F, 0x2D}, # sync1: 0x2D
      {0x30, group}, # sync2: network group
      {0x37, 0xD8}, # report packets when CRC fails
      #{0x37, 0xD0}, # drop pkt if CRC fails
      {0x38, 0x42}, # max 62 byte payload
      {0x3C, 0x8F}, # fifo thres
      {0x3D, 0x12}, # PacketConfig2, interpkt = 1, autorxrestart on
      {0x6F, 0x20}, # Test DAGC
      # {0x71, 0x02}, #     ] |> write_registers(pid)
    ] |> write_registers(pid)

    irq_test = test_interrupt(pid, int)
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

  # do a restart on the receiver
  defp reset_receiver(pid) do
    #switch_opmode(pid, :standby)
    #switch_opmode(pid, :rx)
    write_register {0x3d, 0x16}, pid
  end

  def handle_info({:gpio_interrupt, _pin, :falling}, state) do
    Logger.warn "Interrupt falling received - but it is disabled..."
    {:noreply, state}
  end

  def handle_info({:gpio_interrupt, pin, :rising = dir}, %{pid: pid, int: int} = state) do
    RSSIFinder.irq_thrown
    reset_receiver(pid)
    {:noreply, state}
  end

#    :interrupts |> Stats.add_type
#    case wait_for( fn() -> 
#        case read_2register(0x27, pid) do
#          << _::size(13), 1::size(1), _::size(2)  >>=reg -> reg
#          << _::size(4),  0::size(1), _::size(11) >> -> :carrier_lost
#          _ -> false
#        end
#      end, 12) do
#      :timeout -> Logger.info "Receiving aborted: timeout"
#                  reset_receiver(pid)
#                  :timeout |> Stats.add_type
#                  :timeout
#      :carrier_lost -> Logger.warn "Receiving aborted: carrier lost"
#                  :timeout |> Stats.add_type
#                  :carrier_lost
#      res      -> rssi = read_register(0x24, pid) |> reg_to_uint |> Kernel.*(-0.5)
#                  << fei::integer-signed-size(16) >> = read_2register(0x21, pid)
#		  stats = "RSSI: #{rssi}, FEI: #{fei}"
#                  data = Spi.transfer(pid, String.duplicate(<<0>>, 67))
#                  case res do
#                    << _::size(14), 1::size(1), _::size(1) >> ->
#		         << _ :: size(8), len :: size(8),  payload :: binary-size(len), _::binary >> = data
#                         res = for << d :: size(8) <- payload >>, do: d |> Integer.to_string( 16) |> String.pad_leading(2, "0")
#                         :crc_ok |> Stats.add_type
#                         Logger.info "#{stats}: (len #{len}) #{res |> Enum.join(" ")}"
#		    _ -> Logger.info "#{stats}: CRC invalid on: #{inspect data}"
#                         :crc_failed |> Stats.add_type
#		  end
#    end
#    case Gpio.read(int) do
#      1 -> Logger.warn "Still an interrupt pending, checking again"
#           handle_info({:gpio_interrupt, pin, dir}, state)
#      _ -> {:noreply, state}
#    end
#  end

  # Read a single register (except for 0x00) and return content as hex
  defp reg_as_hex(_pid, 0x00), do: "--"
  defp reg_as_hex(pid, addr), do: addr |> read_register(pid) |> reg_to_uint |> Integer.to_string(16) |> String.pad_leading(2, "0")

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
