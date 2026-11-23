#!/usr/bin/env bash
# Build the UNSIGNED rpm channel tree: OUTDIR/rpm/<channel>/{*.rpm,repodata/} (repodata by createrepo_rs, CI tool, GPL-2.0, never shipped).
# Usage: build-rpm.sh RPMDIR CHANNEL OUTDIR     CHANNEL = stable | nightly. CREATEREPO=createrepo_c switches to the fallback tool.
set -euo pipefail
src=${1:?usage: build-rpm.sh RPMDIR CHANNEL OUTDIR}; ch=${2:?}; out=${3:?}
case $ch in stable | nightly) ;; *) echo "error: channel must be stable or nightly" >&2; exit 2 ;; esac
compgen -G "$src/*.rpm" > /dev/null || { echo "error: no .rpm in $src" >&2; exit 1; }
mkdir -p "$out/rpm/$ch"; rm -rf "$out/rpm/$ch/repodata"
cp -f "$src"/*.rpm "$out/rpm/$ch/"
"${CREATEREPO:-createrepo_rs}" "$out/rpm/$ch"
echo "built $out/rpm/$ch with ${CREATEREPO:-createrepo_rs} (unsigned)"
