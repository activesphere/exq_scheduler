defmodule ExqScheduler.Scheduler.Server do
  use GenServer

  defmodule State do
    defstruct schedules: nil, storage_opts: nil, server_opts: nil, range: nil
  end

  defmodule Opts do
    @enforce_keys [:timeout]
    defstruct timeout: nil, enqueue_missed_jobs: false, missed_jobs_threshold_duration: nil

    def new(opts) do
      timeout = opts[:timeout]
      enqueue_missed_jobs = opts[:enqueue_missed_jobs]

      missed_jobs_threshold_duration =
        if enqueue_missed_jobs do
          opts[:missed_jobs_threshold_duration]
        else
          timeout
        end

      %__MODULE__{
        timeout: timeout,
        enqueue_missed_jobs: enqueue_missed_jobs,
        missed_jobs_threshold_duration: missed_jobs_threshold_duration
      }
    end
  end

  alias ExqScheduler.Storage
  alias ExqScheduler.Schedule.TimeRange

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def load_schedules_config() do
    GenServer.cast(__MODULE__, :load_schedules_config)
  end

  def init(opts) do
    storage_opts = opts[:storage_opts]

    _ = Storage.load_schedules_config(storage_opts)

    state = %State{
      schedules: Storage.get_schedules(storage_opts),
      storage_opts: storage_opts,
      server_opts: opts[:server_opts]
    }

    next_tick(__MODULE__, 0)
    {:ok, state}
  end

  def handle_info({:tick, time}, state) do
    handle_tick(state, time)
    next_tick(__MODULE__, state.server_opts.timeout)
    {:noreply, state}
  end

  def handle_cast(:load_schedules_config, state) do
    _ = Storage.load_schedules_config(state.storage_opts)
    {:noreply, Storage.get_schedules(state.storage_opts)}
  end

  defp handle_tick(state, time) do
    Storage.persist_schedule_times(state.schedules, state.storage_opts)

    Storage.filter_active_jobs(state.schedules, get_range(state, time))
    |> Storage.enqueue_jobs(state.storage_opts)
  end

  defp next_tick(server, timeout) do
    time = Timex.now() |> Timex.to_naive_datetime()
    Process.send_after(server, {:tick, time}, timeout)
  end

  defp get_range(state, time) do
    TimeRange.new(time, state.server_opts.missed_jobs_threshold_duration)
  end
end
