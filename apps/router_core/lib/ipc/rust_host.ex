defmodule RouterCore.IPC.RustHost do
  @moduledoc """
  GenServer that owns the Erlang Port connected to the `connector_host` Rust binary.

  On startup it:
    1. Spawns the Rust binary as a Port (line-buffered stdio).
    2. Issues `start_input` and `start_output` commands for every connector
       declared in the config.
    3. Relays inbound `ingest` events to the appropriate Pipeline GenServer.

  On shutdown it sends a `shutdown` command and closes the port.
  """

  use GenServer, restart: :permanent

  require Logger

  alias RouterCore.{Envelope, Metrics, Pipeline}
  alias RouterCore.IPC.Protocol

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @spec start_link(map()) :: GenServer.on_start()
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc "Send an envelope to a named output via the Rust host."
  @spec send_output(String.t(), Envelope.t()) :: :ok | {:error, term()}
  def send_output(output_name, %Envelope{} = envelope) do
    GenServer.call(__MODULE__, {:send_output, output_name, envelope})
  end

  # ---------------------------------------------------------------------------
  # Server callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(config) do
    bin = System.get_env("CONNECTOR_HOST_BIN", "./bin/connector_host")

    port =
      Port.open({:spawn_executable, bin}, [
        :binary,
        :use_stdio,
        :exit_status,
        {:line, 65_536},
        args: []
      ])

    state = %{port: port, config: config}
    send(self(), :configure)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:configure, state) do
    # Issue start_input for every declared input
    state.config
    |> Map.get("inputs", %{})
    |> Enum.each(fn {name, spec} ->
      send_command(state.port, Protocol.start_input(name, spec))
    end)

    # Issue start_output for every declared output
    state.config
    |> Map.get("outputs", %{})
    |> Enum.each(fn {name, spec} ->
      send_command(state.port, Protocol.start_output(name, spec))
    end)

    {:noreply, state}
  end

  # Inbound line from Rust host
  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    handle_line(line, state)
    {:noreply, state}
  end

  # Rust host exited
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("connector_host exited with status #{status}; restarting supervisor branch")
    {:stop, {:rust_host_exited, status}, state}
  end

  def handle_info(msg, state) do
    Logger.debug("RustHost unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:send_output, name, envelope}, _from, state) do
    cmd = Protocol.send_output(name, envelope)
    send_command(state.port, cmd)
    {:reply, :ok, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    send_command(state.port, Protocol.shutdown())
    Port.close(state.port)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp send_command(port, command) do
    Port.command(port, Protocol.encode(command))
  end

  defp handle_line(line, state) do
    case Protocol.decode(line) do
      {:ok, %{"event" => "ingest", "input" => input, "envelope" => env_map}} ->
        envelope = Envelope.from_map(env_map)
        Metrics.inc(:envelopes_ingested)
        route_to_pipelines(input, envelope, state.config)

      {:ok, %{"event" => "ack"}} ->
        :ok

      {:ok, %{"event" => "error", "message" => msg} = ev} ->
        Logger.error("connector_host error: #{msg} details=#{inspect(ev["details"])}")
        Metrics.inc(:pipeline_errors)

      {:error, reason} ->
        Logger.warning("Failed to decode line from connector_host: #{inspect(reason)}")
    end
  end

  defp route_to_pipelines(input_name, envelope, config) do
    config
    |> Map.get("pipelines", %{})
    |> Enum.each(fn {pipeline_name, spec} ->
      if spec["from"] == input_name do
        Pipeline.deliver(pipeline_name, envelope)
      end
    end)
  end
end
