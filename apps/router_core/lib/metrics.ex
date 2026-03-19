defmodule RouterCore.Metrics do
  @moduledoc """
  Simple in-process metrics store + HTTP endpoint.

  Counters:
    - envelopes_ingested
    - envelopes_emitted
    - pipeline_errors

  Exposed as JSON at GET /metrics on the configured port (default 4000).

  TODO(CODEX): Replace with a proper Prometheus /metrics scrape endpoint
               (e.g. using telemetry_metrics + telemetry_metrics_prometheus).
  """

  use GenServer

  require Logger

  @valid_counters [:envelopes_ingested, :envelopes_emitted, :pipeline_errors]

  alias Plug.Cowboy

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Increment a counter by 1."
  @spec inc(atom()) :: :ok
  def inc(counter) do
    GenServer.cast(__MODULE__, {:inc, counter})
  end

  @doc "Return a snapshot of all counters."
  @spec snapshot() :: map()
  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  # ---------------------------------------------------------------------------
  # Server callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    port = Keyword.get(opts, :port, 4000)

    state = %{
      envelopes_ingested: 0,
      envelopes_emitted: 0,
      pipeline_errors: 0
    }

    case Cowboy.http(RouterCore.Metrics.Router, [], port: port) do
      {:ok, _pid} ->
        Logger.info("Metrics endpoint listening on http://0.0.0.0:#{port}/metrics")

      {:error, reason} ->
        Logger.warning("Could not start metrics HTTP server: #{inspect(reason)}")
    end

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:inc, counter}, state) when counter in @valid_counters do
    {:noreply, Map.update!(state, counter, &(&1 + 1))}
  end

  def handle_cast({:inc, unknown}, state) do
    Logger.warning("Metrics.inc/1 called with unknown counter: #{inspect(unknown)}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:snapshot, _from, state) do
    {:reply, state, state}
  end
end

defmodule RouterCore.Metrics.Router do
  @moduledoc "Minimal Plug router that serves the /metrics JSON endpoint."

  use Plug.Router

  plug :match
  plug :dispatch

  get "/metrics" do
    body = RouterCore.Metrics.snapshot() |> Jason.encode!()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, body)
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
