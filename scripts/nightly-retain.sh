#!/usr/bin/env bash
# Keep only the newest N versions per package and architecture among the rpm assets (and their .asc) of the rolling release TAG.
# Usage: nightly-retain.sh TAG [KEEP=3]      (needs gh; GH_TOKEN with contents: write; run in the repository checkout or with GH_REPO)
set -euo pipefail
tag=${1:?usage: nightly-retain.sh TAG [KEEP]}; keep=${2:-3}
[[ $keep =~ ^[1-9][0-9]*$ ]] || { echo "error: KEEP must be a positive integer" >&2; exit 2; }
re='^(.+)-([0-9][^-]*)-[0-9]+\.([a-z0-9_]+)\.rpm$'
# "<package>.<arch> <stamp-sorted version> <file>"; the version differs only in the UTC stamp and the sha, so a version sort is the time order
gh release view "$tag" --json assets --jq '.assets[].name' | while read -r f; do
  [[ $f =~ $re ]] && echo "${BASH_REMATCH[1]}.${BASH_REMATCH[3]} ${BASH_REMATCH[2]} $f"
done | sort -k1,1 -k2,2V | awk -v k="$keep" '{n[$1]++; f[$1,n[$1]]=$3} END {for (p in n) for (i=1; i<=n[p]-k; i++) print f[p,i]}' | while read -r old; do
  echo "retention: delete $old"; gh release delete-asset "$tag" "$old" --yes; gh release delete-asset "$tag" "$old.asc" --yes 2> /dev/null || true
done
