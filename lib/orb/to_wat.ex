defprotocol Orb.ToWat do
  @doc "Protocol for converting to WebAssembly text format (.wat)"
  def to_wat(data, indent)
end

# TODO: remove this.
# A lot of the instruction are implemented as tuples.
# They might all become structs in the future, which means this could be removed.
defimpl Orb.ToWat, for: Tuple do
  def to_wat(tuple, indent) do
    Orb.ToWat.Instructions.do_wat(tuple, indent)
  end
end

defmodule Orb.ToWat.Helpers do
  alias Orb.CustomType

  def do_type(type) do
    case type do
      :i64 ->
        "i64"

      :i32 ->
        "i32"

      :f64 ->
        "f64"

      :f32 ->
        "f32"

      # e.g. {I32, I32}
      tuple when is_tuple(tuple) ->
        tuple |> Tuple.to_list() |> Enum.map(&do_type/1) |> Enum.join(" ")

      type ->
        CustomType.resolve!(type) |> to_string()
    end
  end
end
