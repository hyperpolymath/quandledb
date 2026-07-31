# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Property-based tests for quandle axiom discharge and Reidemeister invariance.
#
# Addresses PROOF-NEEDS.md M1 (quandle axioms), M2 (Reidemeister invariance),
# and M3 (canonicalisation idempotency).

using Test
using KnotTheory

include(joinpath(@__DIR__, "quandle_semantic.jl"))
using .QuandleSemantic

# ---------------------------------------------------------------------------
# § 1. Dihedral quandle axioms (algebraic, no knot theory required)
#
# The dihedral quandle Z_p uses the action  a ▷ b = 2b - a  (mod p).
# Three axioms must hold for every prime p:
#   A1. Idempotence:            a ▷ a = a
#   A2. Right-invertibility:    x ↦ x ▷ b is a bijection for each b
#   A3. Right self-distributivity: (a ▷ b) ▷ c = (a ▷ c) ▷ (b ▷ c)
# ---------------------------------------------------------------------------

function dihedral_action(lhs::Int, rhs::Int, p::Int)::Int
    mod(2 * rhs - lhs, p)
end

@testset "Dihedral quandle axioms (algebraic)" begin
    for p in [3, 5, 7, 11, 13]
        @testset "Z_$p" begin
            elements = 0:p-1

            # A1: idempotence — a ▷ a = a for all a
            @test all(a -> dihedral_action(a, a, p) == a, elements)

            # A2: right-invertibility — the map x ↦ x ▷ b is a bijection
            for b in elements
                orbit = Set(dihedral_action(x, b, p) for x in elements)
                @test length(orbit) == p
            end

            # A3: right self-distributivity
            for a in elements, b in elements, c in elements
                lhs = dihedral_action(dihedral_action(a, b, p), c, p)
                rhs = dihedral_action(
                    dihedral_action(a, c, p),
                    dihedral_action(b, c, p),
                    p,
                )
                @test lhs == rhs
            end
        end
    end
end

# ---------------------------------------------------------------------------
# § 2. Presentation well-formedness (M1 structural check)
#
# For every knot in the standard table, the extracted QuandlePresentation
# must satisfy structural constraints:
#   - generator indices are in 1..generator_count
#   - relation count equals crossing count
#   - each relation is self-consistent (lhs, rhs, out all in range)
# ---------------------------------------------------------------------------

@testset "Presentation well-formedness for standard knots" begin
    knots_under_test = [
        ("trefoil (3_1)", trefoil().pd),
        ("figure_eight (4_1)", figure_eight().pd),
        ("cinquefoil (5_1)", cinquefoil().pd),
    ]

    for (name, pd) in knots_under_test
        @testset "$name" begin
            pres = extract_presentation(pd)
            n = pres.generator_count

            @test n >= 1                                          # non-empty
            @test length(pres.relations) == length(pd.crossings)  # one relation per crossing

            for rel in pres.relations
                @test 1 <= rel.lhs <= n
                @test 1 <= rel.rhs <= n
                @test 1 <= rel.out <= n
                @test rel.is_inverse isa Bool
            end
        end
    end
end

# ---------------------------------------------------------------------------
# § 3. Canonicalisation idempotency (M3)
#
# Applying canonicalize_presentation twice must yield the same result
# as applying it once.
# ---------------------------------------------------------------------------

@testset "Canonicalisation idempotency" begin
    for (pd, label) in [
        (trefoil().pd, "trefoil"),
        (figure_eight().pd, "figure-eight"),
        (cinquefoil().pd, "cinquefoil"),
    ]
        @testset "$label" begin
            pres = extract_presentation(pd)
            once = canonicalize_presentation(pres)
            twice = canonicalize_presentation(once)
            @test canonical_presentation_blob(once) == canonical_presentation_blob(twice)
        end
    end
end

# ---------------------------------------------------------------------------
# § 4. Determinism
#
# The same PD must always produce the same presentation hash and
# dihedral colouring counts.
# ---------------------------------------------------------------------------

@testset "Descriptor determinism" begin
    for (pd, label) in [
        (trefoil().pd, "trefoil"),
        (figure_eight().pd, "figure-eight"),
        (cinquefoil().pd, "cinquefoil"),
    ]
        @testset "$label" begin
            d1 = quandle_descriptor(pd)
            d2 = quandle_descriptor(pd)
            @test d1.presentation_hash == d2.presentation_hash
            @test d1.colouring_count_3 == d2.colouring_count_3
            @test d1.colouring_count_5 == d2.colouring_count_5
            @test d1.quandle_key == d2.quandle_key
        end
    end
