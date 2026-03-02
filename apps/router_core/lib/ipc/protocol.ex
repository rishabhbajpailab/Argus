defmodule RouterCore.IPC.Protocol do
  @moduledoc """
  Encode/decode line-delimited JSON messages exchanged with the Rust host.

  ### Elixir → Rust (commands)
      %{cmd: "start_input",  name: "kafka_in",  config: %{...}}
      %{cmd: "start_output", name: "kafka_out", config: %{...}}
      %{cmd: "send_output",  name: "kafka_out", envelope: %{...}}
      %{cmd: "shutdown"}

  ### Rust → Elixir (events)
      %{"event" => "ingest", "input" => "kafka_in", "envelope" => %{...}}
      %{"event" => "ack",    "ref" => "..."}
      %{"event" => "error",  "message" => "...", "details" => %{...}}
  """

  alias RouterCore.Envelope

  @doc "Encode a command map to a newline-terminated JSON binary."
  @spec encode(map()) :: binary()
  def encode(command) when is_map(command) do
    Jason.encode!(command) <> "\n"
  end

  @doc "Decode a JSON line from the Rust host. Returns `{:ok, map}` or `{:error, reason}`."
  @spec decode(binary()) :: {:ok, map()} | {:error, term()}
  def decode(line) do
    case Jason.decode(String.trim(line)) do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:ok, other} -> {:error, {:unexpected_value, other}}
      {:error, _} = err -> err
    end
  end

  @doc "Build a `start_input` command."
  @spec start_input(String.t(), map()) :: map()
  def start_input(name, config),
    do: %{"cmd" => "start_input", "name" => name, "config" => config}

  @doc "Build a `start_output` command."
  @spec start_output(String.t(), map()) :: map()
  def start_output(name, config),
    do: %{"cmd" => "start_output", "name" => name, "config" => config}

  @doc "Build a `send_output` command."
  @spec send_output(String.t(), Envelope.t()) :: map()
  def send_output(name, %Envelope{} = envelope),
    do: %{"cmd" => "send_output", "name" => name, "envelope" => Envelope.to_map(envelope)}

  @doc "Build a `shutdown` command."
  @spec shutdown() :: map()
  def shutdown, do: %{"cmd" => "shutdown"}
end
