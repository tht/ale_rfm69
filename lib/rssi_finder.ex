defmodule RSSIFinder do
  use GenServer
  require Logger

  @interval 10

  def start_link do
    Logger.info "Starting rssi finder process..."
    GenServer.start_link(__MODULE__, {}, name: __MODULE__)
  end

  def init(_) do
    state = %{
      mode: :sleep,
      irqs: 0
    }
    Process.send_after(self(), :calc, @interval * 1000)
    {:ok, state}
  end

  def irq_thrown do
    GenServer.cast __MODULE__, {:irq}
  end

  def handle_cast({:irq}, %{irqs: irqs} = state) do
    {:noreply, %{state | irqs: irqs+1}}
  end

  def handle_info(:calc, %{irqs: irqs} = state) do
    Process.send_after(self(), :calc, @interval * 1000)
    Logger.info "Number of interrupts received: #{irqs/@interval}"
    cond do
      irqs > 100 -> GenServer.cast AleRFM69, {:rssi, -div(irqs,100)}
      irqs <  50 -> GenServer.cast AleRFM69, {:rssi, 1}
      true -> nil
    end
    {:noreply, %{state | irqs: 0}}
  end
end
