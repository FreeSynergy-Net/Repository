#!/usr/bin/env bash
# Shape of the signing workflows (check.yml). Usage: check-key-jobs.sh WORKFLOW.yml [GATE_JOB]
# Rules: exactly ONE job uses secrets.GPG_*; it is in environment apt-signing; no other job names apt-signing; inside the key job there is no
# `cargo install`, no createrepo_rs, no `uses:` except actions/* and FreeSynergy-Net/fs-release/, no curl|sh. With GATE_JOB: job `deploy` lists it in `needs`.
# Threat model (honest): this protects against MISTAKES (VERSEHEN), not against someone who can change the workflow, the toolchain or the scripts (they can change this check too).
set -euo pipefail
wf=${1:?usage: check-key-jobs.sh WORKFLOW.yml [GATE_JOB]}; gate=${2:-}
# No other workflow in the directory may name apt-signing or secrets.GPG_ (only publish.yml and nightly.yml are key workflows).
for o in "$(dirname "$wf")"/*.yml; do
  [ "$o" = "$wf" ] && continue
  case $(basename "$o") in publish.yml|nightly.yml) continue;; esac
  if grep -qE "^[ ]*(- )?environment:[ ]*apt-signing|^[ ]*[A-Za-z_]+:[ ]*\$\{\{[ ]*secrets\.GPG_" "$o"; then echo "error: $o names apt-signing or secrets.GPG_ (only publish.yml and nightly.yml may)"; exit 1; fi
done
awk -v gate="$gate" '
  /^jobs:/ {inj=1; next}
  inj && /^  [A-Za-z0-9_-]+:[ ]*(#.*)?$/ {job=$1; sub(/:$/, "", job); next}
  !inj || job=="" || /^[ ]*#/ {next}
  /secrets\.GPG_/ {key[job]=1}
  /apt-signing/ {env[job]=1}
  /cargo install|createrepo_rs|(curl|wget)[^|]*\|[ ]*(sudo[ ]+(-[A-Za-z]+[ ]+)*)?(ba|z)?sh/ {bad[job]=bad[job] " [" $0 "]"}
  /^[ ]*(- )?uses:/ {u=$0; sub(/.*uses:[ ]*/, "", u); if (u !~ /^(actions\/|FreeSynergy-Net\/fs-release\/)/) bad[job]=bad[job] " [uses " u "]"}
  /^    needs:/ && job=="deploy" {dn=dn $0}
  END {
    for (j in key) {n++; k=j}
    if (n != 1) {print "error: " n+0 " jobs use secrets.GPG_ (exactly 1 allowed)"; e=1}
    if (n == 1) {
      if (!(k in env)) {print "error: key job " k " is not in environment apt-signing"; e=1}
      for (j in env) if (j != k) {print "error: job " j " names apt-signing (only the key job may)"; e=1}
      if (bad[k] != "") {print "error: foreign code in key job " k ":" bad[k]; e=1}
    }
    if (gate != "" && dn !~ gate) {print "error: deploy does not list " gate " in needs"; e=1}
    if (!e) print "ok: one key job (" k "), environment apt-signing, nothing foreign in it"
    exit e
  }' "$wf"
