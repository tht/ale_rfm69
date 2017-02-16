defmodule AleRFM69 do
  @moduledoc """
  Documentation for AleRFM69.
  """

  use GenServer
  require Logger

  @interrupt 1013

  def start_link do
    Logger.info "Starting RFM69 driver process"
    GenServer.start_link(__MODULE__, { }, name: __MODULE__)
  end

  def init(_args) do
    with {:ok, pid} <- Spi.start_link("spidev32766.0"),
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

  def read_reg(addr) do
    GenServer.call __MODULE__, {:read_reg, addr}
  end

  def dump_conf do
    GenServer.call __MODULE__, {:dump_conf}
  end

  def get_pid do
    GenServer.call __MODULE__, {:get_pid}
  end

  # Read a single register and return content as number
  defp read_reg_i(pid, addr) do
    << _ :: size(8), res :: size(8) >> = Spi.transfer(pid, << 0 :: size(1), addr :: size(7), 0x00>>)
    res
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
