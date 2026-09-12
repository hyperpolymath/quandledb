# CLAUDE.md - QuandleDB

## Project Overview

QuandleDB is a knot database application using the independent Skein.jl storage
library and KnotTheory.jl mathematical toolkit. Its semantic core consumes
`KnotTheory.PlanarDiagram`, extracts presentations and computes fingerprints and
colouring counts. Index matches are candidates, not checked isotopy witnesses.
KRL is its resolution language; `server/krl/` implements a retrieval/candidate
fragment, separately scoped from the four-operation construction/resolution draft.
Tangle is a separate Turing-complete language and is not a KRL compilation target.

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

The following files in `.machine_readable/descriptiles/` contain structured project metadata:
- `STATE.a2ml` - Current project state and progress
- `META.a2ml` - Architecture decisions
- `ECOSYSTEM.a2ml` - Relationship to Skein.jl and the KRL stack
