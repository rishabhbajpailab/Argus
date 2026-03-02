defmodule RouterCore do
  @moduledoc """
  Entry point for the RouterCore OTP application.

  On startup the application:
    1. Reads the ROUTER_CONFIG env var (falls back to a bundled example).
    2. Loads and validates the YAML configuration.
    3. Starts the supervision tree (Rust host + pipeline runtime + metrics).
  """

  use Application

  @default_config "configs/examples/kafka_to_log.yaml"

  @impl Application
  def start(_type, _args) do
    config_path = System.get_env("ROUTER_CONFIG", @default_config)

    case RouterCore.Config.load(config_path) do
      {:ok, config} ->
        RouterCore.Supervisor.start_link(config)

      {:error, reason} ->
        {:error, "Failed to load config #{config_path}: #{inspect(reason)}"}
    end
  end
end
