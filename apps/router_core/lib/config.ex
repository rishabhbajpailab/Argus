defmodule RouterCore.Config do
  @moduledoc """
  Load and validate the YAML configuration file.

  Expected top-level keys: inputs, outputs, pipelines.

  Returns `{:ok, config_map}` on success or `{:error, reason}` on failure.
  """

  @valid_input_types ~w(kafka mqtt rabbitmq)
  @valid_output_types ~w(kafka log mqtt rabbitmq)

  @doc """
  Load configuration from a YAML file at `path`.
  Interpolates `${VAR:default}` environment variable references in string values.
  """
  @spec load(String.t()) :: {:ok, map()} | {:error, term()}
  def load(path) do
    with {:exists, true} <- {:exists, File.exists?(path)},
         {:ok, raw} <- YamlElixir.read_from_file(path),
         config = interpolate_env(raw),
         :ok <- validate(config) do
      {:ok, config}
    else
      {:exists, false} -> {:error, "config file not found: #{path}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validate a config map. Returns `:ok` or `{:error, reason}`.
  """
  @spec validate(map()) :: :ok | {:error, String.t()}
  def validate(config) do
    with :ok <- require_key(config, "inputs"),
         :ok <- require_key(config, "outputs"),
         :ok <- require_key(config, "pipelines"),
         :ok <- validate_inputs(config["inputs"]),
         :ok <- validate_outputs(config["outputs"]),
         :ok <- validate_pipelines(config["pipelines"], config["inputs"], config["outputs"]) do
      :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp require_key(map, key) do
    if Map.has_key?(map, key) and not is_nil(map[key]) do
      :ok
    else
      {:error, "missing required top-level key: '#{key}'"}
    end
  end

  defp validate_inputs(inputs) when is_map(inputs) do
    Enum.reduce_while(inputs, :ok, fn {name, spec}, _acc ->
      case validate_connector_spec(name, spec, @valid_input_types, "input") do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp validate_inputs(_), do: {:error, "'inputs' must be a map"}

  defp validate_outputs(outputs) when is_map(outputs) do
    Enum.reduce_while(outputs, :ok, fn {name, spec}, _acc ->
      case validate_connector_spec(name, spec, @valid_output_types, "output") do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp validate_outputs(_), do: {:error, "'outputs' must be a map"}

  defp validate_connector_spec(name, spec, valid_types, kind) when is_map(spec) do
    type = spec["type"]

    if type in valid_types do
      :ok
    else
      {:error,
       "#{kind} '#{name}' has unknown type '#{type}'. " <>
         "Valid types: #{Enum.join(valid_types, ", ")}"}
    end
  end

  defp validate_connector_spec(name, _spec, _valid, kind),
    do: {:error, "#{kind} '#{name}' spec must be a map"}

  defp validate_pipelines(pipelines, inputs, outputs) when is_map(pipelines) do
    Enum.reduce_while(pipelines, :ok, fn {name, spec}, _acc ->
      case validate_pipeline_spec(name, spec, inputs, outputs) do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp validate_pipelines(_, _, _), do: {:error, "'pipelines' must be a map"}

  defp validate_pipeline_spec(name, spec, inputs, outputs) when is_map(spec) do
    from = spec["from"]
    to = spec["to"]

    with :ok <- require_field(name, "from", from),
         :ok <- require_field(name, "to", to),
         :ok <- check_input_ref(name, from, inputs),
         :ok <- check_output_refs(name, List.wrap(to), outputs) do
      :ok
    end
  end

  defp validate_pipeline_spec(name, _, _, _),
    do: {:error, "pipeline '#{name}' spec must be a map"}

  defp require_field(pipeline, field, nil),
    do: {:error, "pipeline '#{pipeline}' is missing required field '#{field}'"}

  defp require_field(_pipeline, _field, _val), do: :ok

  defp check_input_ref(pipeline, from, inputs) do
    if Map.has_key?(inputs, from) do
      :ok
    else
      {:error, "pipeline '#{pipeline}' references unknown input '#{from}'"}
    end
  end

  defp check_output_refs(_pipeline, [], _outputs), do: :ok

  defp check_output_refs(pipeline, [out | rest], outputs) do
    if Map.has_key?(outputs, out) do
      check_output_refs(pipeline, rest, outputs)
    else
      {:error, "pipeline '#{pipeline}' references unknown output '#{out}'"}
    end
  end

  # ---------------------------------------------------------------------------
  # Environment variable interpolation  ${VAR:default}
  # ---------------------------------------------------------------------------

  defp interpolate_env(value) when is_binary(value) do
    Regex.replace(~r/\$\{([^}:]+)(?::([^}]*))?\}/, value, fn _, var, default ->
      System.get_env(var) || default || ""
    end)
  end

  defp interpolate_env(value) when is_map(value) do
    Map.new(value, fn {k, v} -> {k, interpolate_env(v)} end)
  end

  defp interpolate_env(value) when is_list(value) do
    Enum.map(value, &interpolate_env/1)
  end

  defp interpolate_env(value), do: value
end
