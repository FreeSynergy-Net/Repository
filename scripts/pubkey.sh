#!/usr/bin/env bash
# Export ONLY the pinned primary key of a key file: the file must hold exactly one primary key and it must be FPR (no secret key).
# Usage: pubkey.sh KEY.asc FPR OUT.asc      (used for the key in freesynergy-release and for RPM-GPG-KEY-freesynergy)
set -euo pipefail
key=${1:?usage: pubkey.sh KEY.asc FPR OUT.asc}; want=${2:?}; out=${3:?}; want=${want^^}; want=${want// /}
tmp=$(mktemp -d); trap 'gpgconf --homedir "$tmp" --kill gpg-agent >/dev/null 2>&1 || true; rm -rf "$tmp"' EXIT
gpg --homedir "$tmp" --batch -q --import "$key" 2> /dev/null
if gpg --homedir "$tmp" --batch --list-secret-keys --with-colons 2> /dev/null | grep -q '^sec:'; then echo "error: $key holds a secret key" >&2; exit 1; fi
mapfile -t p < <(gpg --homedir "$tmp" --batch --list-keys --with-colons | awk -F: '/^pub:/ {k=1; next} k && /^fpr:/ {print toupper($10); k=0}')
[[ ${#p[@]} == 1 && ${p[0]} == "$want" ]] || { echo "error: want exactly one primary key $want; found: ${p[*]:-none}" >&2; exit 1; }
gpg --homedir "$tmp" --batch --armor --export "$want" > "$out"
