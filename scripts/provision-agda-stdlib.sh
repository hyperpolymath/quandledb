#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# provision-agda-stdlib.sh [DIR]
#
# The one shared, pinned way an estate repo gets the Agda standard library.
# Repos copy this file byte-identically from rsr-template-repo; do not fork it.
#
# Why it exists: each Agda repo wrote its own stdlib setup, and Ubuntu's apt
# agda-stdlib package now ships standard-library.agda-lib with `include: src`.
# Workflows that overwrote that file with `include: .` made Agda search a
# directory holding no modules.  This script never reads or writes apt's copy
# and never touches ~/.agda: it clones a tag, verifies the commit, and writes
# a private libraries file.
#
# Environment (all optional):
#   AGDA_STDLIB_VERSION  tag to clone            (default v2.3)
#   AGDA_STDLIB_COMMIT   full commit SHA the tag must resolve to
#                        (default 8326c7475af1fa456ca04a0203c168d5d7ff842b)
#   AGDA_STDLIB_REPO     clone URL (default https://github.com/agda/agda-stdlib)
#   AGDA_MIN_VERSION     minimum Agda compiler; fails below it (default 2.7.0,
#                        the oldest compiler agda-stdlib v2.3 documents as tested)
#   RUNNER_TEMP          base for the default directory
#   GITHUB_ENV           when set, AGDA_LIBRARIES=<path> is appended to it
#
# A repo that must stay on another release overrides VERSION and COMMIT together;
# changing one without the other fails the commit check, loudly.
#
# Output: the libraries-file path on stdout (export it as AGDA_LIBRARIES).
# Exit: 0 ok; 1 provisioning or pin failure; 2 misuse.

set -euo pipefail

VERSION="${AGDA_STDLIB_VERSION:-v2.3}"
COMMIT="${AGDA_STDLIB_COMMIT:-8326c7475af1fa456ca04a0203c168d5d7ff842b}"
REPO="${AGDA_STDLIB_REPO:-https://github.com/agda/agda-stdlib}"
AGDA_MIN="${AGDA_MIN_VERSION:-2.7.0}"

if [ "$#" -gt 1 ]; then
  echo "usage: $(basename "$0") [DIR]" >&2
  exit 2
fi
if [[ ! "$COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "FAIL: AGDA_STDLIB_COMMIT must be a full 40-character lowercase SHA, got '$COMMIT'" >&2
  exit 2
fi

if ! command -v agda >/dev/null 2>&1; then
  echo "FAIL: 'agda' not found on PATH; install the compiler first." >&2
  exit 1
fi
AGDA_VERSION_LINE="$(agda --version | head -1)"
echo "$AGDA_VERSION_LINE" >&2
AGDA_ACTUAL="$(grep -oE '[0-9]+(\.[0-9]+)+' <<<"$AGDA_VERSION_LINE" | head -1 || true)"
if [ -z "$AGDA_ACTUAL" ]; then
  echo "FAIL: cannot read an Agda version from '$AGDA_VERSION_LINE'." >&2
  exit 1
fi
if [ "$(printf '%s\n%s\n' "$AGDA_MIN" "$AGDA_ACTUAL" | sort -V | head -1)" != "$AGDA_MIN" ]; then
  {
    echo "FAIL: Agda $AGDA_ACTUAL is older than $AGDA_MIN, the minimum for agda-stdlib $VERSION."
    echo "      (Ubuntu apt's agda-bin can be 2.6.3.)  Install a newer compiler, or set"
    echo "      AGDA_MIN_VERSION together with AGDA_STDLIB_VERSION/COMMIT if you know better."
  } >&2
  exit 1
fi

if [ "$#" -eq 1 ]; then
  DIR="$1"
else
  DIR="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/agda-stdlib.XXXXXX")/agda-stdlib"
fi

if [ -e "$DIR" ] && [ -n "$(ls -A "$DIR" 2>/dev/null)" ]; then
  echo "FAIL: $DIR exists and is not empty; refusing to reuse an unverified tree." >&2
  exit 1
fi
mkdir -p "$(dirname "$DIR")"
DIR="$(cd "$(dirname "$DIR")" && pwd)/$(basename "$DIR")"

git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$VERSION" "$REPO" "$DIR" >&2
ACTUAL="$(git -C "$DIR" rev-parse HEAD)"
if [ "$ACTUAL" != "$COMMIT" ]; then
  {
    echo "FAIL: agda-stdlib $VERSION resolved to $ACTUAL, expected $COMMIT."
    echo "      The tag moved or the pin is wrong; not using this tree."
  } >&2
  rm -rf "$DIR"
  exit 1
fi
if [ ! -f "$DIR/src/Data/Nat.agda" ]; then
  echo "FAIL: $DIR/src/Data/Nat.agda missing; the clone is not a stdlib source tree." >&2
  exit 1
fi

LIBS="$DIR/libraries"
printf '%s\n' "$DIR/standard-library.agda-lib" >"$LIBS"
# Written by us, with `include: src`, so no other file can redirect the search.
printf 'name: standard-library\ninclude: src\n' >"$DIR/standard-library.agda-lib"

echo "agda-stdlib $VERSION ($ACTUAL) provisioned at $DIR" >&2
if [ -n "${GITHUB_ENV:-}" ]; then
  printf 'AGDA_LIBRARIES=%s\n' "$LIBS" >>"$GITHUB_ENV"
fi
echo "export AGDA_LIBRARIES=$LIBS" >&2
printf '%s\n' "$LIBS"
