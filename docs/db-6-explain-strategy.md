<!--
SPDX-License-Identifier: MPL-2.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# DB-6: EXPLAIN strategy for read-only API queries

Status: **Phase A landed 2026-06-01.** Phases B + C deferred.

## Goal

For every read-path SQL query in `server/serve.jl`, surface the SQLite
`EXPLAIN QUERY PLAN` output so query-plan regressions are visible during
review (Phase A) and at request time (Phase B+C).

This builds on DB-3 (B-tree index inventory): DB-3 enumerated the
indexed columns; DB-6 confirms the planner actually uses them.

## Echo-types audit

Per `[[proofs-must-check-and-cross-doc-echo-types]]`: echo-types is a
fibre-based loss-with-residue semantics library. It has zero SQL,
HTTP-server, or query-plan content. **Verdict: NOT-RELEVANT.** Recorded
once at `feedback_echo_types_audit_krl_tangle_quandledb_not_relevant.md`
for all five krl/tangle/quandledb obligations.

## Query inventory (current, as of 2026-06-01)

### Owned by quandledb (SQL visible)

| Handler | File:line | SQL surface | EXPLAIN reachable? |
|---------|-----------|-------------|---|
| `handle_semantic_detail` | `server/serve.jl:737` | `SELECT * FROM quandle_semantic_index WHERE knot_name = ?` (indirect via `ensure_semantic_entry!`) | **Yes** (Phase B) |
| `handle_semantic_equivalents` | `server/serve.jl:743` | two `SELECT` queries on `quandle_semantic_index` (strong + weak buckets); see `serve.jl:347` and `:350` | **Yes** (Phase B) |
| `handle_semantic_index` | `server/serve.jl:759` | dynamic `SELECT * FROM quandle_semantic_index WHERE … LIMIT ? OFFSET ?` — 7 optional filters + ordering on `(crossing_number, knot_name)` | **Yes** (Phase A — this is the scaffold target) |
| `handle_krl_query (SQL mode)` | `server/serve.jl:816` | arbitrary `SELECT`/`WITH` queries; passes through `parse_sql` → `eval_krl_program` | **Yes** (Phase B; deeper integration) |
| `handle_krl_query (KRL mode)` | same | KRL → SQL via the KRL evaluator under `server/krl/` | **Partial** (depends on `pushdown_used`; covered Phase C) |
| `handle_statistics` | `server/serve.jl:920` | `SELECT COUNT(*) AS n FROM quandle_semantic_index` + distribution queries | **Yes** (Phase B, low-priority) |

### Owned by Skein.jl (SQL opaque)

| Handler | File:line | Underlying call | Blocker |
|---------|-----------|-----------------|---|
| `handle_knots` | `server/serve.jl:699` | `query(db; crossing_number, writhe, genus, …)` | Skein.jl `query` builds SQL internally and does not return the constructed string; we cannot pipe it through `EXPLAIN` without a Skein.jl API addition. |
| `handle_knot_detail` | `server/serve.jl:728` | `fetch_knot(db, name)` | Same. |
| `semantic_summary_by_name` (called from `handle_knots`) | `server/serve.jl` | Joins via Skein.jl. | Same. |

