defmodule RouterCore.Pipeline do
  @moduledoc """
  Pipeline GenServer.

  Receives `{:envelope, envelope}` messages from `RouterCore.IPC.RustHost`,
  applies configured transforms, then fans out to all configured outputs by
  issuing `send_output` IPC commands back to the Rust host.

  One Pipeline process is started per pipeline defined in the config.
  """

  use GenServer, restart: :permanent

  require Logger

  alias RouterCore.Envelope
  alias RouterCore.IPC.RustHost
  alias RouterCore.Metrics

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: via(name))
  end

  @doc "Deliver an envelope to the named pipeline."
  @spec deliver(String.t(), Envelope.t()) :: :ok
  def deliver(pipeline_name, %Envelope{} = envelope) do
    GenServer.cast(via(pipeline_name), {:envelope, envelope})
  end

  # ---------------------------------------------------------------------------
  # Server callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    state = %{
      name: Keyword.fetch!(opts, :name),
      from: Keyword.fetch!(opts, :from),
      to: Keyword.fetch!(opts, :to),
      transforms: Keyword.get(opts, :transforms, [])
    }

    Logger.info("Pipeline '#{state.name}' started (#{state.from} → #{Enum.join(state.to, ", ")})")
    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:envelope, envelope}, state) do
    envelope = apply_transforms(envelope, state.transforms)
    fanout(envelope, state.to)
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp fanout(envelope, outputs) do
    Enum.each(outputs, fn output_name ->
      case RustHost.send_output(output_name, envelope) do
        :ok ->
          Metrics.inc(:envelopes_emitted)

        {:error, reason} ->
          Logger.error("Failed to send envelope to output '#{output_name}': #{inspect(reason)}")
          Metrics.inc(:pipeline_errors)
      end
    end)
  end

  defp apply_transforms(envelope, []), do: envelope

  defp apply_transforms(envelope, [%{"type" => "add_fields", "fields" => fields} | rest]) do
    merged = Map.merge(ensure_map(envelope.payload), fields)
    apply_transforms(%{envelope | payload: merged}, rest)
  end

  # TODO(CODEX): add filter, rename_fields, jmespath_extract transforms
  defp apply_transforms(envelope, [unknown | rest]) do
    Logger.warning("Unknown transform type: #{inspect(unknown)}, skipping")
    apply_transforms(envelope, rest)
  end

  defp ensure_map(payload) when is_map(payload), do: payload
  defp ensure_map(_), do: %{}

  defp via(name), do: {:via, Registry, {RouterCore.Registry, {__MODULE__, name}}}
end
