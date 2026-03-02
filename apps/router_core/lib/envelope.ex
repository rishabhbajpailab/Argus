defmodule RouterCore.Envelope do
  @moduledoc """
  The canonical event struct that flows through the pipeline.

  Fields:
    - id       — unique message identifier (binary string)
    - source   — name of the input that produced this envelope
    - payload  — the event body (map or binary)
    - metadata — additional key/value pairs (map)
    - ts       — ingestion timestamp (unix millis)
  """

  @enforce_keys [:id, :source, :payload]
  defstruct [:id, :source, :payload, metadata: %{}, ts: nil]

  @type t :: %__MODULE__{
          id: String.t(),
          source: String.t(),
          payload: map() | binary(),
          metadata: map(),
          ts: integer() | nil
        }

  @doc "Create a new envelope, generating an id and timestamp if not supplied."
  @spec new(String.t(), map() | binary(), keyword()) :: t()
  def new(source, payload, opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id, generate_id()),
      source: source,
      payload: payload,
      metadata: Keyword.get(opts, :metadata, %{}),
      ts: Keyword.get(opts, :ts, System.system_time(:millisecond))
    }
  end

  @doc "Convert an envelope to a plain map suitable for JSON encoding."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = env) do
    %{
      "id" => env.id,
      "source" => env.source,
      "payload" => env.payload,
      "metadata" => env.metadata,
      "ts" => env.ts
    }
  end

  @doc "Reconstruct an envelope from a plain map (e.g. decoded from JSON)."
  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      id: map["id"] || generate_id(),
      source: map["source"] || "unknown",
      payload: map["payload"],
      metadata: map["metadata"] || %{},
      ts: map["ts"]
    }
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
