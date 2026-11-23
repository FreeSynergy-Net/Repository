#!/usr/bin/env bash
# Gate before anything is built or signed: the project key never signs unreviewed code. Only `main` of the source repo, or a full commit SHA that is
# an ANCESTOR of origin/main there (main is the reviewed line), is accepted; branch names and tags are refused. Prints the commit to build.
# Usage: nightly-check-ref.sh SRC_DIR REF      (SRC_DIR = full clone with origin/main, fetch-depth 0)
set -euo pipefail
src=${1:?usage: nightly-check-ref.sh SRC_DIR REF}; ref=${2:?}
if [[ $ref == main ]]; then git -C "$src" rev-parse --verify -q "origin/main^{commit}"; exit; fi
[[ $ref =~ ^[0-9a-f]{40}$ ]] || { echo "error: ref must be 'main' or a full commit SHA on main (no branch, no tag): $ref" >&2; exit 1; }
git -C "$src" cat-file -e "$ref^{commit}" 2> /dev/null || { echo "error: commit $ref not found" >&2; exit 1; }
git -C "$src" merge-base --is-ancestor "$ref" origin/main || { echo "error: $ref is not an ancestor of origin/main" >&2; exit 1; }
echo "$ref"
