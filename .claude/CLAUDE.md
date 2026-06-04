# CLAUDE.md - QuandleDB

## Project Overview

QuandleDB is a knot-theory database application wrapping Skein.jl.

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
- AffineScript files use SPDX headers (`SPDX-License-Identifier: MPL-2.0`)
- SCM files in `.machine_readable/` ONLY

## Machine-Readable Artefacts

The following files in `.machine_readable/` contain structured project metadata:
- `STATE.scm` - Current project state and progress
- `META.scm` - Architecture decisions
- `ECOSYSTEM.scm` - Relationship to Skein.jl and ecosystem
