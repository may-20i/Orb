defmodule Orb.I32.Pointer do
  @moduledoc """
  Custom `Orb.CustomType` for pointer to 32-bit integer in memory.
  """

  @behaviour Orb.CustomType
  @behaviour Access

  @impl Orb.CustomType
  def wasm_type(), do: :i32

  @impl Orb.CustomType
  def byte_count(), do: 4

  @impl Access
  def fetch(%Orb.VariableReference{} = var_ref, at!: offset) do
    address =
      offset
      |> then(&Orb.Numeric.Multiply.optimized(Orb.I32, &1, 4))
      |> then(&Orb.Numeric.Add.optimized(Orb.I32, &1, var_ref))

    ast = {:i32, :load, address}
    {:ok, ast}
  end
end
