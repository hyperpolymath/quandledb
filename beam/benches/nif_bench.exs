# benches/nif_bench.exs
Benchee.run(
  %{
    "semantic_lookup (stub/nif)" => fn -> QuandleDBNif.semantic_lookup("3_1") end,
    "semantic_equivalents (stub/nif)" => fn -> QuandleDBNif.semantic_equivalents("3_1") end
  },
  time: 2,
  memory_time: 1
)
