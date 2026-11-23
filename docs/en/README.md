# Repository (English)

## Layout (GitHub Pages first, `https://freesynergy-net.github.io/Repository/`)

```
index.html                                  fingerprint + links
apt/freesynergy.sources                     ready-made deb822 file
apt/freesynergy-archive-keyring.{pgp,asc}   public key (binary for Signed-By, armoured for people)
apt/dists/<suite>/{Release,InRelease,Release.gpg}
apt/dists/<suite>/main/binary-amd64/Packages{,.gz,.xz}
apt/pool/<suite>/<prefix>/<package>/<package>_<version>_<arch>.deb
rpm/RPM-GPG-KEY-freesynergy                 public key (same key as apt)
rpm/stable/{*.rpm,repodata/}                the ONE dnf channel = all version-tagged releases and pre-releases (never an untagged build); repodata/repomd.xml.asc = detached signature (repo_gpgcheck=1)
```

`freesynergy-release` (built by `fs-blueprint package release --fingerprint <pinned FPR> --pages-url https://freesynergy-net.github.io/Repository`) points dnf at `<pages>/rpm/stable` (ONE section `[freesynergy]`, `name=FreeSynergy`, enabled) with `gpgcheck=1` and `repo_gpgcheck=1`.

First install, always in this order: fetch `<pages>/rpm/RPM-GPG-KEY-freesynergy`, compare the fingerprint (`16A4 A3EE 563A EF51 FCF0 C55D ED7B 57C4 A190 4342`), `rpm --import`, then `dnf install --setopt=localpkg_gpgcheck=1 <pages>/rpm/freesynergy-release.noarch.rpm` (Fedora does not check the signature of local or URL packages by default, so without that option an unimported key is not noticed). The version of `freesynergy-release` follows the fs-blueprint version; when the key or the Pages URL changes, `--pkg-version` MUST be raised in the `release-pkg` job of `publish.yml`.

apt suites (rpm has ONE channel, see above; apt is not merged to one suite yet): `stable` (= releases), `testing` (= pre-releases). Architectures `amd64` and `arm64` indexed. Retention: 3 versions per package and architecture and suite.
A later mirror (Codeberg Pages, own domain) is the same tree; trust sits in the signature, not in the place (ADR 0062).

## How it is built

1. `fetch-releases.sh`: `.deb` files from the releases of the listed repos, only with a valid signature of the project key.
2. `build-apt.sh`: `apt-ftparchive` (stateless: the tree is the state; the site is rebuilt completely from the releases every time).
3. Signing only in the separate `sign` job (`GPG_PRIVATE_KEY`, `GPG_PASSPHRASE`, `scripts/sign-apt.sh`; temporary GNUPGHOME; the fs-release action `sign-apt` is not merged, so it is not used).
4. `verify-apt.sh` against the public key from fs-release, then `make-site.sh`, then (not yet run) the Pages deploy.

Indexes are also served by hash (`by-hash`, `Acquire-By-Hash: yes`), so a republish never mixes old and new files.

## Signing environment (owner, once; nothing of it exists yet)

1. Settings > Environments > New environment `apt-signing`: deployment branches = `main` only, required reviewer = the owner.
2. Secrets **only in that environment** (not in the repository or organisation): `GPG_PRIVATE_KEY` = export of the **signing subkey only**
   (`gpg --armor --export-secret-subkeys <subkey-fpr>!`; the primary key stays offline), `GPG_PASSPHRASE`. Fingerprints: primary `16A4 A3EE 563A EF51 FCF0 C55D ED7B 57C4 A190 4342`, signing subkey `372A 583D 05BF 8362 604C F25D E26A 2347 F2B1 C097`.
3. Settings > Actions > General: enable "Require actions to be pinned to a full-length commit SHA".
4. Settings > Pages: Source = GitHub Actions. Then run `publish` (inputs: `repos`, `key_ref` = reviewed fs-release commit, `deploy`).

## Re-signing and `Valid-Until`

By default `Release` has no `Valid-Until`, so the repository never expires for clients. `build-apt.sh --valid-days N` sets `Valid-Until = Date + N days`
(`APT::FTPArchive::Release::ValidTime`); then the repository MUST be rebuilt and re-signed on a schedule or clients refuse it. Open decision of the strategy.

## Limits (not proven)

- The Pages deploy and `publish.yml` have never run; all actions are pinned by full SHA (`upload-pages-artifact` v5.0.0, `deploy-pages` v5.0.1, checked against their tags 2026-11-23); `key_ref` is a reviewed fs-release commit.
- `fetch-releases.sh` and `make-site.sh` were not run against real releases (the dry run used local test builds of zentinel 26.11.2-1 and kanidmd 1.12.1-1).
- Signing key: the secret is assumed to hold only the subkey; it expires 2027-11-07 (renew and re-publish the keyring before that).
- Self-test and dry run (`scripts/test-container.sh`) ran in debian:13, debian:12 and ubuntu:24.04 containers: apt update/install, tampered index/InRelease refused.

