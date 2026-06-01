<!--
SPDX-License-Identifier: MPL-2.0
Owner: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# Assumptions Registry — QuandleDB

Every load-bearing **unproven** assumption used in this repo, with an
ID, classification, and the obligation it supports.

Classifications:
- **MATH** — true by an external mathematical theorem (cite it)
- **DESIGN** — true by construction in our code (must remain true; flag if you change the named code)
- **EMPIRICAL** — believed from testing; not formally verified
- **CRYPTO** — standard cryptographic-primitive assumption

Cross-references use `[[A-QD-N.M]]` syntax, resolved here.

---

## Presentation extraction (QD-1, QD-9, QD-10, QD-11)

| ID | Class | Statement | Cited by | Where it lives |
|----|-------|-----------|----------|----------------|
| A-QD-1.1 | DESIGN | PD codes are well-formed: each crossing has exactly 4 arcs in PD-positions `(a, b, c, d)` | QD-1 | `KnotTheory.PlanarDiagram` struct contract |
| A-QD-1.2 | DESIGN | Connectedness (or per-component handling) is checked by the caller; `extract_presentation` does not validate | QD-1 | `server/quandle_semantic.jl::extract_presentation` |
| A-QD-9.1 | MATH | Path compression in union-find preserves equivalence classes | QD-9 | Tarjan 1975 |
| A-QD-9.2 | DESIGN | Iteration order of `pd.crossings` (a `Vector{Crossing}`) is deterministic at the Julia level | QD-9 | Julia language guarantee |
| A-QD-10.1 | DESIGN | `spec/grammar.ebnf` v0.1.0 (in KRL repo) is unambiguous | QD-10 | `hyperpolymath/krl/spec/grammar.ebnf` |
| A-QD-10.2 | DESIGN | Grammar references in KRL repo and quandledb/server/krl/ are kept in lock-step (currently manual; CI gate is owed) | QD-10 | Both Parser.jl files |
| A-QD-11.1 | DESIGN | The SQL subset supported by `SqlFrontend.jl` is well-defined: no joins, no subqueries, equality + comparison filters only | QD-11 | `server/krl/SqlFrontend.jl` |
| A-QD-11.2 | MATH (effective) | `KnotTheory.jl`'s notion of `crossing_number`, `writhe`, `genus` is stable across implementations (standard knot-theoretic definitions) | QD-11 | KnotTheory.jl upstream |

## Canonical form and fingerprinting (QD-3, QD-4, QD-7, QD-8)

| ID | Class | Statement | Cited by | Where it lives |
|----|-------|-----------|----------|----------------|
| A-QD-3.1 | MATH | The number of quandle homomorphisms from a quandle `Q` to a fixed finite quandle `T` is a class invariant of `Q` | QD-3 | Joyce 1982; standard algebraic result |
| A-QD-3.2 | DESIGN | `_dihedral_colouring_count`'s matrix `M` correctly encodes the dihedral relations: row for relation `(a, b, c)` (positive) is `M[i, a] += 1; M[i, c] += 1; M[i, b] -= 2` mod `p` | QD-3 | `server/quandle_semantic.jl:253-270` |
| A-QD-4.1 | CRYPTO | BLAKE3 produces identical output for identical input bytes | QD-4 | BLAKE3 specification |
| A-QD-4.2 | MATH | Julia's `string(...)` interpolation of `Int` is identical across platforms (base-10 ASCII, no locale dependence) | QD-4 | Julia language guarantee |
| A-QD-4.3 | DESIGN | `sort(...; by = r -> (r.lhs, r.rhs, r.out, r.is_inverse ? 1 : 0))` is stable and order-preserving across Julia implementations | QD-4 | Julia `Base.sort` contract |
| A-QD-7.1 | DESIGN | No relation field outside `(lhs, rhs, out, is_inverse)` affects quandle equality (the `QuandleRelation` struct has only these four fields) | QD-7 | `server/quandle_semantic.jl::QuandleRelation` |
| A-QD-8.1 | DESIGN | `_rank_mod_p!` correctly computes matrix rank over `Z_p` for prime `p` | QD-8 | `server/quandle_semantic.jl:207-251` |
| A-QD-8.2 | MATH | For a homogeneous linear system over `Z_p` (prime) with `g` unknowns and rank `r`, the solution count is `p^(g - r)` | QD-8 | Standard linear algebra |

## Reidemeister invariance (QD-2, QD-12)

| ID | Class | Statement | Cited by | Where it lives |
|----|-------|-----------|----------|----------------|
| A-QD-2.1 | MATH | R1 + R2 + R3 generate isotopy on classical knot diagrams (Reidemeister 1927) | QD-2, QD-3 | Standard |
| A-QD-2.2 | MATH | R3 acts on the fundamental quandle as a permutation of generators, leaving the quandle isomorphism class invariant | QD-2 | Standard quandle-theoretic result |
| A-QD-12.1 | DESIGN | All Skein.jl mutating operations are identifiable by name suffix (e.g. `store!`, `delete!`, `update!` — Julia convention) | QD-12 | Skein.jl upstream + Julia convention |

## FFI / ABI (QD-5, QD-6)

| ID | Class | Statement | Cited by | Where it lives |
|----|-------|-----------|----------|----------------|
| A-QD-5.1 | DESIGN | Idris2's `HasSize` / `HasAlignment` instances are correct for the platforms targeted | QD-5 | Idris2 stdlib + per-platform overrides |
| A-QD-5.2 | DESIGN | Zig's `extern struct` layout is C-ABI compatible (no field reordering, padding per platform) | QD-5 | Zig language guarantee |
| A-QD-6.1 | DESIGN | Zig's safety guarantees (no UB on well-typed code in Release-Safe) hold for the NIF code paths in `beam/native/quandle_db_nif.zig` | QD-6 | Zig language guarantee + audit of the file |
| A-QD-6.2 | DESIGN | Elixir-side input types are validated by Dialyzer typespecs before the NIF call | QD-6 | `beam/lib/quandle_db_nif/native.ex` typespecs |

## Cryptographic primitives

| ID | Class | Statement | Cited by | Notes |
|----|-------|-----------|----------|-------|
| A-QD-4.1 | CRYPTO | BLAKE3 produces identical output for identical input bytes | QD-4 | (see above) |
| _(implicit)_ | CRYPTO | SHA-256 collision resistance (used as backup digest in `quandle_descriptor`) | QD-4 (extended) | Standard |

---

## How to use this file

- **Reading code.** When you see a function whose correctness depends
  on something not enforced by the local types — _that's an
  assumption_. Find or add the entry here and reference it by ID.
- **Writing a proof.** Every proof obligation in
  [PROOF-NARRATIVE.md](PROOF-NARRATIVE.md) names its assumptions by ID.
  Before discharging the proof, audit the assumptions.
- **Modifying load-bearing code.** Each DESIGN assumption names a
  file/component. If you edit that file, re-validate the assumption
  (or update the obligation if the design changed intentionally).

## Promoting / demoting assumptions

| From | To | Trigger |
|------|-----|---------|
| EMPIRICAL → MATH | discharge with a citation |
| EMPIRICAL → DESIGN | refactor to make it a structural invariant |
| MATH → (delete) | obligation has been re-cast not to need it |
| DESIGN → MATH (rare) | the design encodes a known theorem |
| any → CRYPTO | only for cryptographic primitives |

When you change a row, leave a one-line note in the changelog with the
date and reason.

---

## Changelog

| Date | Change | By |
|------|--------|-----|
| 2026-06-01 | Initial registry, scoped to QuandleDB obligations QD-1..QD-12 | Audit |
