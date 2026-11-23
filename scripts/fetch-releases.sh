#!/usr/bin/env bash
# Download the .deb files of the newest releases of the given FreeSynergy repos, keep only those whose detached signature
# (<file>.deb.asc, made by the project key) verifies, and write them to OUTDIR (flat). Release = stable, pre-release = testing, all = both (ONE rpm channel); drafts never.
# Only releases with a VERSION TAG (v<digit>...) are taken: the rolling pre-release `nightly` (untagged builds) never goes in.
# The check is here in bash (the gh output is only a list of tags), so it holds for every suite.
# Usage: fetch-releases.sh [--keep N] SUITE OUTDIR PUBLIC_KEY.asc PRIMARY_FPR REPO...      (needs gh, jq, gpg, gpgv; GH_TOKEN for gh)
# Source of truth stays the release; this repository only holds a derived view (ADR 0068).
set -euo pipefail
keep=3; ext=${FETCH_EXT:-deb}   # FETCH_EXT=rpm fetches .rpm + .rpm.asc instead
if [[ ${1:-} == --keep ]]; then keep=${2:?}; shift 2; fi
suite=${1:?usage: fetch-releases.sh [--keep N] SUITE OUTDIR KEY FPR REPO...}
out=${2:?}; key=${3:?}; want=${4:?}; shift 4
case $suite in stable) sel='.isPrerelease==false' ;; testing) sel='.isPrerelease==true' ;; all) sel=true ;; *) echo "error: suite" >&2; exit 2 ;; esac
want=${want^^}; want=${want// /}
mkdir -p "$out"
tmp=$(mktemp -d); trap 'gpgconf --homedir "$tmp/gh" --kill gpg-agent >/dev/null 2>&1 || true; rm -rf "$tmp"' EXIT
mkdir -m 700 "$tmp/gh"
gpg --homedir "$tmp/gh" --batch -q --dearmor --output "$tmp/kr.pgp" < "$key"
for repo in "$@"; do
  mapfile -t tags < <(gh release list -R "FreeSynergy-Net/$repo" --limit 50 --json tagName,isPrerelease,isDraft \
    --jq ".[] | select(.isDraft==false and ($sel)) | .tagName" | grep -E '^v[0-9][0-9A-Za-z._+~-]*$' | head -n "$keep")
  for tag in "${tags[@]}"; do
    d=$tmp/$repo/$tag; mkdir -p "$d"
    gh release download "$tag" -R "FreeSynergy-Net/$repo" -p "*.$ext" -p "*.$ext.asc" -D "$d" || { echo "note: $repo $tag has no .$ext"; continue; }
    for f in "$d"/*."$ext"; do
      [[ -f $f ]] || continue
      st=$(gpgv --homedir "$tmp/gh" --keyring "$tmp/kr.pgp" --status-fd=1 "$f.asc" "$f" 2> /dev/null || true)
      if grep -q '^\[GNUPG:\] GOODSIG ' <<< "$st" && [[ $(awk '$2=="VALIDSIG" {print toupper($12)}' <<< "$st" | sort -u) == "$want" ]]; then
        cp "$f" "$out/"; echo "taken: $repo $tag $(basename "$f")"
      else
        echo "::warning::$repo $tag $(basename "$f"): signature missing or not by the project key - NOT taken"
      fi
    done
  done
done
