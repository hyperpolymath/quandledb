<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Owner: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# Proof Narrative — QuandleDB

This file is the **single coherent story** of what QuandleDB proves,
what it assumes, and what it has left to prove.

For the per-obligation checklist with status/prover/effort, see
[PROOF-NEEDS.md](PROOF-NEEDS.md).
For the registry of every load-bearing unproven assumption, see
[ASSUMPTIONS.md](ASSUMPTIONS.md).

---

## 1. Position in the stack

QuandleDB is the **semantic identity layer** of the KRL stack:

```
┌─────────────────────────────────────────────────────────┐
│  KRL surface language     (hyperpolymath/krl)           │
└─────────────────┬───────────────────────────────────────┘
                  │ compiles to
                  ▼
┌─────────────────────────────────────────────────────────┐
│  TangleIR                                                │
└─────────────────┬───────────────────────────────────────┘
                  │ extract_presentation(ir)
                  ▼
┌─────────────────────────────────────────────────────────┐
│  QuandlePresentation  (THIS REPO)                        │
│    server/quandle_semantic.jl — Julia core               │
│    canonicalize_presentation → BLAKE3 fingerprint        │
│    _dihedral_colouring_count → integer invariants        │
└─────────────────┬───────────────────────────────────────┘
                  │ fingerprint, key
                  ▼
┌─────────────────────────────────────────────────────────┐
│  Skein.jl       — invariants table, query layer          │
└─────────────────────────────────────────────────────────┘
```

Consequence: QuandleDB owes correctness of the **functor**
`Q : Tang → Quand` and of the **canonical-form** that makes
fingerprints meaningful as equality-witnesses.

## 2. Proven now

All current results are **property-tested in Julia** (not formally
mechanised). Tests live in [`server/test_quandle_axioms.jl`](server/test_quandle_axioms.jl)
(250 LoC, 8 testsets, ~150 individual assertions).

### Algebraic / mathematical

| ID | Statement | Form | Where |
|----|-----------|------|-------|
| **Q-DihedralAxioms** | Dihedral quandle `Z_p` satisfies idempotence, right-invertibility, right self-distributivity for `p ∈ {3, 5, 7, 11, 13}` | Julia property tests, exhaustive over `Z_p` | `test_quandle_axioms.jl §1` |
| **Q-PresentationWF** | Extracted presentations are structurally well-formed (generator indices in-range, one relation per crossing) for the standard knot table (trefoil, figure-eight, cinquefoil) | Julia property tests | `test_quandle_axioms.jl §2` |
| **Q-CanonIdem** | `canonicalize ∘ canonicalize = canonicalize` on the standard test knots | Julia property tests | `test_quandle_axioms.jl §3` |
| **Q-DescriptorDet** | The same PD yields the same `presentation_hash`, `colouring_count_3`, `colouring_count_5`, `quandle_key` deterministically (run-to-run) | Julia property tests | `test_quandle_axioms.jl §4` |
| **Q-R1Reduce** | Injecting a nugatory crossing into a PD and running `r1_simplify` strictly reduces crossing/generator count | Julia property tests | `test_quandle_axioms.jl §5` |
| **Q-R2Reduce** | `s1·S1·s1·s1·s1` (trefoil + bigon) after `r2_simplify` agrees with the canonical trefoil on dihedral colouring counts | Julia property tests | `test_quandle_axioms.jl §6` |
| **Q-ColorDistinguishes** | The three standard test knots are pairwise distinguished by at least one of `colouring_count_3` or `colouring_count_5` | Julia property tests | `test_quandle_axioms.jl §7` |
| **Q-KeyUniqueness** | `quandle_key` is pairwise distinct on the three standard test knots | Julia property tests | `test_quandle_axioms.jl §8` |

### Implementation

`extract_presentation`, `canonicalize_presentation`,
`canonical_presentation_blob`, `_dihedral_colouring_count` are
implemented in `server/quandle_semantic.jl` and exercised by the
above tests on the standard knot table. The implementation is
production-grade Julia (union-find for Wirtinger arc collapsing,
modular linear algebra for the colouring counts).

## 3. Remaining obligations (the narrative arc)

These extend `PROOF-NEEDS.md`'s previously-stated M1–M4 / S1–S3 with
the implementation-level obligations surfaced by the 2026-06-01
audit. The narrative is grouped by where the obligation sits in the
"PD → presentation → fingerprint → query" pipeline.

### Presentation extraction

#### QD-1 — `extract_presentation` is well-formed on arbitrary connected PD codes

