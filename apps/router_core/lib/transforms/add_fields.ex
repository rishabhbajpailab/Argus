defmodule RouterCore.Transforms.AddFields do
  @moduledoc """
  Transform that merges a static map of fields into the envelope payload.

  If the payload is not a map, it is replaced with the fields map.
  Logs a warning when a non-map payload is encountered.

  Config keys:
    - `"fields"` — map of field names to values to merge into the payload
  """

  @behaviour RouterCore.Transform

  require Logger

  alias RouterCore.Envelope

  @impl RouterCore.Transform
  def apply(%Envelope{payload: payload} = envelope, %{"fields" => fields}) when is_map(fields) do
    merged =
      case payload do
        p when is_map(p) ->
          Map.merge(p, fields)

        other ->
          Logger.warning(
            "AddFields transform: non-map payload #{inspect(other)} replaced with fields map"
          )

          fields
      end

    %{envelope | payload: merged}
  end

  def apply(envelope, _config), do: envelope
end