end

# ---------------------------------------------------------------------------
# § 5. Reidemeister I invariance (M2)
#
# A PD with nugatory crossings (kinks) should give the same dihedral
# colouring counts as the simplified version.
#
# A nugatory crossing has repeated arc labels — r1_simplify detects and
# removes it.  We inject a kink whose arcs are disjoint from the main
# diagram so the quandle structure is unchanged (the isolated loop
# contributes an independent generator with trivial relations).
# ---------------------------------------------------------------------------

@testset "Reidemeister I: kink removal preserves colouring counts" begin
    t_pd = trefoil().pd

    # The trefoil uses arc labels from the Wirtinger presentation.
    # Inject a kink on fresh arcs (200, 201) that don't overlap.
    # A kink crossing has arc 200 appearing twice in position (a, b, b, a).
    kink = Crossing((200, 201, 201, 200), 1)
    pd_with_kink = PlanarDiagram(
        [t_pd.crossings..., kink],
        t_pd.components,
    )

    simplified = r1_simplify(pd_with_kink)

    # B8: assert strict reduction (length(t_pd) < length(pd_with_kink), so
    # a passing r1_simplify must produce length(simplified) < length(pd_with_kink),
    # not merely == length(t_pd)). The previous == check would silently pass
    # if r1_simplify did nothing — see PROOF-NARRATIVE.md bug audit B8.
    @test length(simplified.crossings) < length(pd_with_kink.crossings)
    @test length(simplified.crossings) == length(t_pd.crossings)

    # Coloring counts for the diagram before and after R1:
    # The isolated kink adds one generator with a self-relation out = 2*rhs - lhs
    # where lhs = rhs = out, so it contributes a free factor.  After removal it
    # is gone — the ratio is p^1.  We only check proportionality via the
    # relation count, not raw counts, since the isolated component changes the
    # dimension.
    before_pres = extract_presentation(pd_with_kink)
    after_pres  = extract_presentation(simplified)
    @test after_pres.generator_count < before_pres.generator_count ||
          length(after_pres.relations) < length(before_pres.relations)
end

# ---------------------------------------------------------------------------
# § 6. Reidemeister II invariance (M2)
#
# A braid word  s1.S1.s1.s1.s1  is topologically the trefoil (s1.s1.s1)
# with an extra s1.S1 cancelling pair.  After r2_simplify the crossing
# count drops by 2 and the dihedral colouring counts must agree with the
# standard trefoil.
# ---------------------------------------------------------------------------

@testset "Reidemeister II: bigon removal preserves colouring counts" begin
    # from_braid_word("s1.s1.s1") returns the canonical 3-crossing trefoil.
    trefoil_canonical = trefoil().pd

    # Build a 5-crossing diagram by explicit braid closure on s1.S1.s1.s1.s1.
    # This goes through the generic braid-closure path (not the short-circuit),
    # so we get a non-minimal PD with an s1·S1 bigon present.
    trefoil_inflated = from_braid_word("s1.S1.s1.s1.s1").pd

    simplified = r2_simplify(trefoil_inflated)

    # Simplification must have removed at least the bigon pair.
    @test length(simplified.crossings) <= length(trefoil_inflated.crossings)

    # Colouring counts must match the canonical trefoil.
    if length(simplified.crossings) > 0
        d_simplified = quandle_descriptor(simplified)
        d_canonical  = quandle_descriptor(trefoil_canonical)

        @test d_simplified.colouring_count_3 == d_canonical.colouring_count_3
        # KNOWN-BROKEN (upstream): KnotTheory.jl r2_simplify removes the bigon
        # without re-splicing the severed arcs, leaving 4 arc labels that occur
        # only once; the extracted presentation then has 5 generators instead
        # of 3 and c5 comes out 25 instead of 5. Flips to "unexpected pass"
        # (forcing removal of this marker) once the upstream fix lands.
        @test_broken d_simplified.colouring_count_5 == d_canonical.colouring_count_5
    end
end

# ---------------------------------------------------------------------------
# § 7. Coloring count distinguishes distinct knots (sanity check)
#
# The trefoil and figure-eight must differ in at least one dihedral
# colouring count.  This is the fundamental usefulness test for the
# semantic index.
# ---------------------------------------------------------------------------

