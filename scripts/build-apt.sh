#!/usr/bin/env bash
# Build the unsigned APT tree (pool/ + dists/) from a directory of .deb files with apt-ftparchive (stateless: the tree IS the state).
# Usage: build-apt.sh [--keep N] [--arch amd64[,arm64]] [--valid-days D] [--no-index] DEBDIR SUITE OUTDIR
#   SUITE   stable (= releases) or testing (= pre-releases)
#   OUTDIR  repository root; an existing tree is extended (older versions beyond --keep are removed, default 3 per package+arch)
#   --no-index  only copy + prune (used by the self-test where apt-ftparchive is missing)
#   --valid-days D  adds Valid-Until = Date + D days (off by default: the repo must then be re-signed regularly or clients refuse it; decision open)
# Layout: pool/<suite>/<prefix>/<pkg>/<pkg>_<ver>_<arch>.deb, dists/<suite>/{Release,main/binary-<arch>/Packages{,.gz,.xz}}.
# Signing is NOT done here (sign-apt.sh, only in the sign job).
set -euo pipefail
keep=3 archs=amd64 valid="" index=1
while [[ ${1:-} == --* ]]; do
  case $1 in
    --keep) keep=${2:?}; shift 2 ;;
    --arch) archs=${2:?}; shift 2 ;;
    --valid-days) valid=${2:?}; shift 2 ;;
    --no-index) index=0; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
debdir=${1:?usage: build-apt.sh [options] DEBDIR SUITE OUTDIR}
suite=${2:?suite}
out=${3:?outdir}
case $suite in stable | testing) ;; *) echo "error: suite must be stable or testing" >&2; exit 2 ;; esac
[[ $keep =~ ^[1-9][0-9]*$ ]] || { echo "error: --keep must be a positive number" >&2; exit 2; }
[[ -d $debdir ]] || { echo "error: $debdir is not a directory" >&2; exit 2; }
mkdir -p "$out"
out=$(cd "$out" && pwd)
pool=$out/pool/$suite

# pkg_ver_arch.deb -> sets pkg ver arch; only plain Debian names are accepted (they become paths).
parse_name() {
  local b=${1##*/}
  b=${b%.deb}
  arch=${b##*_}
  local rest=${b%_*}
  ver=${rest##*_}
  pkg=${rest%_*}
  [[ $b == *_*_* && $pkg =~ ^[a-z0-9][a-z0-9+.-]+$ && $ver =~ ^[A-Za-z0-9.+~%-]+$ && $arch =~ ^(amd64|arm64|all)$ ]]
}

prefix_of() { if [[ $1 == lib* ]]; then echo "${1:0:4}"; else echo "${1:0:1}"; fi; }

shopt -s nullglob
n=0
for f in "$debdir"/*.deb; do
  pkg="" ver="" arch=""
  parse_name "$f" || { echo "error: unusable file name $(basename "$f") (want <pkg>_<version>_<amd64|arm64|all>.deb)" >&2; exit 1; }
  dest=$pool/$(prefix_of "$pkg")/$pkg
  mkdir -p "$dest"
  cp -f "$f" "$dest/"
  n=$((n + 1))
done
echo "copied $n .deb into pool/$suite"

# Retention: keep the newest $keep versions per package+arch (sort -V orders 1.10 after 1.2 and ~pre before the release).
prune() {
  local dir g
  declare -A groups=()
  while IFS= read -r f; do
    pkg="" ver="" arch=""
    parse_name "$f" || continue
    groups["$(dirname "$f")|$pkg|$arch"]+="$ver"$'\t'"$f"$'\n'
  done < <(find "$pool" -type f -name '*.deb' 2>/dev/null | sort)
  for g in "${!groups[@]}"; do
    mapfile -t old < <(printf '%s' "${groups[$g]}" | sort -V -k1,1 -t $'\t' | head -n "-$keep" | cut -f2)
    for dir in "${old[@]}"; do
      [[ -n $dir ]] || continue
      echo "retention: removing ${dir#"$out"/}"
      rm -f -- "$dir"
    done
  done
}
prune
[[ $index == 1 ]] || exit 0

command -v apt-ftparchive >/dev/null || { echo "error: apt-ftparchive missing (package apt-utils)" >&2; exit 3; }
[[ -d $pool ]] && [[ -n $(find "$pool" -name '*.deb' -print -quit) ]] || { echo "error: no .deb in pool/$suite" >&2; exit 1; }
cd "$out"
dist=dists/$suite
rm -rf "$dist"
archlist=${archs//,/ }
for a in $archlist; do
  bin=$dist/main/binary-$a
  mkdir -p "$bin"
  apt-ftparchive --arch "$a" packages "pool/$suite" > "$bin/Packages"
  gzip -9 -n -c "$bin/Packages" > "$bin/Packages.gz"
  xz -9 -c "$bin/Packages" > "$bin/Packages.xz"
done
opts=(-o "APT::FTPArchive::Release::Origin=FreeSynergy" -o "APT::FTPArchive::Release::Label=FreeSynergy"
  -o "APT::FTPArchive::Release::Suite=$suite" -o "APT::FTPArchive::Release::Codename=$suite"
  -o "APT::FTPArchive::Release::Architectures=$archlist" -o "APT::FTPArchive::Release::Components=main"
  -o "APT::FTPArchive::Release::Description=FreeSynergy packages ($suite)")
# by-hash: clients fetch the indexes by content hash, so a republish never serves a Release that points at a half-updated Packages
opts+=(-o "APT::FTPArchive::DoByHash=1")
if [[ -n $valid ]]; then
  [[ $valid =~ ^[1-9][0-9]*$ ]] || { echo "error: --valid-days must be a positive number" >&2; exit 2; }
  # apt-ftparchive writes Valid-Until = Date + ValidTime (seconds)
  opts+=(-o "APT::FTPArchive::Release::ValidTime=$((valid * 86400))")
fi
apt-ftparchive "${opts[@]}" release "$dist" > Release.tmp
mv Release.tmp "$dist/Release"
echo "built $dist (unsigned): $(grep -c '^Filename:' "$dist/main/binary-${archlist%% *}/Packages") package file(s) in the first index"
