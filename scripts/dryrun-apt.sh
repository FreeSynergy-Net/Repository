#!/usr/bin/env bash
# Dry run INSIDE A THROWAWAY DEBIAN/UBUNTU CONTAINER (refuses to run elsewhere): build the repo from real .deb files, sign it with a
# throwaway key, configure it like a user would (deb822 .sources + keyring), then `apt update` + `apt install` from file:// and check
# that tampering makes `apt update` fail. Never run on a real server; uses no real key.
#   podman run --rm -v "$PWD":/src:ro,z -v /path/to/debs:/debs:ro,z docker.io/library/debian:13 bash /src/scripts/dryrun-apt.sh /debs PKG...
# PKG...: package names to install (default: every package found in DEBDIR for amd64)
set -euo pipefail
[[ -e /run/.containerenv || -e /.dockerenv ]] || { echo "refusing: not inside a container" >&2; exit 2; }
debs=${1:?usage: dryrun-apt.sh DEBDIR [PKG...]}
shift
src=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq > /dev/null
apt-get install -y -qq --no-install-recommends apt-utils gnupg gpgv xz-utils > /dev/null
w=/work; mkdir -p $w; cp -r "$src/scripts" $w/
export GNUPGHOME=$w/gh; mkdir -m 700 "$GNUPGHOME"
printf 'Key-Type: EDDSA\nKey-Curve: ed25519\nKey-Usage: sign\nName-Real: dryrun\nExpire-Date: 0\n%%no-protection\n%%commit\n' > $w/spec
gpg --batch -q --generate-key $w/spec 2> /dev/null
fpr=$(gpg --batch --list-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}')
install -d -m 0755 /etc/apt/keyrings
gpg --batch --export "$fpr" > /etc/apt/keyrings/freesynergy-archive-keyring.pgp

$w/scripts/build-apt.sh --arch amd64,arm64 "$debs" stable $w/repo
$w/scripts/sign-apt.sh --key "$fpr" $w/repo stable
$w/scripts/verify-apt.sh --fingerprint "$fpr" $w/repo stable /etc/apt/keyrings/freesynergy-archive-keyring.pgp

# the distribution sources stay: the packages' dependencies (e.g. systemd) come from there
cat > /etc/apt/sources.list.d/freesynergy.sources <<SRC
Types: deb
URIs: file://$w/repo/
Suites: stable
Components: main
Signed-By: /etc/apt/keyrings/freesynergy-archive-keyring.pgp
SRC
apt-get update 2>&1 | tail -4
if (($# == 0)); then mapfile -t pkgs < <(grep '^Package:' $w/repo/dists/stable/main/binary-amd64/Packages | cut -d' ' -f2); else pkgs=("$@"); fi
for p in "${pkgs[@]}"; do apt-cache policy "$p" | sed -n '1,3p'; done
apt-get install -y -q --no-install-recommends "${pkgs[@]}" 2>&1 | tail -8
for p in "${pkgs[@]}"; do dpkg -s "$p" | grep -E '^(Package|Status|Version):' | paste -sd' '; done
echo "== counter-check: manipulated Packages indexes must make apt update fail"
rm -rf /var/lib/apt/lists/*
while IFS= read -r -d '' z; do printf 'X' | dd of="$z" bs=1 seek=20 conv=notrunc 2> /dev/null; done < <(find $w/repo/dists -path '*binary-amd64*' -type f -print0)  # plain, compressed and by-hash copies
apt-get update > $w/neg.txt 2>&1 || true
if ! grep -qE '^[EW]:.*work/repo' $w/neg.txt; then echo "FAIL: tampered index accepted"; cat $w/neg.txt; exit 1; else grep -E '^[EW]:.*work/repo' $w/neg.txt | head -3; echo "ok: tampered index refused"; fi
echo "== counter-check: manipulated InRelease must make apt update fail"
$w/scripts/build-apt.sh --arch amd64,arm64 "$debs" stable $w/repo > /dev/null
$w/scripts/sign-apt.sh --key "$fpr" $w/repo stable > /dev/null
rm -rf /var/lib/apt/lists/*
sed -i 's/^Label: FreeSynergy/Label: Evil/' $w/repo/dists/stable/InRelease
apt-get update > $w/neg2.txt 2>&1 || true
if ! grep -qE '^[EW]:.*work/repo' $w/neg2.txt; then echo "FAIL: tampered InRelease accepted"; cat $w/neg2.txt; exit 1; else grep -E '^[EW]:.*work/repo' $w/neg2.txt | head -3; echo "ok: tampered InRelease refused"; fi
echo "DRYRUN OK"
