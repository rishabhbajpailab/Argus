defmodule RouterCore.EnvelopeTest do
  use ExUnit.Case, async: true

  alias RouterCore.Envelope

  describe "new/3" do
    test "generates id and ts when not provided" do
      env = Envelope.new("sensor_1", %{"v" => 1.5})

      assert is_binary(env.id)
      assert byte_size(env.id) == 16
      assert is_integer(env.ts)
      assert env.ts > 0
      assert env.source == "sensor_1"
      assert env.payload == %{"v" => 1.5}
      assert env.metadata == %{}
    end

    test "accepts explicit id and ts via opts" do
      env = Envelope.new("s", %{}, id: "myid", ts: 12345)

      assert env.id == "myid"
      assert env.ts == 12345
    end
  end

  describe "to_map/1 and from_map/1 round-trip" do
    test "round-trips a complete envelope" do
      original = Envelope.new("test_source", %{"key" => "value"}, metadata: %{"x" => 1})
      map = Envelope.to_map(original)
      restored = Envelope.from_map(map)

      assert restored.id == original.id
      assert restored.source == original.source
      assert restored.payload == original.payload
      assert restored.metadata == original.metadata
      assert restored.ts == original.ts
    end

    test "to_map/1 produces string keys" do
      env = Envelope.new("src", %{})
      map = Envelope.to_map(env)

      assert Map.has_key?(map, "id")
      assert Map.has_key?(map, "source")
      assert Map.has_key?(map, "payload")
      assert Map.has_key?(map, "metadata")
      assert Map.has_key?(map, "ts")
    end
  end

  describe "from_map/1 with missing or nil fields" do
    test "generates id when missing" do
      env = Envelope.from_map(%{"source" => "s", "payload" => %{}})

      assert is_binary(env.id)
      assert byte_size(env.id) == 16
    end

    test "substitutes 'unknown' source when missing" do
      env = Envelope.from_map(%{"id" => "abc", "payload" => %{}})

      assert env.source == "unknown"
    end

    test "allows nil payload" do
      env = Envelope.from_map(%{"id" => "abc", "source" => "s"})

      assert is_nil(env.payload)
    end

    test "defaults metadata to empty map when missing" do
      env = Envelope.from_map(%{"id" => "abc", "source" => "s", "payload" => %{}})

      assert env.metadata == %{}
    end
  end
end
