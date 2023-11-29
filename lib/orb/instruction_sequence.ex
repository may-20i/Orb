defmodule Orb.InstructionSequence do
  defstruct type: :unknown_effect,
            body: [],
            contains: %{
              locals_effected: %{},
              globals_effected: %{},
              unknown_effect: false,
              i32: false,
              i64: false,
              f32: false,
              f64: false
            }

  alias Orb.Ops
  alias Orb.Constants

  def new([instruction]) do
    new(Ops.typeof(instruction, :primitive), [instruction])
  end

  def new(instructions) when is_list(instructions) do
    new(:unknown_effect, instructions)
    # raise "Inference of result type via reduce is unimplemented for now."
  end

  def new(type, instructions) when is_list(instructions) do
    %__MODULE__{
      type: type,
      body: instructions
    }
  end

  def expand(%__MODULE__{} = func) do
    body = func.body |> Enum.map(&Constants.expand_if_needed/1)
    %{func | body: body}
  end

  defimpl Orb.ToWat do
    alias Orb.ToWat.Instructions

    def to_wat(
          %Orb.InstructionSequence{body: instructions},
          indent
        ) do
      for instruction <- instructions do
        [Instructions.do_wat(instruction, indent), "\n"]
      end
    end
  end

  defimpl Orb.TypeNarrowable do
    def type_narrow_to(
          %Orb.InstructionSequence{type: Elixir.Integer, body: [single]} = seq,
          narrower_type
        ) do
      case Ops.types_compatible?(Elixir.Integer, narrower_type) do
        true ->
          %{
            seq
            | type: narrower_type,
              body: [Orb.TypeNarrowable.type_narrow_to(single, narrower_type)]
          }

        false ->
          seq
      end
    end

    def type_narrow_to(%Orb.InstructionSequence{} = seq, _), do: seq
  end
end
