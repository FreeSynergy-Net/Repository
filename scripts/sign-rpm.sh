#!/usr/bin/env bash
# Two stages, because signing a package changes its checksum: (1) packages: rpmsign every .rpm in DIR; then build-rpm.sh makes repodata
# from the SIGNED files; (2) repo: detached armoured repodata/repomd.xml.asc (for repo_gpgcheck).
# Usage: sign-rpm.sh [--homedir DIR] [--passphrase-file FILE] --key FPR packages|repo DIR      (DIR = dir with the rpms, resp. .../rpm/<channel>)
# Key material only here and in the CI sign job (temporary GNUPGHOME); nothing secret is printed.
set -euo pipefail
home="" pass="" key=""; 
while [[ ${1:-} == --* ]]; do
  case $1 in --homedir) home=${2:?}; shift 2 ;; --passphrase-file) pass=${2:?}; shift 2 ;; --key) key=${2:?}; shift 2 ;; *) echo "unknown option $1" >&2; exit 2 ;; esac
done
stage=${1:?usage: sign-rpm.sh [options] --key FPR packages|repo DIR}; dir=${2:?}; [[ -n $key ]] || { echo "error: --key FPR required" >&2; exit 2; }
opts=(--batch --yes --local-user "$key" --digest-algo SHA512); rdef=(--define "_gpg_name $key")
[[ -z $home ]] || { opts+=(--homedir "$home"); rdef+=(--define "_gpg_path $home"); }
if [[ -n $pass ]]; then
  opts+=(--pinentry-mode loopback --passphrase-file "$pass")
  rdef+=(--define "__gpg_sign_cmd %{__gpg} gpg --batch --no-verbose --no-armor --pinentry-mode loopback --passphrase-file $pass %{?_gpg_digest_algo:--digest-algo %{_gpg_digest_algo}} --no-secmem-warning -u \"%{_gpg_name}\" -sbo %{__signature_filename} %{?_gpg_path:--homedir %{_gpg_path}} %{__plaintext_filename}")
fi
case $stage in
  packages) rpmsign "${rdef[@]}" --addsign "$dir"/*.rpm ;;
  repo) [[ -s $dir/repodata/repomd.xml ]] || { echo "error: $dir/repodata/repomd.xml missing" >&2; exit 1; }
    rm -f "$dir/repodata/repomd.xml.asc"
    gpg "${opts[@]}" --armor --detach-sign --output "$dir/repodata/repomd.xml.asc" "$dir/repodata/repomd.xml" ;;
  *) echo "error: stage must be packages or repo" >&2; exit 2 ;;
esac
echo "signed ($stage) $dir with key $key"
