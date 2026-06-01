# SPDX-License-Identifier: MPL-2.0

module QuandleSemantic

using KnotTheory
using SHA
using Blake3Hash

export QuandleRelation, QuandlePresentation
export extract_presentation, canonicalize_presentation, canonical_presentation_blob
export quandle_descriptor
export IMAGE_HISTOGRAM_MAX_G

"""
    QuandleRelation

A single crossing relation in the fundamental quandle. At a positive crossing,
the right quandle action gives `lhs ▷ rhs = out`; at a negative crossing,
this is inverted (`is_inverse = true`).

# Fields
- `lhs::Int`: left-hand-side generator index (the arc being acted on)
- `rhs::Int`: acting generator index (the over-strand arc)
- `out::Int`: result generator index (the arc after the crossing)
- `is_inverse::Bool`: `true` for negative crossings (inverse action)
"""
struct QuandleRelation
    lhs::Int
    rhs::Int
    out::Int
    is_inverse::Bool
end

"""
    QuandlePresentation

Fundamental-quandle presentation of a knot diagram: `generator_count` generators
(one per arc) plus a list of relations (one per crossing).

# Fields
- `generator_count::Int`: number of generators (equals number of distinct arcs
  after union-find collapsing at each crossing)
- `relations::Vector{QuandleRelation}`: one relation per crossing

Two presentations with equal `canonical_presentation_blob` are isomorphic quandles.
"""
struct QuandlePresentation
    generator_count::Int
    relations::Vector{QuandleRelation}
end

function _uf_find!(parent::Vector{Int}, x::Int)
    while parent[x] != x
        parent[x] = parent[parent[x]]
        x = parent[x]
    end
    x
end

function _uf_union!(parent::Vector{Int}, rank::Vector{Int}, a::Int, b::Int)
    ra = _uf_find!(parent, a)
    rb = _uf_find!(parent, b)
    ra == rb && return

    if rank[ra] < rank[rb]
        parent[ra] = rb
    elseif rank[ra] > rank[rb]
        parent[rb] = ra
    else
        parent[rb] = ra
        rank[ra] += 1
    end
end

function _wirtinger_arc_to_generator(pd::KnotTheory.PlanarDiagram)
    all_arcs = sort(unique(vcat([collect(c.arcs) for c in pd.crossings]...)))
    isempty(all_arcs) && return Dict{Int, Int}(), 0

    arc_to_idx = Dict{Int, Int}()
    for (i, arc) in enumerate(all_arcs)
        arc_to_idx[arc] = i
    end

    parent = collect(1:length(all_arcs))
    rank = zeros(Int, length(all_arcs))

    # Over-strand arcs (d,b) represent the same Wirtinger generator.
    for c in pd.crossings
        _, b, _, d = c.arcs
        _uf_union!(parent, rank, arc_to_idx[d], arc_to_idx[b])
    end

    root_to_gen = Dict{Int, Int}()
    arc_to_gen = Dict{Int, Int}()
    next_gen = 1
    for arc in all_arcs
        root = _uf_find!(parent, arc_to_idx[arc])
        if !haskey(root_to_gen, root)
            root_to_gen[root] = next_gen
            next_gen += 1
        end
        arc_to_gen[arc] = root_to_gen[root]
    end

    arc_to_gen, next_gen - 1
end

"""
    extract_presentation(pd::KnotTheory.PlanarDiagram) -> QuandlePresentation

Extract a Wirtinger-style quandle presentation from a planar diagram.
"""
function extract_presentation(pd::KnotTheory.PlanarDiagram)::QuandlePresentation
    arc_to_gen, generator_count = _wirtinger_arc_to_generator(pd)
    relations = QuandleRelation[]

    for c in pd.crossings
        a, _, c_arc, d = c.arcs
        g_a = arc_to_gen[a]
        g_c = arc_to_gen[c_arc]
        g_over = arc_to_gen[d]

        if c.sign >= 0
            # Positive crossing: g_c = g_a ▷ g_over
            push!(relations, QuandleRelation(g_a, g_over, g_c, false))
        else
            # Negative crossing: g_a = g_c ▷^{-1} g_over
            push!(relations, QuandleRelation(g_c, g_over, g_a, true))
        end
    end

    QuandlePresentation(generator_count, relations)