**Claim.** For **every** connected `KnotTheory.PlanarDiagram` (not just
the three test knots), `extract_presentation(pd)` returns a
`QuandlePresentation` such that:
- generator indices are in `1..generator_count`
- relation count equals crossing count
- each relation's `lhs`, `rhs`, `out` are in range
- the union-find collapsing is correct (over-strand arcs `d` and `b`
  are identified at each crossing)

**Why valuable.** Generalises Q-PresentationWF from the standard knot
table to the full input space. Closes PROOF-NEEDS M1's remaining gap.

**Assumptions.**
- [[A-QD-1.1]] PD codes are well-formed: each crossing has exactly
  4 arcs in PD-positions `(a, b, c, d)`.
- [[A-QD-1.2]] Connectedness (or per-component handling) is checked
  by the caller; `extract_presentation` does not validate it.

**How to discharge.** Either:
- _Formal proof_ via Idris2 on a dependent-type-encoded
  `WellFormedPD`, or
- _Property-based test_ generating random PD codes from braid words
  (`KnotTheory.from_braid_word`) and verifying the four structural
  conditions.

#### QD-9 — Union-find traversal-order independence

**Claim.** The union-find in `_wirtinger_arc_to_generator` produces
the same `generator_count` and `arc_to_gen` mapping (up to the chosen
canonical labelling) regardless of the order in which crossings are
visited.

**Why valuable.** Reproducibility hazard. Same PD on different
array layouts could yield different generator-count without this,
which would silently destabilise `quandle_key`.

**Assumptions.**
- [[A-QD-9.1]] Path compression preserves equivalence classes.
- [[A-QD-9.2]] Iteration order of `pd.crossings` is deterministic at
  the Julia level (true for `Vector`).

**How to discharge.** Shuffle-test: for each PD in the test corpus,
randomly shuffle `pd.crossings`, re-extract, assert equality up to
canonical relabelling. Easy single-PR.

#### QD-10 — KRL parser accepts exactly the language defined by `spec/grammar.ebnf`

**Claim.** `server/krl/Parser.jl::parse_any(s)` succeeds iff `s` is a
string in the v0.1.0 KRL grammar.

**Why valuable.** Two KRL parsers exist (`KRLAdapter.jl` and
`server/krl/`); both must accept the same language for queries to be
portable. See KRL repo `KR-6`.

**Assumptions.**
- [[A-QD-10.1]] `spec/grammar.ebnf` v0.1.0 is unambiguous.
- [[A-QD-10.2]] Grammar in KRL repo and quandledb repo are kept in lock-step
  (currently a manual discipline; should be a CI check).

**How to discharge.** Differential property test against
`KRLAdapter.jl::parse_krl`. Coordinate with KRL `KR-6`.

#### QD-11 — SQL→KRL translation is semantics-preserving

**Claim.** For every SQL query `s` accepted by
`server/krl/SqlFrontend.jl::parse_sql`, the resulting `KRLProgram`
returns the same result set as `s` would on a reference SQL engine
over the same data.

**Why valuable.** User-visible queries depend on this. SqlFrontend
exists so users can write `SELECT * FROM knots WHERE crossing < 8`
and have it translate to `find where crossing < 8`. Semantic
preservation is the user-facing contract.

**Assumptions.**
- [[A-QD-11.1]] The SQL subset supported is well-defined (no
  joins, no subqueries, equality + comparison filters only — verify
  against `SqlFrontend.jl`).
- [[A-QD-11.2]] `KnotTheory.jl`'s notion of `crossing_number`,
  `writhe`, `genus` are stable across implementations.

**How to discharge.** Property test: for a corpus of supported SQL
queries, compare results against a reference Julia implementation
that traverses the knot table directly.

### Canonical form and fingerprinting

#### QD-3 — Colouring-count well-definedness

(Re-statement of PROOF-NEEDS M4 with the assumption registry.)

**Claim.** `_dihedral_colouring_count(p, modulus)` depends only on
the isomorphism class of the fundamental quandle of `p`, not on the
particular `QuandlePresentation` chosen to represent it.

**Why valuable.** Without this, two presentations of the same knot
can return different colouring counts. The whole `quandle_key`
machinery becomes unreliable. This is **the central claim** of the
semantic-index layer.

**Assumptions.**
- [[A-QD-3.1]] The number of quandle homomorphisms from `Q` to a
  fixed finite quandle `T` is a class invariant of `Q` (standard
  algebraic result).
- [[A-QD-3.2]] `_dihedral_colouring_count` correctly counts solutions
  of the linear system over `Z_p` — i.e., the matrix `M` in the
  implementation correctly encodes the dihedral relations.