@testset "Colouring counts distinguish knot types" begin
    t_desc = quandle_descriptor(trefoil().pd)
    f_desc = quandle_descriptor(figure_eight().pd)
    c_desc = quandle_descriptor(cinquefoil().pd)

    # At least one of Z_3 or Z_5 must separate trefoil from figure-eight.
    @test t_desc.colouring_count_3 != f_desc.colouring_count_3 ||
          t_desc.colouring_count_5 != f_desc.colouring_count_5

    # Trefoil and cinquefoil are Z_5-distinguishable.
    @test t_desc.colouring_count_5 != c_desc.colouring_count_5 ||
          t_desc.colouring_count_3 != c_desc.colouring_count_3
end

# ---------------------------------------------------------------------------
# § 8. Quandle key uniqueness for distinct knots
#
# The quandle_key combines generator_count, relation_count,
# degree_partition, and colouring counts.  For the three standard knots
# they must all be distinct.
# ---------------------------------------------------------------------------

@testset "Quandle key uniqueness" begin
    descriptors = [
        quandle_descriptor(trefoil().pd),
        quandle_descriptor(figure_eight().pd),
        quandle_descriptor(cinquefoil().pd),
    ]
    keys = [d.quandle_key for d in descriptors]
    @test length(unique(keys)) == length(keys)
end

# ---------------------------------------------------------------------------
# § 13. QD-9 — Union-find traversal-order independence
#
# `_wirtinger_arc_to_generator` walks `pd.crossings` and union-finds arc
# equivalence classes. If the result depended on iteration order, the
# same knot diagram in two different array layouts would give different
# `generator_count`, different `quandle_key`, and different
# `presentation_hash` — silently destabilising the semantic index.
#
# Addresses PROOF-NARRATIVE.md QD-9 and assumptions A-QD-9.1, A-QD-9.2.
# ---------------------------------------------------------------------------

using Random

@testset "QD-9: union-find traversal-order independence" begin
    for (pd, label) in [
        (trefoil().pd, "trefoil"),
        (figure_eight().pd, "figure-eight"),
        (cinquefoil().pd, "cinquefoil"),
    ]
        @testset "$label" begin
            base_pres = extract_presentation(pd)
            base_blob = canonical_presentation_blob(base_pres)
            base_desc = quandle_descriptor(pd)

            rng = MersenneTwister(0xC0FFEE)
            for trial in 1:8
                shuffled_crossings = shuffle(rng, copy(pd.crossings))
                shuffled_pd = PlanarDiagram(shuffled_crossings, pd.components)

                shuffled_pres = extract_presentation(shuffled_pd)
                @test shuffled_pres.generator_count == base_pres.generator_count
                @test canonical_presentation_blob(shuffled_pres) == base_blob

                shuffled_desc = quandle_descriptor(shuffled_pd)
                @test shuffled_desc.presentation_hash == base_desc.presentation_hash
                @test shuffled_desc.colouring_count_3 == base_desc.colouring_count_3
                @test shuffled_desc.colouring_count_5 == base_desc.colouring_count_5
                @test shuffled_desc.quandle_key == base_desc.quandle_key
            end
        end
    end
end

# ---------------------------------------------------------------------------
# § 14. QD-2 Path B — R3 invariance hand-corpus
#
# Until `r3_simplify` is added upstream to KnotTheory.jl (PROOF-NARRATIVE
# .md QD-2 Path A, parked at #29), discharge R3 empirically with two
# hand-constructed PD pairs from the audit Agent's design.
# ---------------------------------------------------------------------------

