# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# DB-6 Phase A: utility for emitting SQLite `EXPLAIN QUERY PLAN` output.
#
# Read-only by construction. Does NOT wire into any public endpoint; that is
# Phase B (blocked on Skein.jl public-API addition; see docs/db-6-explain-strategy.md).
#
# Usage:
#   plan = explain_query_plan(sdb.conn, "SELECT * FROM quandle_semantic_index WHERE writhe = ?", Any[0])
#   each row is Dict("id"=>Int, "parent"=>Int, "notused"=>Int, "detail"=>String)

using SQLite
using DBInterface

"""
    explain_query_plan(conn::SQLite.DB, sql::AbstractString, args::AbstractVector=Any[])
        :: Vector{Dict{String, Any}}

Run SQLite `EXPLAIN QUERY PLAN` on `sql` with bind args `args` and return one
`Dict` per planner row. Each Dict has keys `"id"`, `"parent"`, `"notused"`,
`"detail"`.

The wrapper does not mutate the database. SQLite's `EXPLAIN QUERY PLAN` is a
metadata-only `SELECT` against the planner — even when `sql` contains a
mutation, only the plan is produced (the mutation does not execute). We still
defensively reject obvious DDL/DML prefixes via [`is_select_only`](@ref) so
callers wiring this into a public endpoint cannot be tricked into surfacing
mutation plans.
"""
function explain_query_plan(conn::SQLite.DB, sql::AbstractString,
                            args::AbstractVector = Any[])::Vector{Dict{String, Any}}
    plan = Dict{String, Any}[]
    explain_sql = "EXPLAIN QUERY PLAN " * sql
    for row in DBInterface.execute(conn, explain_sql, args)
        push!(plan, Dict{String, Any}(
            "id"      => row.id,
            "parent"  => row.parent,
            "notused" => row.notused,
            "detail"  => row.detail,
        ))
    end
    return plan
end

"""
    is_select_only(sql::AbstractString) :: Bool

Return `true` iff the leading non-whitespace token of `sql` is `SELECT` or
`WITH` (case-insensitive). Used by Phase B's public endpoint to refuse
mutation prefixes before they reach `explain_query_plan`.
"""
function is_select_only(sql::AbstractString) :: Bool
    return occursin(r"^\s*(SELECT|WITH)\b"i, sql)
end

"""
    plan_summary(plan::Vector{Dict{String, Any}}) :: String

One-line human summary of a plan: each row's `"detail"` joined with ` | `.
For per-request log lines (Phase B).
"""
function plan_summary(plan::Vector{Dict{String, Any}}) :: String
    return join(map(r -> string(r["detail"]), plan), " | ")
end