**The Skein.jl gap is the same shape as the DB-3 Phase B blocker**
(Skein.jl does not expose `create_index!` / `drop_index!` / `list_indices`).
The fix is upstream: an addition to Skein.jl's public API surface, e.g.
`Skein.explain(db; …same kwargs as query) -> String`. Filed at
[hyperpolymath/quandledb#34](https://github.com/hyperpolymath/quandledb/issues/34)
as the parent for DB-6.

## Phase A — what landed today

- `server/query_explain.jl`: `explain_query_plan(conn::SQLite.DB, sql::String, args::Vector)::Vector{Dict}`
  - Wraps `EXPLAIN QUERY PLAN <sql>` with the same bind-arg pattern.
  - Returns one Dict per planner row: `id`, `parent`, `notused`, `detail`.
  - Read-only by construction (SQLite `EXPLAIN QUERY PLAN` is a `SELECT`).
- `server/test_query_explain.jl`: 4 assertions exercising:
  1. trivial `SELECT 1` plan is non-empty
  2. a single-table `SELECT` reads the expected table name in `detail`
  3. a filtered `SELECT * FROM quandle_semantic_index WHERE crossing_number = ?` mentions either `SEARCH` (index hit) or `SCAN` (no index hit) — sanity check that the planner emits structured output
  4. a `SELECT * … WHERE writhe = ?` mentions `idx_semantic_writhe` (the DB-3 index from PR #42); this is the regression hook that proves the index is actually used

These tests run against the canonical seed `data/knots.db` produced by
`server/test_quandle_axioms.jl` setup.

**Phase A does NOT** wire the utility into any public endpoint. The
public surface is still strictly `GET /api/knots`, `/api/semantic*`,
`/api/krl/query`, `/api/statistics`. That wiring is Phase B.

## Phase B — planned (next PR)

1. `GET /api/explain?endpoint=semantic&…` — accepts the same query
   parameters as `/api/semantic`, builds the same SQL via the same
   `handle_semantic_index` helper, but returns the EXPLAIN output
   instead of the rows.
2. `GET /api/explain?sql=…` — raw-SQL mode. Validates that the SQL is a
   plain `SELECT`/`WITH` (no `INSERT`/`UPDATE`/`DELETE`/`PRAGMA`) before
   piping through `explain_query_plan`. Reuses the existing
   `read-only-api-gate.yml` discipline (QD-12).
3. Per-request logging: when a query is served, also emit a JSON line
   `{"query": "...", "plan_summary": "..."}` to a structured log so
   regressions are visible in the metrics stream.

Phase B is blocked on a small Skein.jl upstream addition (see above).
Once that lands, the wrapper for `handle_knots` becomes one-line.

## Phase C — deferred (research-grade)

1. **Plan-snapshot regression test**: capture the EXPLAIN output for a
   canonical set of queries on the seed DB and assert byte-equality in
   CI. Any drift = fail. (Aligns with VeriSimDB seam-walk in
   `[[verisimdb-subject-of-everything]]`.)
2. **Cost-model integration**: pair each plan with the
   `tropical-resource-typing` cost-decoration so reviewers see expected
   row counts alongside the planner's pick.
3. **Composite-index suggestion**: examine which filter
   combinations on `/api/semantic` trigger SCANs (no index) and
   propose composite indexes. This is the DB-3 Phase C echo.

## Out of scope

- Anything beyond SQLite (no Postgres-style `pg_stat_statements`).
- Schema changes (DB-3 owns indexes; DB-6 only reads plans).
- Frontend rendering of plans (back-end-only this PR).
- ReScript→AffineScript migration of the frontend (tracked at quandledb#43; estate sweep at standards#252).

## Acceptance

- `server/query_explain.jl` compiles and `julia --project=server -e 'include("server/test_query_explain.jl"); run_db6_tests()'` returns nonzero only on regression.
- `docs/db-6-explain-strategy.md` exists and lists all read-path queries.
- No public endpoint is added (Phase A is utility-only).

## Cross-document

- DB-3 (`docs/db-3-index-strategy.md`): index inventory consumed here.
- QD-12 (`server/.github/workflows/read-only-api-gate.yml`): the
  read-only discipline that Phase B explain endpoint must honour.
- VeriSimDB seam-walk umbrella (`hyperpolymath/verisimdb#80`): pattern of
  plan-snapshot regression tests we will echo in Phase C.

## See also

- [hyperpolymath/quandledb#34](https://github.com/hyperpolymath/quandledb/issues/34) — DB-6 parent
- [hyperpolymath/quandledb#33](https://github.com/hyperpolymath/quandledb/issues/33) — DB-3 Phase B + C parent (Skein.jl gap is shared)
- [hyperpolymath/quandledb#42](https://github.com/hyperpolymath/quandledb/pull/42) — DB-3 Phase A (indexes that Phase A test 4 exercises)
