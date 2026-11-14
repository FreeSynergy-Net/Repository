#!/usr/bin/env bash
# Verify one suite of an APT tree WITHOUT trusting anything but the keyring:
#   1. InRelease and Release.gpg carry a good signature (gpgv, own empty homedir; optional: primary fingerprint must match)
#   2. InRelease text == Release text
#   3. every file below dists/<suite> is listed in Release (SHA256) with matching size and hash; Packages.gz/.xz == Packages
#   4. every Filename in every Packages exists in the pool with matching Size and SHA256
# Usage: verify-apt.sh [--fingerprint PRIMARY_FPR] REPO SUITE KEYRING   (KEYRING: binary .pgp or armoured .asc)
# Exit 0 only if everything is OK; every problem prints a FAIL line. Needs gpgv, gpg (only to dearmor), sha256sum, gzip, xz.
set -euo pipefail
want=""
if [[ ${1:-} == --fingerprint ]]; then want=${2:?}; shift 2; want=${want^^}; want=${want// /}; fi
repo=${1:?usage: verify-apt.sh [--fingerprint F] REPO SUITE KEYRING}
suite=${2:?suite}
keyring=${3:?keyring}
dist=$repo/dists/$suite
[[ -d $dist && -f $keyring ]] || { echo "error: $dist or $keyring missing" >&2; exit 2; }
tmp=$(mktemp -d)
trap 'gpgconf --homedir "$tmp/gh" --kill gpg-agent >/dev/null 2>&1 || true; rm -rf "$tmp"' EXIT
mkdir -m 700 "$tmp/gh"
fail=0
bad() { echo "FAIL $*"; fail=1; }

kr=$tmp/keyring.pgp
if head -c 27 "$keyring" | grep -q -- '-----BEGIN PGP PUBLIC'; then
  gpg --homedir "$tmp/gh" --batch -q --dearmor --output "$kr" < "$keyring"
else
  cp "$keyring" "$kr"
fi

# 1. signatures: GOODSIG + VALIDSIG, none of the BAD statuses; primary fingerprint of EVERY VALIDSIG == wanted
check_sig() {
  local label=$1; shift
  local st
  st=$(gpgv --homedir "$tmp/gh" --keyring "$kr" --status-fd=1 "$@" 2>/dev/null || true)
  if grep -q -E '^\[GNUPG:\] (EXPKEYSIG|EXPSIG|REVKEYSIG|BADSIG|ERRSIG|NO_PUBKEY)( |$)' <<< "$st"; then
    bad "$label: $(grep -o -E '^\[GNUPG:\] (EXPKEYSIG|EXPSIG|REVKEYSIG|BADSIG|ERRSIG|NO_PUBKEY)' <<< "$st" | cut -d' ' -f2 | sort -u | paste -sd, -)"
    return
  fi
  if ! grep -q '^\[GNUPG:\] GOODSIG ' <<< "$st" || ! grep -q '^\[GNUPG:\] VALIDSIG ' <<< "$st"; then
    bad "$label: no good signature"
    return
  fi
  if [[ -n $want ]]; then
    while read -r p; do [[ $p == "$want" ]] || bad "$label: signed by primary key $p, expected $want"; done \
      < <(awk '$1=="[GNUPG:]" && $2=="VALIDSIG" {print toupper($12)}' <<< "$st")
  fi
  echo "signature ok: $label"
}
if [[ -f $dist/InRelease ]]; then check_sig InRelease --output "$tmp/inrelease.txt" "$dist/InRelease"; else bad "InRelease missing"; fi
if [[ -f $dist/Release.gpg ]]; then check_sig Release.gpg "$dist/Release.gpg" "$dist/Release"; else bad "Release.gpg missing"; fi

# 2. the clear-signed text must be the Release file (so both signatures cover the same indexes)
if [[ -s $tmp/inrelease.txt ]]; then
  # clear-signing drops the final newline; compare with a newline appended to both
  cmp -s <(cat "$tmp/inrelease.txt"; echo) <(cat "$dist/Release"; echo) || bad "InRelease text differs from Release"
fi

# 3. Release hashes over every file below dists/<suite> (except the metadata that is signed itself)
listed=$tmp/listed
awk '/^SHA256:/ {s=1; next} /^[^ ]/ {s=0} s && NF==3 {print $1, $2, $3}' "$dist/Release" > "$listed"
[[ -s $listed ]] || bad "Release has no SHA256 section"
while read -r h sz p; do
  f=$dist/$p
  [[ -f $f ]] || { bad "listed file missing: $p"; continue; }
  [[ $(stat -c %s "$f") == "$sz" ]] || bad "size mismatch: $p"
  [[ $(sha256sum "$f" | cut -d' ' -f1) == "$h" ]] || bad "SHA256 mismatch: $p"
done < "$listed"
while IFS= read -r -d '' f; do
  p=${f#"$dist"/}
  case $p in Release | InRelease | Release.gpg | */by-hash/*) continue ;; esac
  awk -v p="$p" '$3==p {f=1} END{exit !f}' "$listed" || bad "file not listed in Release: $p"
done < <(find "$dist" -type f -print0)
# by-hash copies: file name must be the hash of the content; with Acquire-By-Hash: yes every listed file has its SHA256 copy
while IFS= read -r -d '' f; do
  algo=$(basename "$(dirname "$f")")
  case $algo in SHA256) tool=sha256sum ;; SHA512) tool=sha512sum ;; *) continue ;; esac
  [[ $($tool "$f" | cut -d' ' -f1) == "$(basename "$f")" ]] || bad "by-hash name does not match content: ${f#"$dist"/}"
done < <(find "$dist" -path '*/by-hash/*' -type f -print0)
if grep -q '^Acquire-By-Hash: yes' "$dist/Release"; then
  while read -r h _ p; do
    [[ -f $(dirname "$dist/$p")/by-hash/SHA256/$h ]] || bad "by-hash copy missing: $p"
  done < "$listed"
fi
for p in $(awk '{print $3}' "$listed" | grep '/Packages$' || true); do
  gzip -dc "$dist/$p.gz" 2> /dev/null | cmp -s - "$dist/$p" || bad "$p.gz differs from $p"
  xz -dc "$dist/$p.xz" 2> /dev/null | cmp -s - "$dist/$p" || bad "$p.xz differs from $p"
done

# 4. Packages -> pool
npk=0
for pk in $(awk '{print $3}' "$listed" | grep '/Packages$' || true); do
  while read -r h sz fn; do
    npk=$((npk + 1))
    f=$repo/$fn
    [[ -f $f ]] || { bad "pool file missing: $fn"; continue; }
    [[ $(stat -c %s "$f") == "$sz" ]] || bad "size mismatch: $fn"
    [[ $(sha256sum "$f" | cut -d' ' -f1) == "$h" ]] || bad "SHA256 mismatch: $fn"
  done < <(awk 'BEGIN{RS=""; FS="\n"} {fn=""; sz=""; h=""; for(i=1;i<=NF;i++){ if($i ~ /^Filename: /) fn=substr($i,11); if($i ~ /^Size: /) sz=substr($i,7); if($i ~ /^SHA256: /) h=substr($i,9)} print h, sz, fn}' "$dist/$pk")
done
[[ $npk -gt 0 ]] || bad "no package entries found"
if [[ $fail == 0 ]]; then echo "OK $suite: signatures, Release hashes and $npk pool file(s) verified"; else exit 1; fi
