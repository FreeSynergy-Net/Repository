#!/usr/bin/env bash
# Assemble the GitHub Pages site (github.io first; same tree works under apt.<domain> or a Codeberg mirror later):
#   SITE/apt/{dists,pool}            the signed repository tree
#   SITE/apt/freesynergy-archive-keyring.pgp (+ .asc)   the public key (binary for Signed-By, armoured for humans)
#   SITE/apt/freesynergy.sources     ready-made deb822 file for BASE_URL
#   SITE/rpm/freesynergy.repo        ready-made dnf repo file
#   SITE/index.html                  fingerprint, working-version notice, dnf and apt setup
# The key file is NOT published as is: it must contain exactly ONE primary key and that must be PRIMARY_FPR; only that key is exported.
# Usage: make-site.sh REPO SITE PUBLIC_KEY.asc BASE_URL PRIMARY_FPR     (BASE_URL e.g. https://freesynergy-net.github.io/Repository/apt/)
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
# dnf side: ready-made repo file (same values as the freesynergy-release package, but with the key as a URL so it works without that package)
rpmbase=${base%apt/}rpm/
mkdir -p "$site/rpm"
cat > "$site/rpm/freesynergy.repo" <<REPO
[freesynergy]
name=FreeSynergy
baseurl=${rpmbase}stable
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=${rpmbase}RPM-GPG-KEY-freesynergy
REPO
cat > "$site/index.html" <<HTML
<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>FreeSynergy packages</title>
<h1>FreeSynergy packages</h1>
<p><strong>Working version / Arbeitsversion.</strong> These are early pre-releases: they work, but they change often and are not finished. Das sind frühe Vorabversionen: sie laufen, ändern sich aber oft und sind nicht fertig.</p>
<p>Primary key fingerprint (check it against the project website and the ADR before you trust the key / Fingerabdruck vor dem Vertrauen mit der Projektseite vergleichen): <code>$fpr</code></p>
<h2>dnf (Fedora)</h2>
<p>Repo file / Quelldatei: <a href="rpm/freesynergy.repo">freesynergy.repo</a> (to <code>/etc/yum.repos.d/</code>), key / Schlüssel: <a href="rpm/RPM-GPG-KEY-freesynergy">RPM-GPG-KEY-freesynergy</a>. Both signature checks are on (<code>gpgcheck=1</code>, <code>repo_gpgcheck=1</code>). Or install the package / oder das Paket installieren: <a href="rpm/freesynergy-release.noarch.rpm">freesynergy-release.noarch.rpm</a>. Then / dann: <code>dnf install fs-tasks</code>.</p>
<h2>apt (Debian, Ubuntu)</h2>
<p>Setup: see docs/en/setup-apt.md (docs/de/einrichtung-apt.md) in the Repository repository. Key: <a href="apt/freesynergy-archive-keyring.asc">asc</a>, <a href="apt/freesynergy-archive-keyring.pgp">pgp</a>; source file / Quelldatei: <a href="apt/freesynergy.sources">freesynergy.sources</a>.</p>
HTML
echo "site assembled in $site (key $fpr)"
