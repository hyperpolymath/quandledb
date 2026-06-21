#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# SessionStart hook — Claude Code on the web (cloud sessions) — QuandleDB.
#
# QuandleDB spans three toolchains the cloud image lacks:
#   * Julia        — the read-only HTTP server (server/, wraps Skein.jl)
#   * Elixir       — the BEAM layer (beam/, requires Elixir ~> 1.19 / OTP 26+)
#   * AffineScript — the TEA frontend (frontend/): an OCaml/Dune compiler,
#                    invoked through Deno tasks (we install its prebuilt binary)
#
# The hook installs what it can and best-effort prefetches deps. Cloud-only;
# every step is guarded so nothing aborts session startup.
#
# ─ FEASIBILITY CAVEATS (read before relying on this) ──────────────────
# On the default "Trusted" network allowlist this hook installs **Deno** and a
# prebuilt **AffineScript** binary (both from GitHub releases). **Julia** and
# **Elixir** stay blocked and skip cleanly; they complete under "Full" network
# access (or a Custom allowlist that adds the hosts below), and the heavier
# installs belong in a cached **setup script** rather than a per-session hook:
#   * Julia     — julialang.org / juliaup hosts are not allowlisted (403). AND
#                 server/Project.toml [sources] path-deps point at sibling
#                 repos (../../../Skein.jl, KnotTheory.jl, AcceleratorGate.jl)
#                 that are absent from a standalone checkout, so
#                 `Pkg.instantiate` cannot resolve the server without them.
#   * Elixir    — beam/ wants `~> 1.19`, which needs Erlang/OTP 26+, newer than
#                 apt's OTP 25; and `mix deps.get` needs Hex (repo.hex.pm),
#                 also not allowlisted.
#   * AffineScript — installed from a prebuilt release binary (v0.1.1, checksum-
#                 pinned), so no opam/OCaml build is needed. Caveat: the latest
#                 tag v0.2.0 is source-only, so we pin v0.1.1 (the newest release
#                 that attaches a runnable binary); v0.2.0-only syntax would need
#                 a source build (opam + dune) or upstream-attached binaries.
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

# ── AffineScript: prebuilt binary (GitHub release — works on Trusted) ──
# The compiler is OCaml/Dune, but release v0.1.1 attaches prebuilt binaries,
# so we fetch the Linux x86-64 one and verify it against the upstream SHA256
# rather than running a ~15-package opam source build. The latest tag v0.2.0
# is source-only, hence the v0.1.1 pin (see header caveats).
AFFINE_VER="v0.1.1"
AFFINE_SHA256="b8f2cab7380306ca07b9599d7fe2470328236e7287a51c78c3bbb5e973fef5dc"
install_affinescript() {
  command -v affinescript >/dev/null 2>&1 && return 0
  log "installing AffineScript ${AFFINE_VER} (prebuilt Linux binary, checksum-pinned)…"
  local bin="${TMPDIR:-/tmp}/affinescript-linux-x64"
  run curl -fsSL -o "$bin" \
    "https://github.com/hyperpolymath/affinescript/releases/download/${AFFINE_VER}/affinescript-linux-x64" || return 0
  if echo "${AFFINE_SHA256}  ${bin}" | sha256sum -c - >>"$LOG" 2>&1; then
    run install -m 0755 "$bin" /usr/local/bin/affinescript
  else
    log "AffineScript checksum mismatch — refusing to install (see log)."
    run rm -f "$bin"
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
