# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
using Test
include("../KRL.jl")
using .KRL

# Deliberately colliding index buckets, with no mathematical witnesses.
struct CandidateData <: KRL.DataProvider end
struct CandidateIndex <: KRL.SemProvider end
KRL.fetch_all(::CandidateData; kwargs...) = [
    Dict{String,Any}("name" => "a", "crossing_number" => 3),
    Dict{String,Any}("name" => "collision", "crossing_number" => 4)]
KRL.equiv_buckets(::CandidateIndex, ::String) =
    (strong=["a", "collision"], weak=["a", "collision"])

function run_resolution(source)
    KRL.eval_krl_program(parse_krl(source),
        KRL.make_eval_context(CandidateData(), CandidateIndex()))
end

@testset "Resolution evidence boundary" begin
    r = run_resolution("from knots | find_equivalent \"a\"")
    @test length(r.rows) == 2
    @test all(row -> row["_equiv_confidence"] == "ConfHeuristic", r.rows)
    @test any(w -> occursin("candidate", w), r.warnings)
    for level in ["exact", "sufficient", "necessary"]
        @test_throws KRL.KRLEvalError run_resolution(
            "from knots | find_equivalent \"a\" confidence >= " * level)
    end
    # A later stage must not reintroduce candidates filtered out upstream.
    filtered = run_resolution(
        "from knots | filter crossing_number > 100 | find_equivalent \"a\"")
    @test isempty(filtered.rows)
    @test_throws KRL.KRLParseError parse_krl("from knots | filter")
end