**How to discharge.** Two parts:
1. For each test knot, build two structurally-different presentations
   (e.g., shuffle the relations) and assert equal counts.
2. Lean 4 proof that the dihedral-relation matrix `M` correctly
   encodes the homomorphism-counting problem.

#### QD-4 — Fingerprint determinism across platforms

(Re-statement of PROOF-NEEDS S1.)

**Claim.** Given identical input PD codes,
`canonical_presentation_blob(p)` produces identical BLAKE3 output
bytes on Linux x86_64, Linux aarch64, macOS, and WebAssembly.

**Why valuable.** Two presentations with the same fingerprint are
isomorphic quandles, **across platforms**. Currently single-platform
tested only.

**Assumptions.**
- [[A-QD-4.1]] BLAKE3 produces identical output for identical input
  bytes (cryptographic primitive assumption).
- [[A-QD-4.2]] Julia's `string(...)` interpolation of `Int` is
  identical across platforms (it is — base-10 ASCII).
- [[A-QD-4.3]] `sort(...; by = r -> (r.lhs, r.rhs, r.out, r.is_inverse ? 1 : 0))`
  is stable and order-preserving across Julia implementations.

**How to discharge.** CI matrix run on Linux x86_64, Linux aarch64,
macOS, WSL; assert identical hashes. No formal proof needed; this
is an empirical platform contract.

#### QD-7 — Canonical-form ordering is a total order

**Claim.** The comparator
`by = r -> (r.lhs, r.rhs, r.out, r.is_inverse ? 1 : 0)` is a total
order on the actual domain of relations seen at runtime.

**Why valuable.** Currently the sort assumes total order. If two
relations agree on all four fields then `sort` is stable but the
output of `canonicalize_presentation` is **identical** for them —
which is fine. But if there are *invisible* relation distinctions
(e.g., generators that get the same numeric id but different
provenance) the canonicalisation silently merges them.

**Assumptions.**
- [[A-QD-7.1]] No relation field outside `(lhs, rhs, out, is_inverse)`
  affects quandle equality.

**How to discharge.** Either (a) prove no other field exists
(structurally trivial — the `QuandleRelation` struct has only these
four fields), or (b) add a comment + test asserting that.

#### QD-8 — `_dihedral_colouring_count` correctness

**Claim.** `_dihedral_colouring_count(p, modulus)` returns the number
of quandle homomorphisms from `fundamental(p)` to the dihedral
quandle `Z_modulus`.

**Why valuable.** This is the implementation of the central
invariant. Currently asserted by Q-DihedralAxioms (which tests the
target's quandle laws) and Q-ColorDistinguishes (which tests it
discriminates), but not by a direct correctness statement.

**Assumptions.**
- [[A-QD-8.1]] `_rank_mod_p!` correctly computes matrix rank over
  `Z_p` for prime `p`.
- [[A-QD-8.2]] `p^(g - rank)` is the count of solutions of the
  homogeneous linear system over `Z_p` with `g` unknowns and the
  computed rank.

**How to discharge.** Cross-check against an independent Brute-force
counter on small examples (`g ≤ 4`, `modulus ∈ {3, 5, 7}`); for the
algebraic argument cite a linear-algebra textbook.

### Reidemeister invariance

#### QD-2 — R3 invariance (the standing gap)

**Claim.** If diagrams `D₁` and `D₂` differ by a single Reidemeister-3
move, their `quandle_descriptor` outputs are equal.

**Why valuable.** PROOF-NEEDS M2 covers R1 and R2; R3 is the standing
gap. Without R3 we do not have full Reidemeister equivalence — the
invariant is incomplete.

**Assumptions.**
- [[A-QD-2.1]] R1 + R2 + R3 generate isotopy on classical knot
  diagrams (Reidemeister 1927 — standard).
- [[A-QD-2.2]] R3 acts on the fundamental quandle as a permutation
  of generators (standard quandle-theoretic result).

**How to discharge.** Either:
1. Contribute `r3_simplify` to `KnotTheory.jl` upstream (the right
   long-term home), or
2. Construct R3-related PD pairs by hand for a small corpus
   (trefoil, figure-eight) and verify `quandle_descriptor` equality.

#### QD-12 — Read-only API guarantee

**Claim.** No HTTP endpoint in `server/serve.jl` invokes a mutating
operation on the Skein.jl database.

**Why valuable.** `.claude/CLAUDE.md` states "Server is read-only
(database mutations via Skein.jl REPL)" as a convention. Promoting
this to a *checked* invariant prevents accidental mutation creep.

