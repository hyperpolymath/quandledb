#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# SessionStart hook — Claude Code on the web (cloud sessions) — QuandleDB.
#
# QuandleDB spans three toolchains the cloud image lacks:
#   * Julia        — the read-only HTTP server (server/, wraps Skein.jl)
#   * Elixir       — the BEAM layer (beam/, requires Elixir ~> 1.19 / OTP 26+)
#   * AffineScript — the TEA frontend (frontend/): a from-source OCaml/Dune
#                    compiler, invoked through Deno tasks
#
# The hook installs what it can and best-effort prefetches deps. Cloud-only;
# every step is guarded so nothing aborts session startup.
#
# ─ FEASIBILITY CAVEATS (read before relying on this) ──────────────────
# On the default "Trusted" network allowlist this hook usefully installs only
# **Deno**; the rest are blocked and skip cleanly. They complete under "Full"
# network access (or a Custom allowlist that adds the hosts below), and most
# belong in a cached **setup script** rather than a per-session hook:
#   * Julia     — julialang.org / juliaup hosts are not allowlisted (403). AND
#                 server/Project.toml [sources] path-deps point at sibling
#                 repos (../../../Skein.jl, KnotTheory.jl, AcceleratorGate.jl)
#                 that are absent from a standalone checkout, so
#                 `Pkg.instantiate` cannot resolve the server without them.
#   * Elixir    — beam/ wants `~> 1.19`, which needs Erlang/OTP 26+, newer than
#                 apt's OTP 25; and `mix deps.get` needs Hex (repo.hex.pm),
#                 also not allowlisted.
#   * AffineScript — a from-source OCaml build (~15 opam packages + dune). opam's
#                 registry (opam.ocaml.org) is not allowlisted, and a per-session
#                 source build is far too slow — strongly prefer a setup script.
#
# https://code.claude.com/docs/en/claude-code-on-the-web
set -uo pipefail

[ "${CLAUDE_CODE_REMOTE:-}" != "true" ] && exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$ROOT" || exit 0

LOG="${TMPDIR:-/tmp}/quandledb-session-start.log"
: >"$LOG"
log() { echo "[quandledb] $*"; }
run() { "$@" >>"$LOG" 2>&1; }            # best-effort; logged, never fatal
reachable() { curl -fsI -m 8 "$1" >/dev/null 2>&1; }  # registry/host gate

# ── Deno: the frontend task runner (GitHub release — works on Trusted) ─
install_deno() {
  command -v deno >/dev/null 2>&1 && return 0
  log "installing Deno (GitHub release)…"
  local z="${TMPDIR:-/tmp}/deno.zip"
  if run curl -fsSL -o "$z" \
    https://github.com/denoland/deno/releases/latest/download/deno-x86_64-unknown-linux-gnu.zip; then
    run unzip -o "$z" -d /usr/local/bin && run chmod +x /usr/local/bin/deno
  fi
}

# ── Erlang + Elixir (best-effort; OTP 25 floor, see caveats) ───────────
install_elixir() {
  command -v mix >/dev/null 2>&1 && return 0
  # beam/ wants `~> 1.19` (OTP 26+). apt ships OTP 25, so this installs the
  # newest Elixir that runs on OTP 25 as a floor; full 1.19 support needs a
  # newer Erlang (source build / setup script).
  log "installing Erlang (apt, OTP 25) + Elixir 1.18 (GitHub, best-effort)…"
  run apt-get update -qq
  run apt-get install -y -qq erlang-nox
  local z="${TMPDIR:-/tmp}/elixir.zip"
  if run curl -fsSL -o "$z" \
    https://github.com/elixir-lang/elixir/releases/download/v1.18.4/elixir-otp-25.zip; then
    run mkdir -p /usr/local/elixir && run unzip -o "$z" -d /usr/local/elixir
    for b in elixir elixirc mix iex; do
      [ -f "/usr/local/elixir/bin/$b" ] && run ln -sf "/usr/local/elixir/bin/$b" /usr/local/bin/
    done
  fi
}

# ── Julia (only if its host is reachable — Full network) ───────────────
install_julia() {
  command -v julia >/dev/null 2>&1 && return 0
  if reachable https://install.julialang.org; then
    log "installing Julia (juliaup)…"
    run bash -c 'curl -fsSL https://install.julialang.org | sh -s -- --yes --default-channel release'
    [ -x "$HOME/.juliaup/bin/julia" ] && run ln -sf "$HOME/.juliaup/bin/julia" /usr/local/bin/julia
  else
    log "skipping Julia — download host blocked on this network (needs Full access)."
  fi
}

# ── AffineScript: from-source OCaml/Dune build (only if opam reachable) ─
install_affinescript() {
  command -v affinescript >/dev/null 2>&1 && return 0
  if reachable https://opam.ocaml.org; then
    log "building AffineScript from source (OCaml/Dune — heavy; prefer a setup script)…"
    run git clone --depth 1 https://github.com/hyperpolymath/affinescript /opt/affinescript
    run apt-get install -y -qq opam
    run opam init --disable-sandboxing -y -q
    run bash -c 'eval "$(opam env)"; opam install -y -q dune sedlex menhir ppx_deriving ppx_sexp_conv sexplib0 fmt cmdliner yojson js_of_ocaml js_of_ocaml-ppx js_of_ocaml-compiler'
    run bash -c 'eval "$(opam env)"; cd /opt/affinescript && dune build'
    [ -f /opt/affinescript/_build/default/bin/main.exe ] &&
      run ln -sf /opt/affinescript/_build/default/bin/main.exe /usr/local/bin/affinescript
  else
    log "skipping AffineScript — opam registry blocked on this network (see header caveats)."
  fi
}

install_deno
install_elixir
install_julia
install_affinescript

# ── Best-effort dependency prefetch (each guarded by its own blockers) ─
if command -v julia >/dev/null 2>&1 && [ -f server/Project.toml ]; then
  log "instantiating Julia server env (best-effort; needs the sibling repos)…"
  (cd server && run julia --project=. -e 'using Pkg; Pkg.instantiate()')
fi

if command -v mix >/dev/null 2>&1 && [ -f beam/mix.exs ]; then
  log "fetching Elixir deps (best-effort; needs Hex registry access)…"
  (
    cd beam || exit 0
    run mix local.hex --force
    run mix local.rebar --force
    run mix deps.get
  )
fi

if command -v deno >/dev/null 2>&1 && command -v affinescript >/dev/null 2>&1 && [ -f frontend/deno.json ]; then
  log "type-checking the AffineScript frontend (best-effort)…"
  (cd frontend && run deno task check)
fi

log "ready (full log: $LOG)."
exit 0
