#!/usr/bin/env bash
# rpm version of a nightly: <next>~nightly.<UTC stamp>.g<sha7>. The tilde sorts it BEFORE the next release and AFTER the last one.
# <next> = the workspace version, raised by one patch step when that version is already released (tag v<version> exists).
# Usage: nightly-version.sh WORKSPACE_VERSION RELEASED(yes|no) STAMP(YYYYMMDDHHMMSS) SHA7
set -euo pipefail
ver=${1:?usage: nightly-version.sh VERSION yes|no STAMP SHA7}; released=${2:?}; stamp=${3:?}; sha=${4:?}
[[ $ver =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || { echo "error: plain x.y.z version expected, got $ver" >&2; exit 2; }
maj=${BASH_REMATCH[1]} min=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]}
[[ $released == yes || $released == no ]] || { echo "error: RELEASED must be yes or no" >&2; exit 2; }
[[ $stamp =~ ^[0-9]{14}$ && $sha =~ ^[0-9a-f]{7}$ ]] || { echo "error: bad stamp or sha" >&2; exit 2; }
[[ $released == no ]] || patch=$((patch + 1))
printf '%s.%s.%s~nightly.%s.g%s\n' "$maj" "$min" "$patch" "$stamp" "$sha"
