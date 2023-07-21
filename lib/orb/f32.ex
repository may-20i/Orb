defmodule Orb.F32 do
  @moduledoc false

  @behaviour Orb.Type

  @impl Orb.Type
  def wasm_type(), do: :f32

  @impl Orb.Type
  def byte_count(), do: 4

  defmodule DSL do
    @moduledoc """
    32-bit float operators.
    """

    import Kernel, except: [+: 2, -: 2, *: 2, ===: 2, !==: 2, /: 2, <=: 2, >=: 2]

    def left + right do
      {:f32, :add, {left, right}}
    end

    def left - right do
      {:f32, :sub, {left, right}}
    end

    def left * right do
      {:f32, :mul, {left, right}}
    end

    def left / right do
      {:f32, :div, {left, right}}
    end

    def left === right do
      {:f32, :eq, {left, right}}
    end

    def left !== right do
      {:f32, :ne, {left, right}}
    end

    def left < right do
      {:f32, :lt, {left, right}}
    end

    def left > right do
      {:f32, :gt, {left, right}}
    end

    def left <= right do
      {:f32, :le, {left, right}}
    end

    def left >= right do
      {:f32, :ge, {left, right}}
    end
  end
end
