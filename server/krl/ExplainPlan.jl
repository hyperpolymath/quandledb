# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# DB-6 Phase A — structured query plan for `explain from … | …`.
#
# Produces the shape the DB-6 acceptance criteria specify: an ordered list of
# operations, each tagged with its kind and, for filters, the column, the
# comparator, the literal value, whether the column is indexed, and a
# selectivity estimate.
#
# HONESTY NOTE ON SELECTIVITY
# ---------------------------
# There are no column histograms yet — that is DB-3 (#33). The criteria
# explicitly permit a stub until DB-3 lands, so every estimate here is
# `SELECTIVITY_STUB` and is reported with `"selectivity_source" => "stub"`.
# Nothing downstream may treat these as measured: `plan_is_costed` returns
# false while any estimate is a stub, so a future DB-7 cost-based reorder
# cannot silently optimise against made-up numbers.

# Included directly into the `KRL` module namespace (as Ast.jl / Parser.jl /
# Evaluator.jl are) — not a submodule, so AST types resolve without imports.

"""Placeholder selectivity used until DB-3 (#33) provides real histograms."""
const SELECTIVITY_STUB = 0.5

"""
Columns carrying a secondary index today. Kept deliberately small and
explicit: an over-claiming list would make `indexed` a fake signal, which is
worse than reporting `false`. Extend as DB-3 lands real indexes.
"""
const INDEXED_COLUMNS = Set([
    "colouring_count_3",
    "colouring_count_5",
    "presentation_hash",
    "quandle_key",
])

_cmp_symbol(k::Symbol) = get(Dict(
    :eq => "=", :neq => "!=", :lt => "<", :lte => "<=",
    :gt => ">", :gte => ">=", :iso => "≅", :path => "~>", :in => "in",
), k, string(k))

_source_name(s::KRLSource) =
    s isa KRLSourceKnots      ? "knots" :
    s isa KRLSourceDiagrams   ? "diagrams" :
    s isa KRLSourceInvariants ? "invariants" :
    s isa KRLSourceNamed      ? s.name :
    s isa KRLSourceSubquery   ? "<subquery>" : "<unknown>"

# Pull (column, comparator, value) out of a comparison predicate when the
# shape is the simple `column <cmp> literal` the plan can describe. Anything
# else (nested boolean, function call, column-to-column) yields `nothing` and
# is reported as an opaque predicate rather than being mis-described.
_literal_value(e::KRLExpr) =
    e isa KRLInt      ? e.n :
    e isa KRLFloat    ? e.x :
    e isa KRLString   ? e.s :
    e isa KRLBool     ? e.b :
    e isa KRLKnotName ? e.name : nothing

function _simple_comparison(e::KRLExpr)
    e isa KRLCompare || return nothing
    e.left isa KRLVar || return nothing
    val = _literal_value(e.right)
    val === nothing && return nothing
    (e.left.name, _cmp_symbol(e.op), val)
end

# Split a conjunction into its conjuncts so `filter a = 1 and b < 2` plans as
# two filter operations, which is what makes a future reorder meaningful.
function _conjuncts(e::KRLExpr)
    e isa KRLAnd && return vcat(_conjuncts(e.left), _conjuncts(e.right))
    [e]
end

function _filter_ops(pred::KRLExpr)
    ops = Dict{String, Any}[]
    for c in _conjuncts(pred)
        simple = _simple_comparison(c)
        if simple === nothing
            push!(ops, Dict{String, Any}(
                "op" => "filter",
                "predicate" => "<expression>",
                "indexed" => false,
                "selectivity_estimate" => SELECTIVITY_STUB,
                "selectivity_source" => "stub",
            ))
        else
            col, cmp, val = simple
            push!(ops, Dict{String, Any}(
                "op" => "filter",
                "column" => col,
                "comparator" => cmp,
                "value" => val,
                "indexed" => col in INDEXED_COLUMNS,
                "selectivity_estimate" => SELECTIVITY_STUB,
                "selectivity_source" => "stub",
            ))
        end
    end
    ops
end

"""
    explain_plan(q::KRLQuery) -> Vector{Dict{String, Any}}

Ordered plan for `q`: a `scan` of the source followed by one entry per
pipeline stage, with conjoined filters split into separate `filter`
operations.

The order returned is **execution order as written** — no reordering is
performed. Cost-based reordering is DB-7 and requires real selectivity
(DB-3), which is why every estimate here is flagged `"stub"`.
"""
function explain_plan(q::KRLQuery)::Vector{Dict{String, Any}}
    plan = Dict{String, Any}[Dict{String, Any}(
        "op" => "scan",
        "table" => _source_name(q.source),
    )]
    for stage in q.stages
        if stage isa KRLFilterStage
            append!(plan, _filter_ops(stage.pred))
        elseif stage isa KRLSortStage
            push!(plan, Dict{String, Any}(
                "op" => "sort",
                "keys" => length(stage.items),
            ))
        elseif stage isa KRLTakeStage
            push!(plan, Dict{String, Any}("op" => "take", "n" => stage.n))
        elseif stage isa KRLSkipStage
            push!(plan, Dict{String, Any}("op" => "skip", "n" => stage.n))
        else
            push!(plan, Dict{String, Any}("op" => _stage_op_name(stage)))
        end
    end
    plan
end

_stage_op_name(s::KRLPipeStage) =
    s isa KRLReturnStage    ? "return" :
    s isa KRLGroupByStage   ? "group_by" :
    lowercase(replace(string(nameof(typeof(s))), "KRL" => "", "Stage" => ""))

"""
    plan_is_costed(plan) -> Bool

`true` only when every selectivity estimate in `plan` came from real
statistics. While DB-3 (#33) is outstanding this is always `false` — the
guard that stops DB-7 optimising against stub numbers.
"""
plan_is_costed(plan::Vector{Dict{String, Any}}) =
    !any(get(op, "selectivity_source", "stub") == "stub" for op in plan)