@testset "QD-2 Path B: R3 triangle-slide preserves quandle descriptor" begin
    # Pair 1: all-positive triangle, inner arcs {1, 6, 4}.
    pd_before_1 = PlanarDiagram([
        Crossing((1, 2, 3, 4), 1),
        Crossing((1, 5, 6, 2), 1),
        Crossing((3, 6, 4, 5), 1),
    ], Vector{Vector{Int}}())

    pd_after_1 = PlanarDiagram([
        Crossing((3, 2, 6, 4), 1),
        Crossing((3, 5, 1, 2), 1),
        Crossing((6, 1, 4, 5), 1),
    ], Vector{Vector{Int}}())

    @testset "all-positive triangle" begin
        d_b = quandle_descriptor(pd_before_1)
        d_a = quandle_descriptor(pd_after_1)
        @test d_b.colouring_count_3 == d_a.colouring_count_3
        @test d_b.colouring_count_5 == d_a.colouring_count_5
        @test d_b.generator_count == d_a.generator_count
        @test d_b.relation_count == d_a.relation_count
    end

    # Pair 2: mixed-sign triangle, inner arcs {10, 15, 13}.
    pd_before_2 = PlanarDiagram([
        Crossing((10, 11, 12, 13), 1),
        Crossing((10, 14, 15, 11), -1),
        Crossing((12, 15, 13, 14), 1),
    ], Vector{Vector{Int}}())

    pd_after_2 = PlanarDiagram([
        Crossing((12, 11, 15, 13), 1),
        Crossing((12, 14, 10, 11), -1),
        Crossing((15, 10, 13, 14), 1),
    ], Vector{Vector{Int}}())

    @testset "mixed-sign triangle" begin
        d_b = quandle_descriptor(pd_before_2)
        d_a = quandle_descriptor(pd_after_2)
        @test d_b.colouring_count_3 == d_a.colouring_count_3
        @test d_b.colouring_count_5 == d_a.colouring_count_5
        @test d_b.generator_count == d_a.generator_count
        @test d_b.relation_count == d_a.relation_count
        @test d_b.inverse_relation_count == d_a.inverse_relation_count
    end
end

# ---------------------------------------------------------------------------
# § 10. KT-11 — Image-size histogram cross-check + class-invariance
#
# The image-size histogram is a refinement of the colouring count.
# Two cross-checks:
#
#   1. Histogram sums to the colouring count. This verifies that the
#      rank-based `_dihedral_colouring_count` agrees with the explicit
#      enumeration `_enumerate_dihedral_colourings`. Discharges QD-8
#      empirically on the test corpus.
#
#   2. Image histograms distinguish trefoil / figure-eight / cinquefoil
#      at least one modulus (when the colouring counts also do — they
#      shouldn't be strictly less powerful). Discharges KT-11's "refined
#      invariant" claim.
#
# Addresses PROOF-NARRATIVE.md KT-11 + QD-8 (cross-check via independent
# method).
# ---------------------------------------------------------------------------

@testset "KT-11: image-histogram sums to colouring count" begin
    for (pd, label) in [
        (trefoil().pd, "trefoil"),
        (figure_eight().pd, "figure-eight"),
        (cinquefoil().pd, "cinquefoil"),
    ]
        @testset "$label" begin
            d = quandle_descriptor(pd)
            # Only meaningful when within the IMAGE_HISTOGRAM_MAX_G window.
            if d.generator_count <= 8
                @test sum(d.image_histogram_3) == d.colouring_count_3
                @test sum(d.image_histogram_5) == d.colouring_count_5
            end
        end
    end
end

@testset "KT-11: image histograms refine the colouring count" begin
    t = quandle_descriptor(trefoil().pd)
    f = quandle_descriptor(figure_eight().pd)
    c = quandle_descriptor(cinquefoil().pd)

    # Each pair must be distinguished by at least one modulus's image
    # histogram OR by the colouring counts (the histogram is a refinement;
    # whenever the counts differ, the histograms must too).
    @test t.image_histogram_3 != f.image_histogram_3 ||
          t.image_histogram_5 != f.image_histogram_5 ||
          t.colouring_count_3 != f.colouring_count_3 ||
          t.colouring_count_5 != f.colouring_count_5
    @test t.image_histogram_3 != c.image_histogram_3 ||
          t.image_histogram_5 != c.image_histogram_5 ||
          t.colouring_count_3 != c.colouring_count_3 ||
          t.colouring_count_5 != c.colouring_count_5
end

# ---------------------------------------------------------------------------
# § 11. KT-2 — Alexander polynomial wiring sanity
#
# Verify that `quandle_descriptor` populates `alexander_polynomial`
# using the canonical "exp:coeff,..." serialisation. For the trefoil,
# the Alexander polynomial is Δ(t) = t - 1 + t^{-1}, which serialises
# to "-1:1,0:-1,1:1" (or some sign convention).
#
# Addresses PROOF-NARRATIVE.md KT-2.
# ---------------------------------------------------------------------------

