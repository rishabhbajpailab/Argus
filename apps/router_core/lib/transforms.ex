defmodule RouterCore.Transform do
  @moduledoc """
  Behaviour for envelope transform modules.

  A transform receives an `Envelope.t()` and a config map, and returns
  a (possibly modified) `Envelope.t()`.

  ## Implementing a transform

      defmodule MyTransform do
        @behaviour RouterCore.Transform

        @impl RouterCore.Transform
        def apply(%RouterCore.Envelope{} = envelope, config) do
          # ... modify envelope ...
          envelope
        end
      end
  """

  alias RouterCore.Envelope

  @doc "Apply the transform to the given envelope with the provided config."
  @callback apply(Envelope.t(), map()) :: Envelope.t()
end
