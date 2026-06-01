# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# DB-6 Phase A: tests for the EXPLAIN QUERY PLAN utility.
#
# Self-contained: provisions an in-memory SQLite DB that mirrors the relevant
# fragment of the quandle_semantic_index schema plus the DB-3 PR #42 indexes
# (idx_semantic_writhe, idx_semantic_genus, idx_semantic_gencount), so the
# tests run without the production seed DB.
#
# Run standalone:
#   julia --project=server -e 'include("server/test_query_explain.jl"); run_db6_tests()'

using SQLite
using DBInterface
using Test

include("query_explain.jl")

"""
    _provision_inmem_db() :: SQLite.DB

Provision an in-memory SQLite DB with the minimal `quandle_semantic_index`
schema fragment exercised by DB-6 Phase A. Mirrors the create-and-index
statements in `serve.jl` under `SEMANTIC_INDEX_STATEMENTS`.
"""
function _provision_inmem_db()
    db = SQLite.DB(":memory:")
    DBInterface.execute(db, """
        CREATE TABLE quandle_semantic_index (
            knot_name TEXT PRIMARY KEY,
            crossing_number INTEGER,
            writhe INTEGER,
            genus INTEGER,
            quandle_generator_count INTEGER,
            determinant INTEGER,
            signature INTEGER,
            colouring_count_3 INTEGER,
            descriptor_hash TEXT,
            quandle_key TEXT
        )
    """)
    DBInterface.execute(db, "CREATE INDEX idx_semantic_writhe ON quandle_semantic_index(writhe)")
    DBInterface.execute(db, "CREATE INDEX idx_semantic_genus ON quandle_semantic_index(genus)")
    DBInterface.execute(db, "CREATE INDEX idx_semantic_gencount ON quandle_semantic_index(quandle_generator_count)")
    DBInterface.execute(db, "CREATE INDEX idx_semantic_crossing_number ON quandle_semantic_index(crossing_number)")
    for (name, cn, w, g) in [
        ("3_1", 3, 3, 1),
        ("4_1", 4, 0, 1),
        ("5_1", 5, 5, 2),
    ]
        DBInterface.execute(db,
            "INSERT INTO quandle_semantic_index (knot_name, crossing_number, writhe, genus) VALUES (?, ?, ?, ?)",
            (name, cn, w, g))
    end
    return db
end

"""
    run_db6_tests()

Execute the Phase A assertions for `explain_query_plan`, `is_select_only`,
and `plan_summary`. Uses an in-memory DB so no seed file is required.
"""
function run_db6_tests()
    db = _provision_inmem_db()
    try
        @testset "DB-6 Phase A: explain_query_plan" begin
            @testset "trivial plan is non-empty" begin
                plan = explain_query_plan(db, "SELECT 1")
                @test !isempty(plan)
                @test all(r -> haskey(r, "detail"), plan)
            end

            @testset "single-table SELECT mentions table" begin
                plan = explain_query_plan(db, "SELECT knot_name FROM quandle_semantic_index LIMIT 1")
                summary = plan_summary(plan)
                @test occursin("quandle_semantic_index", summary)
            end

            @testset "filtered SELECT emits structured planner output" begin
                plan = explain_query_plan(
                    db,
                    "SELECT * FROM quandle_semantic_index WHERE crossing_number = ?",
                    Any[3],
                )
                summary = plan_summary(plan)
                @test occursin(r"SEARCH|SCAN"i, summary)
            end

            @testset "writhe filter hits DB-3 PR #42 index idx_semantic_writhe" begin
                plan = explain_query_plan(
                    db,
                    "SELECT * FROM quandle_semantic_index WHERE writhe = ?",
                    Any[0],
                )
                summary = plan_summary(plan)
                @test occursin("idx_semantic_writhe", summary)
            end

            @testset "is_select_only honours read-only discipline (QD-12)" begin
                @test is_select_only("SELECT * FROM x")
                @test is_select_only("  select 1")
                @test is_select_only("WITH cte AS (SELECT 1) SELECT * FROM cte")
                @test !is_select_only("INSERT INTO x VALUES (1)")
                @test !is_select_only("UPDATE x SET y = 1")
                @test !is_select_only("DELETE FROM x")
                @test !is_select_only("PRAGMA journal_mode = WAL")
                @test !is_select_only("DROP TABLE x")
            end

            @testset "plan_summary joins detail with ` | `" begin
                @test plan_summary([Dict{String, Any}("detail" => "A"),
                                    Dict{String, Any}("detail" => "B")]) == "A | B"
                @test plan_summary(Dict{String, Any}[]) == ""
            end
        end
    finally
        DBInterface.close!(db)
    end
end

# When run directly via `julia server/test_query_explain.jl`, execute tests.
if abspath(PROGRAM_FILE) == @__FILE__
    run_db6_tests()
end