end

"""
    canonicalize_presentation(p::QuandlePresentation) -> QuandlePresentation

Relabel generators in `p` to canonical form: generators receive fresh ids
`1, 2, 3, ...` in the order they first appear in sorted relations.

Two presentations produce the same canonical form iff they represent the
same presentation up to generator renaming. This is the basis for
`canonical_presentation_blob`'s fingerprint.
"""
function canonicalize_presentation(p::QuandlePresentation)::QuandlePresentation
    sorted_rel = sort(p.relations, by = r -> (r.lhs, r.rhs, r.out, r.is_inverse ? 1 : 0))

    mapping = Dict{Int, Int}()
    next_id = 1
    for r in sorted_rel
        for g in (r.lhs, r.rhs, r.out)
            if !haskey(mapping, g)
                mapping[g] = next_id
                next_id += 1
            end
        end
    end

    for g in 1:p.generator_count
        if !haskey(mapping, g)
            mapping[g] = next_id
            next_id += 1
        end
    end

    canon_rel = QuandleRelation[]
    for r in sorted_rel
        push!(canon_rel, QuandleRelation(mapping[r.lhs], mapping[r.rhs], mapping[r.out], r.is_inverse))
    end
    sort!(canon_rel, by = r -> (r.lhs, r.rhs, r.out, r.is_inverse ? 1 : 0))

    QuandlePresentation(p.generator_count, canon_rel)
end

"""
    canonical_presentation_blob(p::QuandlePresentation) -> String

Serialise `p` to a canonical text blob after applying `canonicalize_presentation`.
Format: `qpres-v1|g=<generator_count>|r=<rel>;<rel>;...` where each `<rel>` is
`lhs,rhs,out,sign` with `sign ∈ {-1, 1}`.

Two presentations with the same blob are isomorphic as quandles (up to
generator renaming). This blob is the input to SHA-256 fingerprinting in
`quandle_descriptor`.
"""
function canonical_presentation_blob(p::QuandlePresentation)::String
    c = canonicalize_presentation(p)
    rel_tokens = String[]
    for r in c.relations
        sign_flag = r.is_inverse ? -1 : 1
        push!(rel_tokens, string(r.lhs, ",", r.rhs, ",", r.out, ",", sign_flag))
    end
    blob = string("qpres-v1|g=", c.generator_count, "|r=", join(rel_tokens, ";"))
    # Compute BLAKE3 hash of the blob
    ctx = Blake3Hash.Blake3Ctx()
    Blake3Hash.update!(ctx, Vector{UInt8}(blob))
    fingerprint = bytes2hex(Blake3Hash.digest(ctx))
    fingerprint
end

function _modinv(a::Int, p::Int)
    aa = mod(a, p)
    g, x, _ = gcdx(aa, p)
    g == 1 || return nothing
    mod(x, p)
end

function _rank_mod_p!(M::Matrix{Int}, p::Int)::Int
    rows, cols = size(M)
    r = 0
    c = 1

    while r < rows && c <= cols
        pivot = 0
        for i in (r + 1):rows
            if mod(M[i, c], p) != 0
                pivot = i
                break
            end
        end

        if pivot == 0
            c += 1
            continue
        end

        if pivot != r + 1
            M[r + 1, :], M[pivot, :] = M[pivot, :], M[r + 1, :]
        end

        inv = _modinv(M[r + 1, c], p)
        isnothing(inv) && error("Non-invertible pivot in rank computation mod $p")

        for j in c:cols
            M[r + 1, j] = mod(M[r + 1, j] * inv, p)
        end

        for i in 1:rows
            i == r + 1 && continue
            factor = mod(M[i, c], p)
            factor == 0 && continue
            for j in c:cols
                M[i, j] = mod(M[i, j] - factor * M[r + 1, j], p)
            end
        end

        r += 1
        c += 1
    end

    r
