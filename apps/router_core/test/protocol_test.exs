defmodule RouterCore.IPC.ProtocolTest do
  use ExUnit.Case, async: true

  alias RouterCore.IPC.Protocol
  alias RouterCore.Envelope

  describe "encode/1 and decode/1 round-trip" do
    test "start_input command" do
      cmd = Protocol.start_input("kafka_in", %{"type" => "kafka", "topic" => "events"})
      line = Protocol.encode(cmd)

      assert String.ends_with?(line, "\n")
      assert {:ok, decoded} = Protocol.decode(line)
      assert decoded["cmd"] == "start_input"
      assert decoded["name"] == "kafka_in"
      assert decoded["config"]["topic"] == "events"
    end

    test "start_output command" do
      cmd = Protocol.start_output("log_out", %{"type" => "log"})
      line = Protocol.encode(cmd)

      assert {:ok, decoded} = Protocol.decode(line)
      assert decoded["cmd"] == "start_output"
      assert decoded["name"] == "log_out"
    end

    test "send_output command" do
      env = Envelope.new("src", %{"val" => 42})
      cmd = Protocol.send_output("kafka_out", env)
      line = Protocol.encode(cmd)

      assert {:ok, decoded} = Protocol.decode(line)
      assert decoded["cmd"] == "send_output"
      assert decoded["name"] == "kafka_out"
      assert is_map(decoded["envelope"])
      assert decoded["envelope"]["source"] == "src"
    end

    test "shutdown command" do
      cmd = Protocol.shutdown()
      line = Protocol.encode(cmd)

      assert {:ok, decoded} = Protocol.decode(line)
      assert decoded["cmd"] == "shutdown"
    end
  end

  describe "decode/1 error cases" do
    test "returns error for invalid JSON" do
      assert {:error, _} = Protocol.decode("not json")
    end

    test "returns error for non-map JSON" do
      assert {:error, {:unexpected_value, _}} = Protocol.decode("[1, 2, 3]")
    end
  end
end
