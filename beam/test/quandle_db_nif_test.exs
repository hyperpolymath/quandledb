defmodule QuandleDBNifTest do
  use ExUnit.Case, async: false

  @base_url System.get_env("QDB_LIVE_TEST_BASE_URL")

  if @base_url == nil or @base_url == "" do
    setup_all do
      old_mode = System.get_env("QDB_NIF_MODE")
      System.put_env("QDB_NIF_MODE", "stub")
      on_exit(fn ->
        if old_mode, do: System.put_env("QDB_NIF_MODE", old_mode), else: System.delete_env("QDB_NIF_MODE")
      end)
      :ok
    end

    test "semantic_lookup returns scaffold payload" do
      assert {:ok, payload} = QuandleDBNif.semantic_lookup("3_1")
      assert payload[:name] == "3_1"
      assert payload[:descriptor_version] == "stub-v1"
    end

    test "semantic_equivalents returns scaffold buckets" do
      assert {:ok, payload} = QuandleDBNif.semantic_equivalents("3_1")
      assert payload[:name] == "3_1"
      assert payload[:strong_candidates] == ["3_1"]
      assert payload[:weak_candidates] == []
      assert payload[:combined_candidates] == ["3_1"]
      assert payload[:count] == 1
    end

    test "wrapper validates argument type" do
      assert {:error, :invalid_argument} = QuandleDBNif.semantic_lookup(31)
      assert {:error, :invalid_argument} = QuandleDBNif.semantic_equivalents(:bad)
    end
  else
    test "unit tests disabled when running full-stack integration tests" do
      assert true
    end
  end
end
