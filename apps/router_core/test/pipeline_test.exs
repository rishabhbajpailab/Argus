defmodule RouterCore.PipelineTest do
  use ExUnit.Case, async: true

  alias RouterCore.{Envelope, Pipeline}

  # ---------------------------------------------------------------------------
  # Setup: start a Registry + a mock RustHost + a Pipeline under test
  # ---------------------------------------------------------------------------

  setup do
    registry = start_supervised!({Registry, keys: :unique, name: RouterCore.Registry})

    test_pid = self()

    # Start a stub GenServer for RustHost
    {:ok, stub} = GenServer.start(RustHostStub, test_pid, name: RouterCore.IPC.RustHost)

    %{stub: stub, registry: registry}
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  test "pipeline delivers envelope to a single output", %{} do
    {:ok, _pid} =
      Pipeline.start_link(
        name: "test_single",
        from: "kafka_in",
        to: ["log_out"],
        transforms: []
      )

    envelope = Envelope.new("kafka_in", %{"msg" => "hello"})
    Pipeline.deliver("test_single", envelope)

    assert_receive {:sent_output, "log_out", ^envelope}, 500
  end

  test "pipeline fans out to multiple outputs", %{} do
    {:ok, _pid} =
      Pipeline.start_link(
        name: "test_fanout",
        from: "kafka_in",
        to: ["log_out", "kafka_out"],
        transforms: []
      )

    envelope = Envelope.new("kafka_in", %{"msg" => "fanout"})
    Pipeline.deliver("test_fanout", envelope)

    assert_receive {:sent_output, "log_out", _}, 500
    assert_receive {:sent_output, "kafka_out", _}, 500
  end

  test "add_fields transform merges fields into payload", %{} do
    {:ok, _pid} =
      Pipeline.start_link(
        name: "test_transform",
        from: "kafka_in",
        to: ["log_out"],
        transforms: [%{"type" => "add_fields", "fields" => %{"routed_by" => "argus"}}]
      )

    envelope = Envelope.new("kafka_in", %{"msg" => "data"})
    Pipeline.deliver("test_transform", envelope)

    assert_receive {:sent_output, "log_out", received_envelope}, 500
    assert received_envelope.payload["routed_by"] == "argus"
    assert received_envelope.payload["msg"] == "data"
  end

  test "unknown transform is skipped without crash", %{} do
    {:ok, _pid} =
      Pipeline.start_link(
        name: "test_unknown_transform",
        from: "kafka_in",
        to: ["log_out"],
        transforms: [%{"type" => "does_not_exist"}]
      )

    envelope = Envelope.new("kafka_in", %{"msg" => "safe"})
    Pipeline.deliver("test_unknown_transform", envelope)

    assert_receive {:sent_output, "log_out", _}, 500
  end
end

# ---------------------------------------------------------------------------
# Stub GenServer that replaces RouterCore.IPC.RustHost in tests
# ---------------------------------------------------------------------------

defmodule RustHostStub do
  use GenServer

  def init(test_pid), do: {:ok, test_pid}

  def handle_call({:send_output, name, envelope}, _from, test_pid) do
    send(test_pid, {:sent_output, name, envelope})
    {:reply, :ok, test_pid}
  end
end
