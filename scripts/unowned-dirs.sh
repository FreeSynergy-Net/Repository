#!/usr/bin/env bash
# Unowned-directory check per package over "the package + its transitive Requires among the rpms in DIR" (what a single install really has).
# Prints `UNOWNED <rpm>: <dir>` for every directory under /usr/share/freesynergy or /usr/libexec/freesynergy that no package of that chain owns.
# Usage: unowned-dirs.sh RPMDIR      (needs rpm; reads only; nothing is invented: a Require nobody in DIR provides adds nothing)
set -euo pipefail
dir=${1:?usage: unowned-dirs.sh RPMDIR}; shopt -s nullglob; declare -A prov
for f in "$dir"/*.rpm; do while read -r n _; do prov[$n]+="$f "; done < <(rpm -qp --provides "$f"); done
for f in "$dir"/*.rpm; do
  chain=("$f"); declare -A seen=(["$f"]=1)
  for ((i = 0; i < ${#chain[@]}; i++)); do
    while read -r n _; do for g in ${prov[$n]:-}; do [[ -n ${seen[$g]:-} ]] || { seen[$g]=1; chain+=("$g"); }; done; done < <(rpm -qp --requires "${chain[$i]}")
  done
  owned=$(for g in "${chain[@]}"; do rpm -qpl "$g"; done | sort -u)
  rpm -qpl "$f" | while read -r p; do d=$(dirname "$p"); while [[ $d != / ]]; do
    grep -qxF "$d" <<< "$owned" || case $d in /usr/share/freesynergy* | /usr/libexec/freesynergy*) echo "UNOWNED $(basename "$f"): $d" ;; esac; d=$(dirname "$d"); done; done | sort -u
  unset seen
done
