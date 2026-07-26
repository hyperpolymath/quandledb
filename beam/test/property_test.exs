defmodule QuandleDBNifPropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  @moduledoc """
  Property-based (P2P) tests for the QuandleDB BEAM NIF boundary.
  Asserts that arbitrary string inputs are handled safely without crashing the VM.
  """

  property "semantic_lookup handles arbitrary strings safely" do
    check all(str <- string(:printable)) do
      result = QuandleDBNif.semantic_lookup(str)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  property "semantic_equivalents handles arbitrary strings safely" do
    check all(str <- string(:printable)) do
      result = QuandleDBNif.semantic_equivalents(str)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