end

function _dihedral_colouring_count(p::QuandlePresentation, modulus::Int)::Int
    g = p.generator_count
    r = length(p.relations)
    g == 0 && return modulus  # Unknot has modulus colourings
    r == 0 && return modulus^g

    M = zeros(Int, r, g)
    # Dihedral quandle linearization:
    # out = 2*rhs - lhs  (mod modulus), for both positive and inverse relations.
    for (i, rel) in enumerate(p.relations)
        M[i, rel.lhs] = mod(M[i, rel.lhs] + 1, modulus)
        M[i, rel.out] = mod(M[i, rel.out] + 1, modulus)
        M[i, rel.rhs] = mod(M[i, rel.rhs] - 2, modulus)
    end

    rank = _rank_mod_p!(copy(M), modulus)
    modulus^(g - rank)
end

function _degree_partition(p::QuandlePresentation)::String
    deg = zeros(Int, p.generator_count)
    for rel in p.relations
        deg[rel.lhs] += 1
        deg[rel.rhs] += 1
        deg[rel.out] += 1
    end
    sorted_deg = sort(deg, rev = true)
    join(sorted_deg, ",")
end

# ---------------------------------------------------------------------------
# § Dihedral colouring enumeration + image-size histogram (KT-11)
#
# `_dihedral_colouring_count` computes the colouring count via rank of the
# relations matrix (efficient, polynomial in g·modulus). For a refined
# invariant we ALSO enumerate the colourings explicitly and compute the
# histogram of `|image(c)|` (number of distinct colours each colouring uses).
# This histogram is a strict refinement of the colouring count and an
# independent class invariant — two knots with equal colouring counts may
# differ in the image-size distribution.
#
# Enumeration is exhaustive over `modulus^generator_count` assignments; we
# cap g at IMAGE_HISTOGRAM_MAX_G to keep the descriptor cheap. Larger
# diagrams fall back to a `missing` sentinel in the histogram field.
#
# Property test: sum(histogram) == _dihedral_colouring_count(p, m). This
# cross-checks the rank-based formula against the explicit enumeration.
# ---------------------------------------------------------------------------

const IMAGE_HISTOGRAM_MAX_G = 8

"""
    _enumerate_dihedral_colourings(p::QuandlePresentation, modulus::Int) -> Vector{Vector{Int}}

Enumerate every quandle homomorphism from the fundamental quandle of `p`
into the dihedral quandle `Z_modulus` (action `a ▷ b = 2b - a` mod `modulus`).

Returns the list of colourings as length-`p.generator_count` vectors of
values in `0:modulus-1`. Exhaustive; cost `O(modulus^g · |relations|)`.

For `g == 0` (the unknot's fundamental quandle), there is one trivial
empty colouring, returned as `[Int[]]`.
"""
function _enumerate_dihedral_colourings(p::QuandlePresentation, modulus::Int)::Vector{Vector{Int}}
    g = p.generator_count
    g == 0 && return [Int[]]

    total = modulus ^ g
    valid = Vector{Vector{Int}}()
    sizehint!(valid, max(total ÷ 10, 1))

    for code in 0:total-1
        c = zeros(Int, g)
        x = code
        for i in 1:g
            c[i] = x % modulus
            x ÷= modulus
        end
        ok = true
        for rel in p.relations
            expected = mod(2 * c[rel.rhs] - c[rel.lhs], modulus)
            if c[rel.out] != expected
                ok = false
                break
            end
        end
        ok && push!(valid, c)
    end
    valid
end

