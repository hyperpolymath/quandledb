# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
# Owner: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# BR-5 — End-to-end fuzz harness.
#
# Random braid words → PlanarDiagram → quandle_descriptor → invariance
# checks across the transformations the audit narrative names.
#
# This is the BR-5 obligation from PROOF-NARRATIVE.md §3:
#   "Random KRL → parse → lower → store → query → assert equivalent.
#    Single harness covers half the proof obligations empirically."
#
# In QuandleDB's slice of that pipeline, we generate random braid
# words (already a structurally-valid KRL-equivalent input form),
# build their PD via `from_braid_word`, and assert:
#
#   1. Determinism: same input ⟹ same descriptor (QD-9 sibling).
#   2. Crossing-order invariance: shuffling pd.crossings preserves
#      the descriptor (QD-9 directly).
#   3. Round-trip: extract_presentation ∘ canonicalize ∘
#      canonical_presentation_blob is stable across repeated runs.
#   4. Algebraic well-formedness: every relation in the extracted
#      presentation has lhs, rhs, out ∈ 1:generator_count.
#
# Two reproducibility knobs:
#   * MersenneTwister seed `0xBEAD42` for the trial sequence.
#   * `BR5_TRIALS` ENV var for batch size (default 50). CI can crank
#     this to 5000 with `BR5_TRIALS=5000` for an overnight run.

using Test
using KnotTheory
using Random

include(joinpath(@__DIR__, "quandle_semantic.jl"))
using .QuandleSemantic

const BR5_TRIALS = parse(Int, get(ENV, "BR5_TRIALS", "50"))
const BR5_SEED = 0xBEAD42

# ---------------------------------------------------------------------------
# Braid-word generator.
#
# Produces "s1.s2.S1.s2.s1..." style strings on `nstrands` strands with
# `ncrossings` crossings. Each crossing picks a uniform generator and a
# uniform sign.
# ---------------------------------------------------------------------------

function _random_braid_word(rng::AbstractRNG, nstrands::Int, ncrossings::Int)::String
    @assert nstrands >= 2 "braid needs at least 2 strands"
    @assert ncrossings >= 1 "braid needs at least 1 crossing"
    parts = String[]
    for _ in 1:ncrossings
        gen = rand(rng, 1:(nstrands - 1))
        positive = rand(rng, Bool)
        push!(parts, (positive ? "s" : "S") * string(gen))
    end
    join(parts, ".")
end

# ---------------------------------------------------------------------------
# Property: presentation well-formedness on the fuzz corpus.
# Generalises Q-PresentationWF beyond the 3 standard test knots.
# Cross-references QD-1 in PROOF-NARRATIVE.md (still NOT STARTED in formal
# form; this fuzz pass discharges the structural component empirically).
# ---------------------------------------------------------------------------

@testset "BR-5: presentation well-formedness on random braid words" begin
    rng = MersenneTwister(BR5_SEED)
    for trial in 1:BR5_TRIALS
        nstrands = rand(rng, 3:4)
        ncrossings = rand(rng, 4:12)
        word = _random_braid_word(rng, nstrands, ncrossings)
        pd = from_braid_word(word).pd

        pres = extract_presentation(pd)
        n = pres.generator_count

        @test n >= 0
        @test length(pres.relations) == length(pd.crossings)

        for rel in pres.relations
            @test 1 <= rel.lhs <= n
            @test 1 <= rel.rhs <= n
            @test 1 <= rel.out <= n
            @test rel.is_inverse isa Bool
        end
    end
end

# ---------------------------------------------------------------------------
# Property: descriptor determinism on the fuzz corpus.
# Same input ⟹ same output. This is Q-DescriptorDet generalised to
# random PDs.
# ---------------------------------------------------------------------------

@testset "BR-5: descriptor determinism on random braid words" begin
    rng = MersenneTwister(BR5_SEED)
    for trial in 1:BR5_TRIALS
        nstrands = rand(rng, 3:4)
        ncrossings = rand(rng, 4:12)
        word = _random_braid_word(rng, nstrands, ncrossings)
        pd = from_braid_word(word).pd

        d1 = quandle_descriptor(pd)
        d2 = quandle_descriptor(pd)

        @test d1.presentation_hash == d2.presentation_hash
        @test d1.colouring_count_3 == d2.colouring_count_3
        @test d1.colouring_count_5 == d2.colouring_count_5
        @test d1.quandle_key == d2.quandle_key
    end
end

# ---------------------------------------------------------------------------
# Property: crossing-order invariance on the fuzz corpus.
# QD-9 (already tested on the 3 standard knots in §9); this generalises
# to random PDs at fuzz scale.
# ---------------------------------------------------------------------------

@testset "BR-5: crossing-order invariance on random braid words" begin
    rng = MersenneTwister(BR5_SEED + 1)
    # KNOWN-BROKEN (upstream): the polynomial segments of quandle_key
    # (alexander/conway/homfly from KnotTheory.jl) are crossing-order
    # sensitive on some diagrams — the polynomials are not normalised to a
    # canonical unit (±t^k), so 25/200 seeded trials disagree. The layers
    # this repo owns (presentation_hash, colouring counts) are asserted
    # hard below; the key mismatch count is tracked and marked broken so
    # the marker must be removed once KnotTheory.jl normalises.
    quandle_key_mismatches = 0
    for trial in 1:BR5_TRIALS
        nstrands = rand(rng, 3:4)
        ncrossings = rand(rng, 4:12)
        word = _random_braid_word(rng, nstrands, ncrossings)
        pd = from_braid_word(word).pd

        base = quandle_descriptor(pd)
        shuffled_pd = PlanarDiagram(shuffle(rng, copy(pd.crossings)), pd.components)
        shuffled = quandle_descriptor(shuffled_pd)

        @test shuffled.presentation_hash == base.presentation_hash
        @test shuffled.colouring_count_3 == base.colouring_count_3
        @test shuffled.colouring_count_5 == base.colouring_count_5
        if shuffled.quandle_key != base.quandle_key
            quandle_key_mismatches += 1
        end
    end
    quandle_key_mismatches > 0 &&
        @info "BR-5 quandle_key order-sensitivity (known-broken)" quandle_key_mismatches BR5_TRIALS
    @test_broken quandle_key_mismatches == 0
end

# ---------------------------------------------------------------------------
# Property: canonical-blob round-trip stability.
# Two runs of `canonical_presentation_blob` on the same presentation
# produce byte-equal output.
# ---------------------------------------------------------------------------

@testset "BR-5: canonical-blob round-trip stability" begin
    rng = MersenneTwister(BR5_SEED + 2)
    for trial in 1:BR5_TRIALS
        nstrands = rand(rng, 3:4)
        ncrossings = rand(rng, 4:12)
        word = _random_braid_word(rng, nstrands, ncrossings)
        pd = from_braid_word(word).pd

        pres = extract_presentation(pd)
        blob1 = canonical_presentation_blob(pres)
        blob2 = canonical_presentation_blob(pres)
        @test blob1 == blob2

        canon = canonicalize_presentation(pres)
        canon_blob1 = canonical_presentation_blob(canon)
        canon_blob2 = canonical_presentation_blob(canon)
        @test canon_blob1 == canon_blob2

        # Canonicalising a canon presentation should not change its blob.
        @test blob1 == canon_blob1
    end
end

println("br5-fuzz-tests-ok (trials=$(BR5_TRIALS), seed=0x$(string(BR5_SEED; base = 16)))")
