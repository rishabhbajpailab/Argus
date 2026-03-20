defmodule RouterCore.Supervisor do
  @moduledoc """
  Top-level OTP supervisor for the router.

  Children (in start order):
    1. Registry        — for locating pipeline processes by name
    2. RustHost        — supervised Port wrapping the connector_host binary
    3. Metrics         — HTTP metrics endpoint
    4. Pipeline(s)     — one GenServer per pipeline in the config
  """

  use Supervisor

  alias RouterCore.IPC.RustHost
  alias RouterCore.{Metrics, Pipeline}

  @spec start_link(map()) :: Supervisor.on_start()
  def start_link(config) do
    Supervisor.start_link(__MODULE__, config, name: __MODULE__)
  end

  @impl Supervisor
  def init(config) do
    pipeline_children =
      config
      |> Map.get("pipelines", %{})
      |> Enum.map(fn {name, spec} ->
        Supervisor.child_spec(
          {Pipeline,
           [
             name: name,
             from: spec["from"],
             to: List.wrap(spec["to"]),
             transforms: spec["transforms"] || []
           ]},
          id: {Pipeline, name}
        )
      end)

    children =
      [
        {Registry, keys: :unique, name: RouterCore.Registry},
        {RustHost, config},
        {Metrics, [port: metrics_port()]}
      ] ++ pipeline_children

    # :rest_for_one ensures that if RustHost crashes, Metrics and all Pipeline
    # processes are also restarted. This prevents pipelines from sending to a
    # freshly-booted RustHost that has not yet re-registered its connectors.
    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp metrics_port do
    raw = System.get_env("METRICS_PORT", "4000")

    case Integer.parse(raw) do
      {port, ""} ->
        port

      _ ->
        raise ArgumentError,
              "METRICS_PORT must be a valid integer, got: #{inspect(raw)}"
    end
  end
end
