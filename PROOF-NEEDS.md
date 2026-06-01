<!--
SPDX-License-Identifier: MPL-2.0
Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
Owner: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->

# PROOF-NEEDS — QuandleDB

Mathematical and systems obligations for the quandle semantic layer.

## Mathematical obligations

### M1. Quandle axioms preserved
Statement: For every `QuandlePresentation` produced by `extract_presentation`,
the derived action satisfies the three quandle axioms:

1. `a ▷ a = a` (idempotence)
2. For every `a`, the map `x ↦ x ▷ a` is a bijection (right-invertibility)
3. `(a ▷ b) ▷ c = (a ▷ c) ▷ (b ▷ c)` (right self-distributivity)

Current status: **property-tested** (2026-04-12).
- All three axioms verified algebraically for the dihedral quandle Z_p at
  p ∈ {3, 5, 7, 11, 13} — see `server/test_quandle_axioms.jl` § 1.
- Structural consistency of extracted presentations verified for standard
  knots (trefoil, figure-eight, cinquefoil) — see § 2.
- Remaining gap: formal proof that `extract_presentation` produces a
  valid Wirtinger presentation for arbitrary connected PD codes.

### M2. Reidemeister invariance
Statement: If diagrams D₁ and D₂ differ by a single Reidemeister move,
their extracted presentations produce the same fingerprint.

Current status: **property-tested for R1 and R2** (2026-04-12).
- R1: kink injection + `r1_simplify` verified to reduce crossing count and
  generator count — see `server/test_quandle_axioms.jl` § 5.
- R2: braid word `s1.S1.s1.s1.s1` (trefoil + bigon) after `r2_simplify`
  gives same dihedral colouring counts as canonical trefoil — § 6.
- R3: not yet covered (no programmatic R3-inverse available in KnotTheory.jl).
- Remaining gap: R3 invariance; formal proof via Wirtinger presentation
  isomorphism under each move type.

### M3. Canonicalisation is idempotent
Statement: `canonicalize_presentation(canonicalize_presentation(p)) ==
canonicalize_presentation(p)`.

Current status: **property-tested** (2026-04-12).
Verified for trefoil, figure-eight, cinquefoil — see
`server/test_quandle_axioms.jl` § 3.

### M4. Colouring count well-definedness
Statement: For a finite quandle Q and a presentation p, the number of
quandle homomorphisms from `fundamental(p)` to Q depends only on the
isomorphism class of `fundamental(p)` — not on the particular presentation.

Current status: this is a standard result; need to verify the
implementation actually respects it.

## Systems obligations

### S1. Fingerprint determinism across platforms
Statement: Given identical input bytes, `quandle_fingerprint` produces
identical output bytes on Linux x86_64, Linux aarch64, macOS, and WebAssembly.

Current status: single-platform tested only.

### S2. Idris2 ABI ↔ Zig FFI layout agreement
Statement: Every record type defined in `src/abi/Types.idr` has a
byte-for-byte identical memory layout in the corresponding Zig struct
in `src/ffi/semantic_ffi.zig`.

Current status: declared, not proved. Idris2's dependent types could
encode the layout directly — this is exactly what the ABI/FFI boundary
discipline is for.

### S3. NIF safety
Statement: BEAM NIFs in `beam/native/quandle_db_nif.zig` never crash the
BEAM VM, even on malformed input from the Elixir side.

Current status: tested on well-formed inputs only. No fuzz on the NIF boundary.

## Proof stack (intended)

- **Idris2** for ABI layout / type-level invariants
- **Property-based tests (Julia)** for mathematical invariants M1-M4 as
  empirical evidence
- **Zig's comptime** for layout assertions at the FFI boundary
- **BEAM Dialyzer** for NIF typespec discipline

## Implementation-level obligations (2026-06-01 audit extension)

The original M1–M4 / S1–S3 obligations above are mathematical and
systems contracts. The 2026-06-01 audit added implementation-level
obligations that complete the proof narrative. Full statements with
_why valuable_, status, explicit assumptions, and _how to discharge_
are in [PROOF-NARRATIVE.md](PROOF-NARRATIVE.md). Summary:

