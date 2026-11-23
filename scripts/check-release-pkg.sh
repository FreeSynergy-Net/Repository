#!/usr/bin/env bash
# Trust anchor check of freesynergy-release BEFORE it is signed (it is built in a job without secrets, from third-party crates).
# Usage: check-release-pkg.sh RPM FPR PAGES_URL
# NEVER unpacks the package: the payload is listed first (cpio -t) and must hold EXACTLY the two expected entries, then each file is read
# with --to-stdout into a temp dir (nothing the archive names is ever written). Needs: no scriptlets/triggers/obsoletes/conflicts (read with an rpm that
# knows all scriptlet kinds of the target, see step 0); the header file list is the same two files, both root:root, 0644, flags none / %config(noreplace);
# no dependencies except rpmlib() and the package's own config()/name provides; the key = exactly one primary key == FPR (pubkey.sh); the repo file has the strict line form (section headers and key=value
# without spaces, no continuation lines) and its content equals the expected one: EXACTLY ONE section [freesynergy], name=FreeSynergy, baseurl PAGES_URL/rpm/stable,
# enabled=1, gpgcheck=1, repo_gpgcheck=1, gpgkey = the packaged key, nothing else (one channel; a second section or enabled=0 is refused).
set -euo pipefail
rpm=${1:?usage: check-release-pkg.sh RPM FPR PAGES_URL}; fpr=${2:?}; url=${3:?}; url=${url%/}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
die() { echo "error: $rpm: $*" >&2; exit 1; }
rpm=$(readlink -f "$rpm"); K=/etc/pki/rpm-gpg/RPM-GPG-KEY-freesynergy; Y=/etc/yum.repos.d/freesynergy.repo
payload() { rpm2cpio "$rpm" | cpio "$@" --quiet 2> /dev/null; }
# 0. the rpm that reads the header must know every scriptlet kind of the TARGET (Fedora, rpm >= 6.1: %preuntrans/%postuntrans exist since 4.20; an older rpm
#    does not show them). So it must be at least as new as the target's rpm: release-check runs in a Fedora container pinned by digest. Only the self-test
#    on the CI runner (rpm 4.18, which is needed for the payload-escape test) sets FS_ALLOW_OLD_RPM=1.
if [[ -z ${FS_ALLOW_OLD_RPM:-} ]]; then
  tags=$(rpm --querytags); [[ $tags == *PREUNTRANS*POSTUNTRANS* || $tags == *POSTUNTRANS*PREUNTRANS* ]] || die "this rpm does not know %preuntrans/%postuntrans: it would not show them"
fi
# 1. what the package would run or replace on the user's machine: nothing
extra=$(rpm -qp --scripts --triggers --filetriggers --obsoletes --conflicts "$rpm" 2> /dev/null) || die "cannot read the package header"
[[ -z $extra ]] || die "package carries scriptlets, triggers, obsoletes or conflicts"
[[ $(rpm -qpl "$rpm" 2> /dev/null) == "$K"$'\n'"$Y" ]] || die "header file list is not exactly the key and the repo file"
# mode, owner, group and flags of both files exactly (a repo file writable by "nobody" or 0666 is a way to root; the repo file is %config(noreplace) = "cn", the key has no flag)
[[ $(rpm -qp --qf '[%{FILEMODES:perms} %{FILEUSERNAME} %{FILEGROUPNAME} %{FILEFLAGS:fflags} %{FILENAMES}\n]' "$rpm" 2> /dev/null) == \
  "-rw-r--r-- root root  $K"$'\n'"-rw-r--r-- root root cn $Y" ]] || die "mode, owner, group or flags of the key or the repo file differ from the expected ones"
# dependencies exactly: only rpmlib() gates and the package's own config()/name provides; nothing else (Requires/Provides/Recommends/user() ...)
n=$(rpm -qp --qf '%{NAME}' "$rpm" 2> /dev/null); v=$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$rpm" 2> /dev/null)
req=$(rpm -qp --requires "$rpm" 2> /dev/null | grep -vE '^rpmlib\([A-Za-z0-9]+\) <= [0-9.:~^-]+$' || true)
[[ $req == "config($n) = $v" ]] || die "unexpected Requires"
[[ $(rpm -qp --provides "$rpm" 2> /dev/null | sort) == "$(printf '%s\n' "config($n) = $v" "$n = $v" | sort)" ]] || die "unexpected Provides"
[[ -z $(rpm -qp --recommends --suggests --supplements --enhances "$rpm" 2> /dev/null) ]] || die "unexpected Recommends/Suggests/Supplements/Enhances"
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
  "[freesynergy] gpgkey=file://$K" "[freesynergy] name=FreeSynergy" | sort | tr '\n' '|')
[[ $got == "$want" ]] || die "repo file differs from the expected content (baseurl/enabled/gpgcheck/repo_gpgcheck/gpgkey)"
echo "ok: $rpm holds key $fpr and the expected repo file for $url"
