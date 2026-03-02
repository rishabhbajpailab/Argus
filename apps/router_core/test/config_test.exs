defmodule RouterCore.ConfigTest do
  use ExUnit.Case, async: true

  alias RouterCore.Config

  @fixture_dir Path.expand("fixtures", __DIR__)

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp write_yaml(name, content) do
    path = Path.join(System.tmp_dir!(), "argus_test_#{name}.yaml")
    File.write!(path, content)
    path
  end

  # ---------------------------------------------------------------------------
  # Valid config
  # ---------------------------------------------------------------------------

  test "loads a valid kafka_to_log config" do
    path = write_yaml("valid", """
    inputs:
      kafka_in:
        type: kafka
        brokers: "localhost:9092"
        topic: input.events
        group_id: test-group
    outputs:
      log_out:
        type: log
    pipelines:
      demo:
        from: kafka_in
        to:
          - log_out
    """)

    assert {:ok, config} = Config.load(path)
    assert config["inputs"]["kafka_in"]["type"] == "kafka"
    assert config["outputs"]["log_out"]["type"] == "log"
    assert config["pipelines"]["demo"]["from"] == "kafka_in"
  end

  # ---------------------------------------------------------------------------
  # Missing top-level keys
  # ---------------------------------------------------------------------------

  test "returns error when 'inputs' key is missing" do
    path = write_yaml("no_inputs", """
    outputs:
      log_out:
        type: log
    pipelines:
      demo:
        from: kafka_in
        to: [log_out]
    """)

    assert {:error, msg} = Config.load(path)
    assert msg =~ "inputs"
  end

  test "returns error when 'outputs' key is missing" do
    path = write_yaml("no_outputs", """
    inputs:
      kafka_in:
        type: kafka
        brokers: localhost:9092
        topic: t
        group_id: g
    pipelines:
      demo:
        from: kafka_in
        to: [kafka_in]
    """)

    assert {:error, msg} = Config.load(path)
    assert msg =~ "outputs"
  end

  test "returns error when 'pipelines' key is missing" do
    path = write_yaml("no_pipelines", """
    inputs:
      kafka_in:
        type: kafka
        brokers: localhost:9092
        topic: t
        group_id: g
    outputs:
      log_out:
        type: log
    """)

    assert {:error, msg} = Config.load(path)
    assert msg =~ "pipelines"
  end

  # ---------------------------------------------------------------------------
  # Unknown connector type
  # ---------------------------------------------------------------------------

  test "returns error for unknown input type" do
    path = write_yaml("bad_input_type", """
    inputs:
      my_in:
        type: ftp
    outputs:
      log_out:
        type: log
    pipelines:
      demo:
        from: my_in
        to: [log_out]
    """)

    assert {:error, msg} = Config.load(path)
    assert msg =~ "ftp"
  end

  # ---------------------------------------------------------------------------
  # Pipeline references
  # ---------------------------------------------------------------------------

  test "returns error when pipeline 'from' references unknown input" do
    path = write_yaml("bad_from", """
    inputs:
      kafka_in:
        type: kafka
        brokers: localhost:9092
        topic: t
        group_id: g
    outputs:
      log_out:
        type: log
    pipelines:
      demo:
        from: does_not_exist
        to: [log_out]
    """)

    assert {:error, msg} = Config.load(path)
    assert msg =~ "does_not_exist"
  end

  test "returns error when pipeline 'to' references unknown output" do
    path = write_yaml("bad_to", """
    inputs:
      kafka_in:
        type: kafka
        brokers: localhost:9092
        topic: t
        group_id: g
    outputs:
      log_out:
        type: log
    pipelines:
      demo:
        from: kafka_in
        to: [no_such_output]
    """)

    assert {:error, msg} = Config.load(path)
    assert msg =~ "no_such_output"
  end

  # ---------------------------------------------------------------------------
  # Env-var interpolation
  # ---------------------------------------------------------------------------

  test "interpolates environment variables with default" do
    path = write_yaml("envvar", """
    inputs:
      kafka_in:
        type: kafka
        brokers: "${ARGUS_TEST_BROKERS:test-broker:9092}"
        topic: input.events
        group_id: g
    outputs:
      log_out:
        type: log
    pipelines:
      demo:
        from: kafka_in
        to: [log_out]
    """)

    assert {:ok, config} = Config.load(path)
    assert config["inputs"]["kafka_in"]["brokers"] == "test-broker:9092"
  end

  test "interpolates set environment variable over default" do
    System.put_env("ARGUS_TEST_BROKERS_OVERRIDE", "real-broker:9092")

    path = write_yaml("envvar_override", """
    inputs:
      kafka_in:
        type: kafka
        brokers: "${ARGUS_TEST_BROKERS_OVERRIDE:fallback:9092}"
        topic: input.events
        group_id: g
    outputs:
      log_out:
        type: log
    pipelines:
      demo:
        from: kafka_in
        to: [log_out]
    """)

    assert {:ok, config} = Config.load(path)
    assert config["inputs"]["kafka_in"]["brokers"] == "real-broker:9092"
  after
    System.delete_env("ARGUS_TEST_BROKERS_OVERRIDE")
  end

  # ---------------------------------------------------------------------------
  # Non-existent file
  # ---------------------------------------------------------------------------

  test "returns error for non-existent file" do
    assert {:error, msg} = Config.load("/tmp/does_not_exist_argus.yaml")
    assert msg =~ "not found"
  end
end
