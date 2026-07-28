# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# DB-6 Phase A — `explain from … | …` produces a structured plan.

using Test
include(joinpath(@__DIR__, "..", "KRL.jl"))
using .KRL: parse_krl, explain_plan, plan_is_costed, SELECTIVITY_STUB,
            KRLExplainStmt, KRLQueryStmt, KRLParseError

@testset "DB-6: explain is a distinct statement, not a query" begin
    prog = parse_krl("explain from knots | filter crossing < 8")
    @test length(prog.statements) == 1
    @test prog.statements[1] isa KRLExplainStmt
    # A plain query must NOT become an explain — the two are distinguishable
    # so no existing consumer can be handed a plan where it expected rows.
    @test parse_krl("from knots | filter crossing < 8").statements[1] isa KRLQueryStmt
end

@testset "DB-6: explain requires a query after it" begin
    @test_throws KRLParseError parse_krl("explain")
    @test_throws KRLParseError parse_krl("explain take 5")
end

@testset "DB-6: plan shape matches the acceptance criteria" begin
    prog = parse_krl(
        "explain from knots | filter colouring_count_3 = 9 and crossing < 8 | take 5")
    plan = explain_plan(prog.statements[1].query)

    @test plan[1]["op"] == "scan"
    @test plan[1]["table"] == "knots"

    # A conjunction becomes SEPARATE filter operations — that is what makes a
    # future cost-based reorder (DB-7) meaningful.
    @test plan[2]["op"] == "filter"
    @test plan[2]["column"] == "colouring_count_3"
    @test plan[2]["comparator"] == "="
    @test plan[2]["value"] == 9
    @test plan[2]["indexed"] == true         # carries a secondary index

    @test plan[3]["column"] == "crossing"
    @test plan[3]["comparator"] == "<"
    @test plan[3]["value"] == 8
    @test plan[3]["indexed"] == false        # does not

    @test plan[4]["op"] == "take"
    @test plan[4]["n"] == 5
end

@testset "DB-6: selectivity is honestly labelled a stub until DB-3" begin
    plan = explain_plan(
        parse_krl("explain from knots | filter crossing < 8").statements[1].query)
    filt = plan[2]
    @test filt["selectivity_estimate"] == SELECTIVITY_STUB
    @test filt["selectivity_source"] == "stub"
    # The guard that stops DB-7 optimising against invented numbers. This must
    # stay false until real histograms land (#33) — if it ever returns true
    # while estimates are stubs, the cost model is lying.
    @test plan_is_costed(plan) == false
end

@testset "DB-6: a predicate the plan cannot describe is not mis-described" begin
    # Column-to-column comparison is not a simple `column <cmp> literal`, so
    # it must be reported opaquely rather than given a fabricated column.
    plan = explain_plan(
        parse_krl("explain from knots | filter crossing < genus").statements[1].query)
    @test plan[2]["op"] == "filter"
    @test plan[2]["predicate"] == "<expression>"
    @test !haskey(plan[2], "column")
    @test plan[2]["indexed"] == false
end

println("krl-explain-tests-ok")
