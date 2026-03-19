defmodule RouterCore.Transforms.Identity do
  @moduledoc "No-op transform — returns the envelope unchanged."

  @behaviour RouterCore.Transform

  alias RouterCore.Envelope

  @impl RouterCore.Transform
  def apply(%Envelope{} = envelope, _config), do: envelope
end
