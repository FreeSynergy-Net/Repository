# Repository

Signed package repositories of FreeSynergy (APT now, RPM later: `apt/`, `rpm/`). The releases of the program repositories stay the source of
truth (`.deb` + detached `.asc`); this repository only builds a derived, signed view of them. Nothing here is published by itself.

- Docs: [English](docs/en/README.md) | [Deutsch](docs/de/README.md)
- Set up the source on Debian/Ubuntu: [docs/en/setup-apt.md](docs/en/setup-apt.md) | [docs/de/einrichtung-apt.md](docs/de/einrichtung-apt.md)
- Licence: MIT or Apache-2.0 ([LICENSE-MIT](LICENSE-MIT), [LICENSE-APACHE](LICENSE-APACHE))

| Script | Job |
|--------|-----|
| `scripts/fetch-releases.sh` | newest 3 releases per repo and suite, keeps only `.deb` whose `.asc` verifies against the project key |
| `scripts/build-apt.sh` | `pool/` + `dists/` with `apt-ftparchive`, retention 3 versions per package and architecture, unsigned |
| `scripts/sign-apt.sh` | `InRelease` + `Release.gpg` with a given key (in CI: called by the signing job only, temporary GNUPGHOME) |
| `scripts/verify-apt.sh` | signature against a keyring, Release hashes against the files, Packages against the pool |
| `scripts/make-site.sh` | Pages layout: `apt/{dists,pool,keyring,.sources}` + `index.html` |
| `scripts/test_apt.sh` | self-test with throwaway keys and self-built `.deb` (build, sign, verify, counter-checks, retention) |
| `scripts/dryrun-apt.sh` | dry run in a throwaway Debian container: `apt update` + `apt install` from the repo, tampering must fail |
| `scripts/test-container.sh` | runs self-test (+ dry run) in a throwaway container image (debian:12/13, ubuntu:24.04 checked) |

CI: `check.yml` (shellcheck + self-test, no secrets), `publish.yml` (draft: build without secrets, sign in a separate job, Pages deploy not executed).