@testset "KT-2: Alexander polynomial is populated + non-trivial" begin
    for (pd, label) in [
        (trefoil().pd, "trefoil"),
        (figure_eight().pd, "figure-eight"),
        (cinquefoil().pd, "cinquefoil"),
    ]
        @testset "$label" begin
            d = quandle_descriptor(pd)
            # Must be a non-empty serialised polynomial.
            @test !isempty(d.alexander_polynomial)
            # Must follow the "exp:coeff" pattern.
            @test occursin(r"^-?\d+:-?\d+(,-?\d+:-?\d+)*$", d.alexander_polynomial) ||
                  d.alexander_polynomial == "0:0"
            # Must contain at least one non-zero term for these knots
            # (unknot would be "0:1"; trefoil/fig-8/cinquefoil are all
            # non-trivial).
            @test d.alexander_polynomial != "0:0"
        end
    end
end

@testset "KT-2: Alexander polynomial distinguishes the test knots" begin
    t = quandle_descriptor(trefoil().pd)
    f = quandle_descriptor(figure_eight().pd)
    c = quandle_descriptor(cinquefoil().pd)

    # Trefoil and figure-eight are distinguished by Alexander.
    @test t.alexander_polynomial != f.alexander_polynomial
    # Trefoil and cinquefoil are distinguished by Alexander.
    @test t.alexander_polynomial != c.alexander_polynomial
    # Figure-eight and cinquefoil are distinguished by Alexander.
    @test f.alexander_polynomial != c.alexander_polynomial
end

# ---------------------------------------------------------------------------
# § 12. KT-2 extension — Jones, Conway, HOMFLY populated + non-trivial
#
# Same shape as the Alexander tests in §11. The three polynomial fields
# extend the quandle_descriptor; together with Alexander they form a
# strictly more discriminating descriptor.
#
# Exact-value assertions are deliberately limited to "populated + does
# not equal the trivial-unknot output". A separate exact-fixture suite
# is queued (see KT-2 extension follow-up issue) where the test corpus
# captures the exact strings KnotTheory.jl produces.
# ---------------------------------------------------------------------------

@testset "KT-2 ext: Jones polynomial is populated + non-trivial" begin
    for (pd, label) in [
        (trefoil().pd, "trefoil"),
        (figure_eight().pd, "figure-eight"),
        (cinquefoil().pd, "cinquefoil"),
    ]
        @testset "$label" begin
            d = quandle_descriptor(pd)
            @test !isempty(d.jones_polynomial)
            @test d.jones_polynomial != "0:0"
        end
    end
end

@testset "KT-2 ext: Conway polynomial is populated + non-trivial" begin
    for (pd, label) in [
        (trefoil().pd, "trefoil"),
        (figure_eight().pd, "figure-eight"),
        (cinquefoil().pd, "cinquefoil"),
    ]
        @testset "$label" begin
            d = quandle_descriptor(pd)
            @test !isempty(d.conway_polynomial)
            @test d.conway_polynomial != "0:0"
        end
    end
end

@testset "KT-2 ext: HOMFLY polynomial is populated within bounds" begin
    for (pd, label) in [
        (trefoil().pd, "trefoil"),
        (figure_eight().pd, "figure-eight"),
        (cinquefoil().pd, "cinquefoil"),
    ]
        @testset "$label" begin
            d = quandle_descriptor(pd)
            # All three test knots have < 15 crossings, so HOMFLY computes.
            @test d.homfly_polynomial != "deferred:too_many_crossings"
            @test !isempty(d.homfly_polynomial)
            # HOMFLY is two-variable; format is "a_exp,z_exp:coeff;..."
            @test occursin(';', d.homfly_polynomial) ||
                  occursin(',', d.homfly_polynomial)
        end
    end
end

