defmodule Stats do

  use GenServer
  require Logger

  @hour_template %{
    interrupts: 0,
    crc_ok: 0,
    crc_failed: 0,
    timeout: 0
  }

  def get_stats do
    GenServer.call __MODULE__, {:results}
  end

  def add_type(type) do
    GenServer.cast __MODULE__, {:data, type}
  end

  def start_link do
    Logger.info "Starting statistics process..."
    GenServer.start_link(__MODULE__, {}, name: __MODULE__)
  end

  def init(_) do
    state = %{
      start: 0,
      hourly: (0..23 |> Enum.map( &( {&1, @hour_template} ) ) |> Enum.into(%{}))
    }
    {:ok, state}
  end

  def handle_cast({:data, type}, %{start: start} = state) when start == 0 do
    handle_cast({:data, type}, %{state | start: :os.system_time(:seconds) })
  end

  def handle_cast({:data, type}, %{hourly: hourly, start: start} = state) do
    if :os.system_time(:seconds) > (start+3600*24) do
      Logger.debug "Statistics collection stopped."
      {:noreply, state}
    else
      {_, {h, _, _}} = :calendar.local_time()
      new_hourly = update_in(hourly, [h, type], &( &1 + 1 ))
      {:noreply, %{state | hourly: new_hourly}}
    end
  end

  def handle_call({:results}, _from, state), do: {:reply, state, state}

end
