defmodule QuandleDBNifAspectTest do
  use ExUnit.Case

  @moduledoc """
  Aspect-based tests for the QuandleDB BEAM NIF boundary.
  Asserts resilience against adversarial or extreme inputs.
  """

  test "resists extreme length inputs" do
    huge_str = String.duplicate("A", 1_000_000)
    result = QuandleDBNif.semantic_lookup(huge_str)
    assert match?({:ok, _}, result) or match?({:error, _}, result)
  end

  test "resists null bytes and control characters" do
    nasty_str = "abc\0def\n\r\t\x1b"
    result = QuandleDBNif.semantic_equivalents(nasty_str)
    assert match?({:ok, _}, result) or match?({:error, _}, result)
  end

  test "resists invalid unicode" do
    invalid_str = <<0xFFFF::utf16>>
    result = QuandleDBNif.semantic_lookup(invalid_str)
    assert match?({:ok, _}, result) or match?({:error, _}, result)
  end
end
