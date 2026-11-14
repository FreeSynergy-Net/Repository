#!/usr/bin/env bash
# Sign the APT metadata of one suite: dists/<suite>/InRelease (clearsign) and dists/<suite>/Release.gpg (detached, armoured).
# Usage: sign-apt.sh [--homedir DIR] [--passphrase-file FILE] --key FPR REPO SUITE
#   --key FPR     fingerprint of the primary key whose signing subkey signs (gpg picks the signing subkey; no "!" forcing)
#   --homedir     GNUPGHOME that holds the secret key (default: gpg's default, i.e. in CI the temporary one of the sign action)
# Only this script and the fs-release sign action touch key material; nothing secret is printed.
set -euo pipefail
home="" pass="" key=""
while [[ ${1:-} == --* ]]; do
  case $1 in
    --homedir) home=${2:?}; shift 2 ;;
    --passphrase-file) pass=${2:?}; shift 2 ;;
    --key) key=${2:?}; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
repo=${1:?usage: sign-apt.sh [options] --key FPR REPO SUITE}
suite=${2:?suite}
[[ -n $key ]] || { echo "error: --key FPR is required" >&2; exit 2; }
dist=$repo/dists/$suite
[[ -s $dist/Release ]] || { echo "error: $dist/Release missing (run build-apt.sh first)" >&2; exit 1; }
opts=(--batch --yes --local-user "$key" --digest-algo SHA512)
[[ -z $home ]] || opts+=(--homedir "$home")
[[ -z $pass ]] || opts+=(--pinentry-mode loopback --passphrase-file "$pass")
rm -f "$dist/InRelease" "$dist/Release.gpg"
gpg "${opts[@]}" --clearsign --output "$dist/InRelease" "$dist/Release"
gpg "${opts[@]}" --armor --detach-sign --output "$dist/Release.gpg" "$dist/Release"
echo "signed $dist: InRelease, Release.gpg (key $key)"