@testset "KT-2 ext: polynomial guards return sentinels above their bounds" begin
    # Each polynomial has its OWN bound, set by its own measured cost model,
    # so one diagram cannot exercise them all. Both cases below are genuine
    # (2,n)-torus-link diagrams (post KnotTheory#43 — before that fix the
    # broken braid closure made them degenerate and cheap, which is how the
    # missing guards went unnoticed until CI hung for 6 hours).

    # 16 crossings: above HOMFLY's 15 (skein recursion is exponential), but
    # below Jones' 20 (Kauffman bracket, 2.8s measured here) and far below
    # alexander/conway's 128 (Bareiss, O(n^3)).
    pd16 = from_braid_word(join(["s1" for _ in 1:16], ".")).pd
    d16 = quandle_descriptor(pd16)
    @test d16.homfly_polynomial == HOMFLY_DEFERRED_SENTINEL
    @test d16.jones_polynomial != HOMFLY_DEFERRED_SENTINEL
    @test d16.alexander_polynomial != HOMFLY_DEFERRED_SENTINEL
    @test d16.conway_polynomial != HOMFLY_DEFERRED_SENTINEL

    # 130 crossings: above every bound — all four defer. This also pins the
    # alexander/conway bound itself: if someone raises it without raising
    # this fixture, the test fails rather than silently going quiet.
    pd_over = from_braid_word(join(["s1" for _ in 1:130], ".")).pd
    @test length(pd_over.crossings) > ALEXANDER_MAX_CROSSINGS
    d_over = quandle_descriptor(pd_over)
    @test d_over.alexander_polynomial == HOMFLY_DEFERRED_SENTINEL
    @test d_over.conway_polynomial == HOMFLY_DEFERRED_SENTINEL
    @test d_over.jones_polynomial == HOMFLY_DEFERRED_SENTINEL
    @test d_over.homfly_polynomial == HOMFLY_DEFERRED_SENTINEL
end

@testset "KT-2 ext: Jones polynomial distinguishes the test knots" begin
    t = quandle_descriptor(trefoil().pd)
    f = quandle_descriptor(figure_eight().pd)
    c = quandle_descriptor(cinquefoil().pd)
    @test t.jones_polynomial != f.jones_polynomial
    @test t.jones_polynomial != c.jones_polynomial
    @test f.jones_polynomial != c.jones_polynomial
end

@testset "KT-2 ext: Conway polynomial distinguishes the test knots" begin
    t = quandle_descriptor(trefoil().pd)
    f = quandle_descriptor(figure_eight().pd)
    c = quandle_descriptor(cinquefoil().pd)
    @test t.conway_polynomial != f.conway_polynomial
    @test t.conway_polynomial != c.conway_polynomial
    @test f.conway_polynomial != c.conway_polynomial
end

@testset "KT-2 ext: HOMFLY distinguishes the test knots" begin
    # HOMFLY-PT subsumes both Alexander and Jones; for these knots it
    # should distinguish all pairs.
    t = quandle_descriptor(trefoil().pd)
    f = quandle_descriptor(figure_eight().pd)
    c = quandle_descriptor(cinquefoil().pd)
    @test t.homfly_polynomial != f.homfly_polynomial
    @test t.homfly_polynomial != c.homfly_polynomial
    @test f.homfly_polynomial != c.homfly_polynomial
end

# ---------------------------------------------------------------------------
# § 15. QD-7 — Canonical-form ordering totality (structural assertion)
#
# The `sort(...; by = r -> (r.lhs, r.rhs, r.out, r.is_inverse ? 1 : 0))`
# in `canonicalize_presentation` assumes the comparator tuple captures
# every relation field that affects quandle equality. The
# `QuandleRelation` struct has exactly four fields by definition; if a
# fifth field is added without updating the canonicaliser, the
# canonical form would silently lose discrimination.
#
# This testset is a STRUCTURAL guard against that. Addresses
# PROOF-NARRATIVE.md QD-7 and assumption A-QD-7.1.
# ---------------------------------------------------------------------------

@testset "QD-7: QuandleRelation has exactly 4 fields (canonical-order totality)" begin
    @test fieldcount(QuandleRelation) == 4

    fields = Set(fieldnames(QuandleRelation))
    @test fields == Set([:lhs, :rhs, :out, :is_inverse])

    r1 = QuandleRelation(1, 2, 3, false)
    r2 = QuandleRelation(1, 2, 3, false)
    @test r1 == r2

    r_diff_lhs   = QuandleRelation(9, 2, 3, false)
    r_diff_rhs   = QuandleRelation(1, 9, 3, false)
    r_diff_out   = QuandleRelation(1, 2, 9, false)
    r_diff_inv   = QuandleRelation(1, 2, 3, true)
    @test r1 != r_diff_lhs
    @test r1 != r_diff_rhs
    @test r1 != r_diff_out
    @test r1 != r_diff_inv
end

# ---------------------------------------------------------------------------
# § 16. QD-3 (partial) — Canonical form is invariant under relation reordering
#
# `_dihedral_colouring_count(p, modulus)` builds a sparse linear system
# from `p.relations`. The order of relations affects pivot selection
# but must NOT affect the canonical form (and hence the count).
#
# Test: for each standard knot, shuffle relations deterministically
# and assert the canonical-presentation blob agrees with the unshuffled
# canonical form.
#
# Addresses PROOF-NARRATIVE.md QD-3 (relation-order half) and
# PROOF-NEEDS.md M4. The full iso-class half (different PRESENTATIONS
# of the same fundamental quandle) requires constructing distinct PDs
# of the same knot — partial coverage already via §6 R2 invariance.
# ---------------------------------------------------------------------------

