#!/usr/bin/env bash
# Trust anchor check of freesynergy-release BEFORE it is signed (it is built in a job without secrets, from third-party crates).
# Usage: check-release-pkg.sh RPM FPR PAGES_URL
# Needs: exactly the two files (key, repo file); the key = exactly one primary key == FPR (pubkey.sh); the repo file: stable baseurl PAGES_URL/rpm/stable enabled,
# nightly baseurl PAGES_URL/rpm/nightly disabled, gpgcheck=1 and repo_gpgcheck=1 in both, gpgkey = the packaged key, nothing else.
set -euo pipefail
rpm=${1:?usage: check-release-pkg.sh RPM FPR PAGES_URL}; fpr=${2:?}; url=${3:?}; url=${url%/}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
die() { echo "error: $rpm: $*" >&2; exit 1; }
(cd "$w" && rpm2cpio "$(readlink -f "$rpm")" | cpio -idm --quiet 2> /dev/null) || die "cannot unpack"
files=$(cd "$w" && find . -type f | sort | tr '\n' ' ')
[[ $files == "./etc/pki/rpm-gpg/RPM-GPG-KEY-freesynergy ./etc/yum.repos.d/freesynergy.repo " ]] || die "unexpected file list: $files"
"$here/pubkey.sh" "$w/etc/pki/rpm-gpg/RPM-GPG-KEY-freesynergy" "$fpr" "$w/pub.asc" || die "packaged key is not exactly $fpr"
got=$(awk '/^\[/ {s=$0} /^[a-z_]+=/ {print s " " $0}' "$w/etc/yum.repos.d/freesynergy.repo" | sort | tr '\n' '|')
want=$(printf '%s\n' \
  "[freesynergy] baseurl=$url/rpm/stable" "[freesynergy] enabled=1" "[freesynergy] gpgcheck=1" "[freesynergy] repo_gpgcheck=1" \
  "[freesynergy] gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-freesynergy" "[freesynergy] name=FreeSynergy (stable)" \
  "[freesynergy-nightly] baseurl=$url/rpm/nightly" "[freesynergy-nightly] enabled=0" "[freesynergy-nightly] gpgcheck=1" "[freesynergy-nightly] repo_gpgcheck=1" \
  "[freesynergy-nightly] gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-freesynergy" "[freesynergy-nightly] name=FreeSynergy (nightly, for testers)" | sort | tr '\n' '|')
[[ $got == "$want" ]] || die "repo file differs from the expected content (baseurl/enabled/gpgcheck/repo_gpgcheck/gpgkey)"
echo "ok: $rpm holds key $fpr and the expected repo file for $url"