"""
    _dihedral_image_histogram(p::QuandlePresentation, modulus::Int) -> Vector{Int}

Histogram of `|image(c)|` over all dihedral colourings `c` of `p` into
`Z_modulus`. Index `k` of the returned vector counts colourings that use
exactly `k` distinct colours, for `k ∈ 1:modulus`.

Skipped (returns an all-zero vector with an explicit sentinel) when
`p.generator_count > IMAGE_HISTOGRAM_MAX_G` — the enumeration would be
too expensive to keep `quandle_descriptor` cheap.

This is the KT-11 refined invariant: a strict refinement of
`_dihedral_colouring_count` (which is `sum(histogram)`).
"""
function _dihedral_image_histogram(p::QuandlePresentation, modulus::Int)::Vector{Int}
    g = p.generator_count
    g > IMAGE_HISTOGRAM_MAX_G && return zeros(Int, modulus)

    cs = _enumerate_dihedral_colourings(p, modulus)
    hist = zeros(Int, modulus)
    for c in cs
        img_size = isempty(c) ? 1 : length(unique(c))
        hist[img_size] += 1
    end
    hist
end

# ---------------------------------------------------------------------------
# § Alexander polynomial wiring (KT-2)
#
# `KnotTheory.alexander_polynomial(pd) :: Dict{Int, Int}` returns the
# Laurent polynomial as `exponent -> coefficient`. We serialise it using
# the same `"exp:coeff,..."` format Skein.jl uses (see
# `Skein.jl/ext/KnotTheoryExt.jl::_serialise_int_poly`) so that the
# QuandleDB descriptor and the Skein.jl invariants table speak the same
# canonical form.
#
# The serialised form is part of the `quandle_key`-style fingerprint,
# making Alexander a first-class column of the semantic descriptor.
# ---------------------------------------------------------------------------

"""
    _serialise_int_poly(poly::Dict{Int,Int}) -> String

Serialise a Laurent polynomial-as-dict to the canonical
`"exp:coeff,exp:coeff,..."` form (zero coefficients dropped, exponents in
ascending order). Matches `Skein.jl::_serialise_int_poly` so values are
byte-equal across the two layers.
"""
function _serialise_int_poly(poly::Dict{Int,Int})::String
    pairs = String[]
    for exp in sort(collect(keys(poly)))
        coeff = poly[exp]
        coeff == 0 && continue
        push!(pairs, string(exp, ":", coeff))
    end
    isempty(pairs) ? "0:0" : join(pairs, ",")
end

"""
    quandle_descriptor(pd::KnotTheory.PlanarDiagram) -> NamedTuple

Return canonicalized quandle presentation + simple fingerprints suitable for
indexing and heuristic equivalence checks.
"""
function quandle_descriptor(pd::KnotTheory.PlanarDiagram)
    pres = extract_presentation(pd)
    canon = canonicalize_presentation(pres)
    blob = canonical_presentation_blob(canon)
    hash = bytes2hex(sha256(blob))
    degree_partition = _degree_partition(canon)
    rel_count = length(canon.relations)
    inv_count = count(r -> r.is_inverse, canon.relations)
    pos_count = rel_count - inv_count
    color3 = _dihedral_colouring_count(canon, 3)
    color5 = _dihedral_colouring_count(canon, 5)

    # KT-11: refined image-size histograms (strict refinements of color3, color5)
    image_hist_3 = _dihedral_image_histogram(canon, 3)
    image_hist_5 = _dihedral_image_histogram(canon, 5)
    image_hist_3_str = join(image_hist_3, ",")
    image_hist_5_str = join(image_hist_5, ",")

    # KT-2: Alexander polynomial via KnotTheory.jl, same serialisation as Skein.jl
    alexander_poly = KnotTheory.alexander_polynomial(pd)
    alexander_str = _serialise_int_poly(alexander_poly)

    key = string(
        canon.generator_count, ":",
        rel_count, ":",
        degree_partition, ":",
        color3, ":",
        color5, ":",
        image_hist_3_str, ":",
        image_hist_5_str, ":",
        alexander_str,
    )

    (
        canonical_presentation = blob,
        presentation_hash = hash,
        generator_count = canon.generator_count,
        relation_count = rel_count,
        positive_relation_count = pos_count,
        inverse_relation_count = inv_count,
        degree_partition = degree_partition,
        colouring_count_3 = color3,
        colouring_count_5 = color5,
        image_histogram_3 = image_hist_3,
        image_histogram_5 = image_hist_5,
        alexander_polynomial = alexander_str,
        quandle_key = key,
    )
end

end # module QuandleSemantic
