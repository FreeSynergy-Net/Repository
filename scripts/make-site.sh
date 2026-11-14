#!/usr/bin/env bash
# Assemble the GitHub Pages site (github.io first; same tree works under apt.<domain> or a Codeberg mirror later):
#   SITE/apt/{dists,pool}            the signed repository tree
#   SITE/apt/freesynergy-archive-keyring.pgp (+ .asc)   the public key (binary for Signed-By, armoured for humans)
#   SITE/apt/freesynergy.sources     ready-made deb822 file for BASE_URL
#   SITE/index.html                  fingerprint and 4 setup lines
# The key file is NOT published as is: it must contain exactly ONE primary key and that must be PRIMARY_FPR; only that key is exported.
# Usage: make-site.sh REPO SITE PUBLIC_KEY.asc BASE_URL PRIMARY_FPR     (BASE_URL e.g. https://freesynergy.github.io/fs-packages/apt/)
set -euo pipefail
repo=${1:?usage: make-site.sh REPO SITE KEY.asc BASE_URL PRIMARY_FPR}; site=${2:?}; key=${3:?}; base=${4:?}; want=${5:?}
want=${want^^}; want=${want// /}
[[ $base == https://*/ ]] || { echo "error: BASE_URL must be https://.../ (trailing slash)" >&2; exit 2; }
[[ -d $repo/dists ]] || { echo "error: $repo/dists missing" >&2; exit 1; }
tmp=$(mktemp -d); trap 'gpgconf --homedir "$tmp" --kill gpg-agent >/dev/null 2>&1 || true; rm -rf "$tmp"' EXIT; chmod 700 "$tmp"
gpg --homedir "$tmp" --batch -q --import "$key" 2> /dev/null
mapfile -t primaries < <(gpg --homedir "$tmp" --batch --list-keys --with-colons | awk -F: '/^pub:/ {p=1; next} p && /^fpr:/ {print toupper($10); p=0}')
if [[ ${#primaries[@]} != 1 || ${primaries[0]} != "$want" ]]; then
  echo "error: key file must contain exactly one primary key, $want; found: ${primaries[*]:-none}" >&2; exit 1
fi
fpr=$want
# "stable" exists only once a full (non-pre) release is packaged; until then the ready-made file points at testing
suite=stable; [[ -d $repo/dists/stable ]] || suite=testing
mkdir -p "$site/apt"
cp -a "$repo/dists" "$repo/pool" "$site/apt/"
gpg --homedir "$tmp" --batch --export "$fpr" > "$site/apt/freesynergy-archive-keyring.pgp"
gpg --homedir "$tmp" --batch --armor --export "$fpr" > "$site/apt/freesynergy-archive-keyring.asc"
cat > "$site/apt/freesynergy.sources" <<SRC
Types: deb
URIs: $base
Suites: $suite
Components: main
Signed-By: /etc/apt/keyrings/freesynergy-archive-keyring.pgp
SRC
cat > "$site/index.html" <<HTML
<!doctype html><meta charset="utf-8"><title>FreeSynergy packages</title>
<h1>FreeSynergy APT repository</h1>
<p>Primary key fingerprint (check it against the project website and the ADR before you trust the key): <code>$fpr</code></p>
<p>Setup: see docs/en/setup-apt.md (docs/de/einrichtung-apt.md) in the fs-packages repository. Key: <a href="apt/freesynergy-archive-keyring.asc">asc</a>, <a href="apt/freesynergy-archive-keyring.pgp">pgp</a>; source file: <a href="apt/freesynergy.sources">freesynergy.sources</a>.</p>
HTML
echo "site assembled in $site (key $fpr)"
