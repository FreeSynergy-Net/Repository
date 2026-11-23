#!/usr/bin/env bash
# Trust anchor check of freesynergy-release BEFORE it is signed (it is built in a job without secrets, from third-party crates).
# Usage: check-release-pkg.sh RPM FPR PAGES_URL
# NEVER unpacks the package: the payload is listed first (cpio -t) and must hold EXACTLY the two expected entries, then each file is read
# with --to-stdout into a temp dir (nothing the archive names is ever written). Needs: no scriptlets/triggers/obsoletes/conflicts; the header file list
# is the same two files; the key = exactly one primary key == FPR (pubkey.sh); the repo file has the strict line form (section headers and key=value
# without spaces, no continuation lines) and its content equals the expected one: stable baseurl PAGES_URL/rpm/stable enabled, nightly baseurl
# PAGES_URL/rpm/nightly disabled, gpgcheck=1 and repo_gpgcheck=1 in both, gpgkey = the packaged key, nothing else.
set -euo pipefail
rpm=${1:?usage: check-release-pkg.sh RPM FPR PAGES_URL}; fpr=${2:?}; url=${3:?}; url=${url%/}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
die() { echo "error: $rpm: $*" >&2; exit 1; }
rpm=$(readlink -f "$rpm"); K=/etc/pki/rpm-gpg/RPM-GPG-KEY-freesynergy; Y=/etc/yum.repos.d/freesynergy.repo
payload() { rpm2cpio "$rpm" | cpio "$@" --quiet 2> /dev/null; }
# 1. what the package would run or replace on the user's machine: nothing
extra=$(rpm -qp --scripts --triggers --filetriggers --obsoletes --conflicts "$rpm" 2> /dev/null) || die "cannot read the package header"
[[ -z $extra ]] || die "package carries scriptlets, triggers, obsoletes or conflicts"
[[ $(rpm -qpl "$rpm" 2> /dev/null) == "$K"$'\n'"$Y" ]] || die "header file list is not exactly the key and the repo file"
# 2. the payload (what is actually extracted) is listed, never unpacked
[[ $(payload -t) == "."$K$'\n'"."$Y ]] || die "payload entries are not exactly the key and the repo file"
[[ $(payload -tv | cut -c1) == "-"$'\n'"-" ]] || die "payload entry is not a regular file"
payload -i --to-stdout "./${K#/}" > "$w/key.asc" || die "cannot read the key"
payload -i --to-stdout "./${Y#/}" > "$w/repo" || die "cannot read the repo file"
"$here/pubkey.sh" "$w/key.asc" "$fpr" "$w/pub.asc" || die "packaged key is not exactly $fpr"
# 3. repo file: strict form first (a continuation line or "key = value" would be read differently by dnf), then the content
! grep -vE '^$|^#|^\[[a-z-]+\]$|^[a-z_]+=[^[:space:]]' "$w/repo" | grep -q . || die "repo file has a line of unexpected form (continuation line, spaces around =, ...)"
got=$(awk '/^\[/ {s=$0} /^[a-z_]+=/ {print s " " $0}' "$w/repo" | sort | tr '\n' '|')
want=$(printf '%s\n' \
  "[freesynergy] baseurl=$url/rpm/stable" "[freesynergy] enabled=1" "[freesynergy] gpgcheck=1" "[freesynergy] repo_gpgcheck=1" \
  "[freesynergy] gpgkey=file://$K" "[freesynergy] name=FreeSynergy (stable)" \
  "[freesynergy-nightly] baseurl=$url/rpm/nightly" "[freesynergy-nightly] enabled=0" "[freesynergy-nightly] gpgcheck=1" "[freesynergy-nightly] repo_gpgcheck=1" \
  "[freesynergy-nightly] gpgkey=file://$K" "[freesynergy-nightly] name=FreeSynergy (nightly, for testers)" | sort | tr '\n' '|')
[[ $got == "$want" ]] || die "repo file differs from the expected content (baseurl/enabled/gpgcheck/repo_gpgcheck/gpgkey)"
echo "ok: $rpm holds key $fpr and the expected repo file for $url"