**Assumptions.**
- [[A-QD-12.1]] All Skein.jl mutating operations are identifiable by
  name (e.g., `store!`, `delete!`, `update!`).

**How to discharge.** Static check: `grep -E '(store!|delete!|update!)'
server/serve.jl` returns empty. Add as a CI gate.

### FFI / ABI

#### QD-5 — Idris2 ABI ↔ Zig FFI layout agreement

(Re-statement of PROOF-NEEDS S2.)

**Claim.** Every record type defined in `src/abi/Types.idr` has a
byte-for-byte identical memory layout in the corresponding Zig
struct in `src/ffi/semantic_ffi.zig` and the BEAM NIF in
`beam/native/quandle_db_nif.zig`.

**Why valuable.** Standard FFI hazard. Currently *declared* by the
existence of both files but not *proved*.

**Assumptions.**
- [[A-QD-5.1]] Idris2's `HasSize` / `HasAlignment` instances are
  correct for the platforms targeted.
- [[A-QD-5.2]] Zig's `extern struct` layout is C-ABI compatible.

**How to discharge.** Encode layouts directly in Idris2 dependent
types; emit a compile-time check in Zig (`@sizeOf`, `@alignOf`,
`@offsetOf`); cross-check at the BEAM NIF boundary with `bit_size`.

#### QD-6 — BEAM NIF never crashes the VM

(Re-statement of PROOF-NEEDS S3.)

**Claim.** For every input the Elixir side can pass to a NIF in
`beam/native/quandle_db_nif.zig`, the NIF either returns a valid
result, an `:error` term, or raises a NIF exception — but never
crashes the BEAM VM.

**Why valuable.** Production-critical. A NIF crash brings down the
whole VM.

**Assumptions.**
- [[A-QD-6.1]] Zig's safety guarantees (no UB on well-typed code in
  Release-Safe mode) hold for the NIF code paths.
- [[A-QD-6.2]] Elixir-side input types are validated before the NIF
  call (typespec discipline).

**How to discharge.** Fuzz harness on the NIF boundary: random bytes
+ random tagged-tuple shapes → NIF → assert "no VM crash". Combine
with Dialyzer for the typespec discipline.

## 4. The "stupid proof" exclusions

For completeness, we do **not** pursue:

- _"`QuandlePresentation` has these fields"_ — Julia struct
  definition.
- _"`extract_presentation` returns a `QuandlePresentation`"_ — Julia
  type assertion.
- _"BLAKE3 is collision-resistant"_ — cryptographic primitive
  assumption ([[A-QD-4.1]]).
- _"SHA-256 is collision-resistant"_ — same.
- _"union-find converges in nearly-linear amortised time"_ — Tarjan
  1975, out of scope.

## 5. How to add a new obligation

1. Add a row to [PROOF-NEEDS.md](PROOF-NEEDS.md) with `QD-N` id,
   category (M, S, ABI), prover, priority, effort.
2. Add the narrative entry here with statement, _why valuable_,
   status, **assumptions**, _how to discharge_. Assumptions block is
   non-optional.
3. Each new assumption gets an entry in
   [ASSUMPTIONS.md](ASSUMPTIONS.md) with `A-QD-N.M` id and
   MATH/DESIGN/EMPIRICAL/CRYPTO classification.

## 6. References

- Core algorithms: [`server/quandle_semantic.jl`](server/quandle_semantic.jl).
- Property tests: [`server/test_quandle_axioms.jl`](server/test_quandle_axioms.jl).
- Server: [`server/serve.jl`](server/serve.jl).
- KRL parser: [`server/krl/`](server/krl/).
- BEAM NIF: [`beam/`](beam/).
- ABI: [`src/abi/`](src/abi/), [`src/ffi/`](src/ffi/).
- Companion narratives:
  `hyperpolymath/krl/PROOF-NARRATIVE.md` — KRL surface
  `hyperpolymath/tangle/PROOF-NARRATIVE.md` — Tangle semantic core

## 7. Mathematical references

- Joyce 1982 — _A classifying invariant of knots, the knot quandle_.
- Matveev 1982 — _Distributive groupoids in knot theory_ (parallel
  introduction of quandles).
- Reidemeister 1927 — _Elementare Begründung der Knotentheorie_
  (R1+R2+R3 generation).
- Kauffman _Knots and Physics_ — colouring count and dihedral
  quandle as concrete invariant.
- Eisermann _The number of knot group representations_ —
  faithfulness of the fundamental quandle on prime alternating knots.
