#!/usr/bin/env bash
# Verify repomd.xml.asc against the PUBLIC key only (own empty GNUPGHOME, never the signing key): the signature must be valid and the
# primary key of the signer must be FPR. Proves that what was signed matches the key that is published, not just the secret key in CI.
# Usage: verify-repomd.sh PUBKEY.asc FPR repomd.xml repomd.xml.asc
set -euo pipefail
key=${1:?usage: verify-repomd.sh PUBKEY.asc FPR repomd.xml repomd.xml.asc}; want=${2:?}; xml=${3:?}; asc=${4:?}; want=${want^^}; want=${want// /}
tmp=$(mktemp -d); trap 'gpgconf --homedir "$tmp" --kill gpg-agent >/dev/null 2>&1 || true; rm -rf "$tmp"' EXIT
gpg --homedir "$tmp" --batch -q --import "$key" 2> /dev/null
st=$(gpg --homedir "$tmp" --batch --status-fd 1 --verify "$asc" "$xml" 2> /dev/null) || { echo "error: bad signature on $xml" >&2; exit 1; }
v=$(awk '$2 == "VALIDSIG" {print toupper($NF)}' <<< "$st")
[[ $v == "$want" ]] || { echo "error: signer primary key '$v' is not the pinned $want" >&2; exit 1; }
