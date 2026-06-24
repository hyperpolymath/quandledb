<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Owner: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# DB-3 Index Strategy

**Source:** PROOF-NARRATIVE.md §3 DB-3. Phase A audit 2026-06-01.

This file is the **Phase A audit deliverable** for `quandledb#33`. It
inventories every column in the `quandle_semantic_index` table,
classifies its query-access pattern, and recommends an index strategy.

## Phase A — what's done

3 new indexes added to `SEMANTIC_INDEX_STATEMENTS` in `server/serve.jl`:

| Index | Column | Type | Rationale |
|-------|--------|------|-----------|
| `idx_semantic_writhe` | `writhe` | B-tree | Filter on `GET /api/knots?writhe=X`; medium card (~100) |
| `idx_semantic_genus` | `genus` | B-tree | Filter on both `/api/knots` + `/api/semantic`; sparse but useful |
| `idx_semantic_gencount` | `quandle_generator_count` | B-tree | Currently forced in-memory after fetch; index pays for itself |

Total indexes now: **10** (was 7).

## Column inventory (full audit)

| Column | Type | Card. | Filtered by | Index status | Index kind |
|--------|------|-------|-------------|--------------|------------|
| `knot_name` | TEXT (PK) | ~10⁴ | single-knot lookups | implicit PK | — |
| `descriptor_version` | TEXT | 1-2 | none | — | skip |
| `descriptor_hash` | TEXT | ~10⁴ | `/api/semantic-equivalents/:name` (line 341 of serve.jl); `/api/semantic?descriptor_hash=X` (line 786) | `idx_semantic_hash` (already) | hash/B-tree |
| `quandle_key` | TEXT | ~5000 | `/api/semantic?quandle_key=X` (line 790); `semantic_equivalence_buckets` (line 344) | `idx_semantic_key` (already) | hash/B-tree |
| `diagram_format` | TEXT | 2-3 | none | — | skip |
| `canonical_representation` | TEXT | unique | none | — | skip |
| `component_count` | INTEGER | 1-3 | none | — | skip (too low card) |
| `crossing_number` | INTEGER | ~50 | `/api/knots`, `/api/semantic`, KRL pushdown (line 175) | `idx_semantic_crossing` (already) | B-tree |
| `writhe` | INTEGER | ~100 | `/api/knots?writhe=X` (line 694), KRL pushdown (line 176) | **NEW: `idx_semantic_writhe`** | B-tree |
| `genus` | INTEGER | ~20 | `/api/knots?genus=X` (line 695), `/api/semantic?genus=X` (line 754), KRL pushdown (line 177) | **NEW: `idx_semantic_genus`** | B-tree |
| `determinant` | INTEGER | ~500 | `/api/knots?determinant=X`, `/api/semantic?determinant=X` | `idx_semantic_determinant` (already) | B-tree |
| `signature` | INTEGER | ~200 | `/api/semantic?signature=X` | `idx_semantic_signature` (already) | B-tree |
| `alexander_polynomial` | TEXT | ~2000 | `find_equivalent` stages (no direct filter) | — | skip Phase B (full-text deferred) |
| `jones_polynomial` | TEXT | ~3000 | same | — | skip Phase B |
| `quandle_generator_count` | INTEGER | ~100 | `/api/semantic?quandle_generator_count=X` (line 756), in-memory filter (lines 779-780) | **NEW: `idx_semantic_gencount`** | B-tree |
| `quandle_relation_count` | INTEGER | ~80 | none (could be added) | — | skip until queried |
| `quandle_degree_partition` | TEXT | ~500 | none | — | skip Phase B |
| `colouring_count_3` | INTEGER | ~300 | `/api/semantic?colouring_count_3=X` | `idx_semantic_col3` (already) | B-tree |
| `colouring_count_5` | INTEGER | ~300 | (none directly today, but `quandle_key` derives from it) | `idx_semantic_col5` (already) | B-tree |
| `indexed_at` | TEXT | per-load | none | — | skip |

## Phase B — what's queued

Phase B replaces raw `CREATE INDEX` DDL with calls to Skein.jl's
public index-management API once that API exists. Required:

```julia
create_index!(db::SkeinDB, table::String, column::String, kind::Symbol = :btree)
drop_index!(db::SkeinDB, index_name::String)
list_indices(db::SkeinDB, table::String) :: Vector{String}
```

This is the upstream blocker; should be filed on Skein.jl issue
tracker when this lands. Until then, raw DDL in
`SEMANTIC_INDEX_STATEMENTS` is the working pattern.

## Phase C — what's deferred

- **Full-text indexes on polynomial strings.** `alexander_polynomial`,
  `jones_polynomial`, `conway_polynomial`, `homfly_polynomial`. Would
  help substring or coefficient-range queries; SQLite has FTS5 but
  isn't currently wired into the schema. Defer to a future PR.
- **Materialised views** for the equivalence buckets. The
  `semantic_equivalence_buckets()` function (serve.jl line 336-357)
  scans the whole table; a materialised view keyed by `descriptor_hash`
  and `quandle_key` would O(1) the bucketing.
- **Composite indexes** for multi-column queries like
  `crossing_number=N AND determinant=D`. SQLite query planner may
  already use index intersection effectively; profile before adding.

## Profiling guidance

After this PR, verify the planner uses the new indexes:

```sql
EXPLAIN QUERY PLAN
SELECT knot_name FROM quandle_semantic_index WHERE writhe = 3;
-- expected: SEARCH ... USING INDEX idx_semantic_writhe

EXPLAIN QUERY PLAN
SELECT knot_name FROM quandle_semantic_index WHERE genus = 1;
-- expected: SEARCH ... USING INDEX idx_semantic_genus

EXPLAIN QUERY PLAN
SELECT knot_name FROM quandle_semantic_index WHERE quandle_generator_count = 5;
-- expected: SEARCH ... USING INDEX idx_semantic_gencount
```

If any of these report a SCAN instead of SEARCH, the index is
mis-named or the statistics need an `ANALYZE`.

## Cross-references

- PROOF-NARRATIVE.md §3 DB-3
- Audit doc `/tmp/krl-quandle-tangle-audit-2026-06-01.md` DB-3
- Issue #33 — full DB-3 tracker (Phases B, C remain queued)
- Issue #34 — DB-6 EXPLAIN (depends on this index layout for
  selectivity estimates)
