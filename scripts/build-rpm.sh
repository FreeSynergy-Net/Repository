#!/usr/bin/env bash
# Build the UNSIGNED rpm channel tree: OUTDIR/rpm/<channel>/{*.rpm,repodata/} (repodata by createrepo_c from the Ubuntu archive in the key job; createrepo_rs only checks it afterwards, see gate-createrepo.sh).
# Usage: build-rpm.sh RPMDIR CHANNEL OUTDIR     CHANNEL = stable (the ONE channel: tagged releases and tagged pre-releases). The tool is createrepo_c (CREATEREPO may name another binary).
set -euo pipefail
src=${1:?usage: build-rpm.sh RPMDIR CHANNEL OUTDIR}; ch=${2:?}; out=${3:?}
case $ch in stable) ;; *) echo "error: the only channel is stable" >&2; exit 2 ;; esac
compgen -G "$src/*.rpm" > /dev/null || { echo "error: no .rpm in $src" >&2; exit 1; }
mkdir -p "$out/rpm/$ch"; rm -rf "$out/rpm/$ch/repodata"
cp -f "$src"/*.rpm "$out/rpm/$ch/"
"${CREATEREPO:-createrepo_c}" "$out/rpm/$ch"
echo "built $out/rpm/$ch with ${CREATEREPO:-createrepo_c} (unsigned)"
