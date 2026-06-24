# CLAUDE.md - QuandleDB

## Project Overview

QuandleDB is a knot-theory database application — the invariant/equivalence +
semantic-identity layer of the KRL stack, wrapping the Skein.jl engine. It extracts
quandle presentations from TangleIR, computes fingerprints/colouring invariants, and
is the canonical persistence + invariant/equivalence face (where presentations,
invariants, fingerprints, equivalence classes, witnesses, and results live). KRL =
Knot Resolution Language, a resolution DSL — *not merely* a query language; QuandleDB
hosts the server-side KRL parser (`server/krl/`). The four KRL ops run against the
QuandleDB+Skein substrate; no single op maps 1:1 to a component.

- **Server**: Julia HTTP server (`server/serve.jl`) using HTTP.jl + JSON3.jl
- **Frontend**: AffineScript TEA interface (`frontend/src/ui/tea/quandle_gui.affine`)
- **Engine**: Skein.jl (path dependency at `../../Skein.jl`)

## Build Commands

```bash
# Frontend (AffineScript — affinescript#56 DOM/fetch bindings pending)
cd frontend && deno task check   # affinescript check
cd frontend && deno task build   # affinescript build

# Server
cd server && julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=server server/serve.jl data/knots.db --port 8080 --static public/
```

## API Endpoints

- `GET /api/knots` — list with filters (crossing_number, writhe, genus, name, limit, offset)
- `GET /api/knots/:name` — single knot detail
- `GET /api/statistics` — database stats and distributions

## Key Conventions

- Server is read-only (database mutations via Skein.jl REPL)
- Frontend is an AffineScript TEA program (Model/Msg/init/update/view/subs), mirroring nextgen-databases/nqc/src/ui/tea/nqc_gui.affine
- JSON field names use snake_case (matching Skein.jl schema)
- AffineScript files use SPDX headers (`SPDX-License-Identifier: CC-BY-SA-4.0`)
- SCM files in `.machine_readable/` ONLY

## Machine-Readable Artefacts

The following files in `.machine_readable/6a2/` contain structured project metadata:
- `STATE.a2ml` - Current project state and progress
- `META.a2ml` - Architecture decisions
- `ECOSYSTEM.a2ml` - Relationship to Skein.jl and the KRL stack
