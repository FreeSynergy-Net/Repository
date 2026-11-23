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
rpm/stable/{*.rpm,repodata/}                dnf channel = releases; repodata/repomd.xml.asc = detached signature (repo_gpgcheck=1)
rpm/nightly/{*.rpm,repodata/}               dnf channel = pre-releases
```

`freesynergy-release` (built by `fs-blueprint package release --pages-url https://freesynergy-net.github.io/Repository`) points dnf at `<pages>/rpm/stable` (enabled) and `<pages>/rpm/nightly` (disabled) with `gpgcheck=1` and `repo_gpgcheck=1`.

Suites: `stable` (= releases), `testing` (= pre-releases). Architectures `amd64` and `arm64` indexed. Retention: 3 versions per package and architecture and suite.
A later mirror (Codeberg Pages, own domain) is the same tree; trust sits in the signature, not in the place (ADR 0062).

## How it is built

1. `fetch-releases.sh`: `.deb` files from the releases of the listed repos, only with a valid signature of the project key.
2. `build-apt.sh`: `apt-ftparchive` (stateless: the tree is the state; the site is rebuilt completely from the releases every time).
3. Signing only in the separate `sign` job (`GPG_PRIVATE_KEY`, `GPG_PASSPHRASE`, fs-release action `sign-apt`; temporary GNUPGHOME).
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

- The Pages deploy and `publish.yml` have never run; three `REPLACE_SHA` pins (fs-release `sign-apt` after the 0.0.7 merge, `upload-pages-artifact`, `deploy-pages`) are entered after review; `key_ref` is a reviewed fs-release commit.
- `fetch-releases.sh` and `make-site.sh` were not run against real releases (the dry run used local test builds of zentinel 26.11.2-1 and kanidmd 1.12.1-1).
- Signing key: the secret is assumed to hold only the subkey; it expires 2027-11-07 (renew and re-publish the keyring before that).
- Self-test and dry run (`scripts/test-container.sh`) ran in debian:13, debian:12 and ubuntu:24.04 containers: apt update/install, tampered index/InRelease refused.

## rpm channel

Order matters, because signing a package changes its checksum: `fetch-releases.sh` (`FETCH_EXT=rpm`) -> `sign-rpm.sh ... packages DIR` (rpmsign, key job) ->
`build-rpm.sh RPMDIR stable|nightly OUTDIR` (repodata by `createrepo_rs` 0.1.9, GPL-2.0, CI only, never shipped; `CREATEREPO=createrepo_c` is the fallback) ->
`sign-rpm.sh ... repo rpm/<channel>` (`repomd.xml.asc`). `gate-createrepo.sh` compares createrepo_rs against createrepo_c on the same rpms and prints the tool to use.
Local gate (podman, throwaway Fedora container, throwaway key only inside it): `scripts/test-rpm-container.sh RPMDIR` — install works; tampered package, tampered repomd.xml and unsigned package are refused; then the unowned-directory check (per package: itself + Requires chain, `unowned-dirs.sh`) and rpmlint (any E = red, W allowed).


### Nightly (test builds without a tag)

`nightly.yml` (draft, started by a person with `workflow_dispatch`: `repo`, `ref` = `main` or a full commit SHA that is an ancestor of origin/main (branches and tags are refused in the first job, before build and sign; `scripts/nightly-check-ref.sh`, test `scripts/test_nightly_ref.sh`); job `sign` checks again, before it touches a secret, that the built commit (recorded by each build) equals the verified one (`scripts/nightly-verify-built.sh`), `package`, `key_ref`) builds ONE repository in CI (no secrets), signs in the environment `apt-signing` (same secrets, nothing new) and uploads the rpm files plus `.rpm.asc` to the rolling pre-release `nightly` of this repository (3 versions per package and architecture, `scripts/nightly-retain.sh`). Version: `<next>~nightly.<UTC stamp>.g<sha7>` (`scripts/nightly-version.sh`; sorts after the last and before the next release). `publish.yml` takes that release into `rpm/nightly` (the channel is off by default at the user). Nothing built locally ever goes in.
## Switching on GitHub Pages (owner, once; not done by agents)

Repository `FreeSynergy-Net/Repository` > Settings > Pages > Build and deployment > Source: **GitHub Actions**. Then run the workflow `publish` (Actions > publish > Run workflow) with `deploy` ticked.
Address afterwards: `https://freesynergy-net.github.io/Repository/` (repo setting may also be changed to an own domain later).