## rpm channel

Order matters, because signing a package changes its checksum: `fetch-releases.sh` (`FETCH_EXT=rpm`) -> `sign-rpm.sh ... packages DIR` (rpmsign, key job) ->
`build-rpm.sh RPMDIR stable OUTDIR` (repodata by `createrepo_c` from the Ubuntu archive, in the key job) ->
`sign-rpm.sh ... repo rpm/<channel>` (`repomd.xml.asc`). `gate-createrepo.sh` (job `rpm-index-gate`, NO key): createrepo_rs 0.1.9 (GPL-2.0, CI only, never shipped) rebuilds the index from the signed packages and must equal the index of the key job; a difference makes the run red and nothing is deployed (no fallback).

One approval per run: publish.yml has exactly ONE job with the key, `sign` (environment `apt-signing`): rpm packages, index, repomd.xml and the apt suites are signed there. `scripts/check-key-jobs.sh` (check.yml, with 5 mutants in `test_check_key_jobs.sh`) keeps that shape: exactly one job with `secrets.GPG_`, in `apt-signing`, no `cargo install`, no foreign `uses:`, the gate in `deploy.needs`. Threat model (honest): it protects against MISTAKES, not against someone who can change the workflow, the toolchain or the scripts. Not yet shown live: the first real run (one approval, gate green); `scripts/test_fetch.sh` (red test: tagged releases and pre-releases go in, the untagged `nightly` never) uses a fake `gh`, no network.

Local gate (podman, throwaway Fedora container, throwaway key only inside it): `scripts/test-rpm-container.sh RPMDIR` — install works; tampered package, tampered repomd.xml and unsigned package are refused; then the unowned-directory check (per package: itself + Requires chain, `unowned-dirs.sh`) and rpmlint (any E = red, W allowed).


### Nightly (test builds without a tag)

`nightly.yml` (draft, started by a person with `workflow_dispatch`: `repo`, `ref` = `main` or a full commit SHA that is an ancestor of origin/main (branches and tags are refused in the first job, before build and sign; `scripts/nightly-check-ref.sh`, test `scripts/test_nightly_ref.sh`); job `sign` checks again, before it touches a secret, that the built commit (recorded by each build) equals the verified one (`scripts/nightly-verify-built.sh`), `package`, `key_ref`) builds ONE repository in CI (no secrets), signs in the environment `apt-signing` (same secrets, nothing new) and uploads the rpm files plus `.rpm.asc` to the rolling pre-release `nightly` of this repository (3 versions per package and architecture, `scripts/nightly-retain.sh`). Version: `<next>~nightly.<UTC stamp>.g<sha7>` (`scripts/nightly-version.sh`; sorts after the last and before the next release). `publish.yml` does NOT take it (only version-tagged releases go into the one channel `rpm/stable`): it is a download for testers. Nothing built locally ever goes in.

Checks added in the same step as the signing (scripts, each with a counter-test in `test_verify.sh` / `test_nightly_ref.sh`): `check-rpm-signed.sh` (plain `rpm -K` exits 0 for an UNSIGNED package; the text `digests signatures OK` is required), `check-release-pkg.sh` (own job `release-check` WITHOUT environment and secrets, before `freesynergy-release` is signed; the package is never unpacked: its payload is listed and must hold exactly the key file and the repo file as regular files, then each is read to stdout; both files exactly root:root, 0644 with the expected flags (repo file `%config(noreplace)`); no scriptlets, triggers, obsoletes or conflicts, as far as the checking rpm knows them: `release-check` runs in a Fedora 45 container pinned by digest (rpm 6.1, which also knows `%preuntrans`/`%postuntrans`) and the script refuses an rpm without those tags; no dependencies except `rpmlib()` and the package's own `config()`/name provides; the key is the pinned primary key; the repo file has a strict line form (no continuation lines, no spaces around `=`) and exactly the expected `baseurl`, `enabled`, `gpgcheck`, `repo_gpgcheck`, `gpgkey`. The key job `sign` only compares the sha256 of the package with the one `release-check` approved), and `pubkey.sh` for the published key in `nightly.yml` as in `publish.yml`.

## Switching on GitHub Pages (owner, once; not done by agents)

Repository `FreeSynergy-Net/Repository` > Settings > Pages > Build and deployment > Source: **GitHub Actions**. Then run the workflow `publish` (Actions > publish > Run workflow) with `deploy` ticked.
Address afterwards: `https://freesynergy-net.github.io/Repository/` (repo setting may also be changed to an own domain later).