| # | Statement | Category | Priority | Effort | Status |
|---|-----------|----------|----------|--------|--------|
| QD-1 | `extract_presentation` well-formed on arbitrary connected PD codes | M | P1 | 3d | NOT STARTED (generalises Q-PresentationWF from 3 knots to full input space) |
| QD-2 | R3 invariance | M | P1 | 5d (or upstream PR to KnotTheory.jl) | BLOCKED on `r3_simplify` (stated standing gap in M2) |
| QD-3 | Colouring-count well-definedness | M | P1 | 2d | NOT STARTED (was M4) |
| QD-4 | Fingerprint determinism across platforms | S | P2 | 1d (CI matrix) | NOT STARTED (was S1) |
| QD-5 | Idris2 ABI ↔ Zig FFI layout agreement | ABI | P2 | 3d | NOT STARTED (was S2) |
| QD-6 | BEAM NIF never crashes the VM | S | P1 | 1w (fuzz harness) | NOT STARTED (was S3) |
| QD-7 | Canonical-form ordering is total | M | P3 | 1h (structural; see narrative) | NOT STARTED |
| QD-8 | `_dihedral_colouring_count` correctness | M | P2 | 2d | NOT STARTED |
| QD-9 | Union-find traversal-order independence | M / impl | P2 | 2h (shuffle test) | NOT STARTED |
| QD-10 | KRL parser accepts exactly v0.1.0 grammar | M / impl | P1 | 4h (differential test) | NOT STARTED (cross-references KRL repo KR-6) |
| QD-11 | SQL→KRL translation semantics-preserving | M / impl | P2 | 3d | NOT STARTED |
| QD-12 | Read-only API guarantee | S | P3 | 1h (CI grep gate) | NOT STARTED |

## Categories

| Code | Meaning | Applies? |
|------|---------|----------|
| M | Mathematical obligations | Yes (M1–M4 + QD-1, QD-2, QD-3, QD-7, QD-8, QD-9, QD-10, QD-11) |
| S | Systems obligations | Yes (S1–S3 + QD-4, QD-6, QD-12) |
| ABI | ABI/FFI obligations | Yes (QD-5) |

## How to propose a new obligation

1. State claim precisely.
2. Classify: mathematical, systems, or contract.
3. Either add property-based test as empirical evidence, OR write formal
   proof under `verification/` (create that dir if needed).
4. Add the narrative entry (statement, _why valuable_, status,
   assumptions, _how to discharge_) to
   [PROOF-NARRATIVE.md](PROOF-NARRATIVE.md). The assumptions block is
   non-optional.
5. Each new assumption gets an entry in
   [ASSUMPTIONS.md](ASSUMPTIONS.md) with `A-QD-N.M` id and
   MATH/DESIGN/EMPIRICAL/CRYPTO classification.
6. Move to "Currently verified" section (to be created) when discharged.

## Dangerous patterns (BANNED)

CI rejects any PR introducing these:

| Pattern | Language | Meaning |
|---------|----------|---------|
| `believe_me` | Idris2 | Unsafe cast |
| `assert_total` | Idris2 | Skip totality check |
| `postulate` | Idris2 / Agda | Unproven axiom |
| `sorry` | Lean 4 | Incomplete proof |
| `Admitted` | Coq | Incomplete proof |
| `Obj.magic` | OCaml | Unsafe cast |
| `unsafeCoerce` | Haskell | Unsafe cast |
| `unsafe` (unaudited) | Rust / Zig | Unsafe block without safety comment |

Enforced by `panic-attack assail --proofs-only`.

## References

- Algorithms: [`server/quandle_semantic.jl`](server/quandle_semantic.jl)
- Tests: [`server/test_quandle_axioms.jl`](server/test_quandle_axioms.jl)
- Companion narratives:
  `hyperpolymath/krl/PROOF-NARRATIVE.md` — KRL surface
  `hyperpolymath/tangle/PROOF-NARRATIVE.md` — Tangle semantic core