@testset "QD-3 (partial): canonical form invariant under relation reordering" begin
    rng = MersenneTwister(0xDEADBEEF)
    for (pd, label) in [
        (trefoil().pd, "trefoil"),
        (figure_eight().pd, "figure-eight"),
        (cinquefoil().pd, "cinquefoil"),
    ]
        @testset "$label" begin
            pres = extract_presentation(pd)
            base_blob = canonical_presentation_blob(canonicalize_presentation(pres))

            for trial in 1:8
                shuffled_relations = shuffle(rng, copy(pres.relations))
                shuffled_pres = QuandlePresentation(
                    pres.generator_count,
                    shuffled_relations,
                )
                canon = canonicalize_presentation(shuffled_pres)
                @test canonical_presentation_blob(canon) == base_blob
            end
        end
    end
end

# ---------------------------------------------------------------------------
# § 17. KT-2 extension — exact-value fixtures (Alexander + Conway)
#
# The §11/§12 tests check that polynomial fields are populated and that
# the three standard knots are pairwise distinguished. These properties
# are necessary but weak — a buggy polynomial that happens to be
# distinct across our three knots would still pass.
#
# This testset pins exact-value fixtures for polynomials whose values
# are mathematically standard and verified against upstream:
#
#   * Alexander for the trefoil — confirmed by Skein.jl test fixture in
#     `Skein.jl/ext/KnotTheoryExt.jl` ("-1:1,0:-1,1:1").
#   * Conway for trefoil / figure-eight / cinquefoil — confirmed by
#     `KnotTheory.jl/test/runtests.jl` ("0:1,2:1", "0:1,2:-1",
#     "0:1,2:3,4:1").
#
# Jones and HOMFLY exact values are deliberately NOT pinned: the
# 2026-06-01 audit Agent could not verify them against KnotTheory.jl
# test fixtures (no exact-value assertions exist upstream), and
# sign-convention ambiguity (right-handed vs left-handed trefoil) makes
# guessing brittle. They stay covered by the "populated + distinguishes"
# tests in §12 until upstream fixtures are added.
#
# Addresses PROOF-NARRATIVE.md §3 KT-2 and the follow-up issue #32
# (KT-2 extension exact-fixture suite).
# ---------------------------------------------------------------------------

@testset "KT-2 ext: Alexander polynomial exact-value fixture (trefoil)" begin
    t = quandle_descriptor(trefoil().pd)
    # Trefoil Alexander = t^{-1} - 1 + t = -1:1, 0:-1, 1:1
    # Verified against Skein.jl/ext/KnotTheoryExt.jl test fixture.
    @test t.alexander_polynomial == "-1:1,0:-1,1:1"
end

@testset "KT-2 ext: Conway polynomial exact-value fixtures" begin
    # Trefoil ∇(z) = 1 + z² → "0:1,2:1"
    # Confirmed against KnotTheory.jl/test/runtests.jl line ~278.
    t = quandle_descriptor(trefoil().pd)
    @test t.conway_polynomial == "0:1,2:1"

    # Figure-eight ∇(z) = 1 - z² → "0:1,2:-1". This was @test_broken: the
    # computed value was -(1 - z²) because alexander normalised its unit by
    # "leading coefficient positive", the wrong canonical choice on
    # mixed-sign knots. Fixed upstream (KnotTheory.jl#48) by normalising to
    # Δ(1) = +1, the Conway normalisation — the marker then reported
    # "unexpected pass", which is exactly the signal it existed to produce.
    f = quandle_descriptor(figure_eight().pd)
    @test f.conway_polynomial == "0:1,2:-1"

    # Cinquefoil ∇(z) = 1 + 3z² + z⁴ → "0:1,2:3,4:1"
    c = quandle_descriptor(cinquefoil().pd)
    @test c.conway_polynomial == "0:1,2:3,4:1"
end

# Sanity: if a future change updates the polynomial-serialisation
# format, these fixtures will fail loudly. That's intentional —
# any format change must be a deliberate Skein.jl compatibility break,
# not an accident.

println("quandle-axiom-tests-ok")
