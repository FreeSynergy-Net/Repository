# FreeSynergy-APT-Quelle einrichten (Debian, Ubuntu, node1)

Als root. Den Schlüssel laden, **die Fingerabdrücke selbst prüfen**, erst dann nur für diese Quelle vertrauen (`Signed-By`, nie `apt-key`/`trusted.gpg.d`).

```sh
install -d -m 0755 /etc/apt/keyrings
tmp=$(mktemp -d)
curl -fsSL https://freesynergy-net.github.io/Repository/apt/freesynergy-archive-keyring.asc -o "$tmp/key.asc"
gpg --show-keys --with-fingerprint --with-subkey-fingerprints "$tmp/key.asc"
```

Der Fingerabdruck des Hauptschlüssels muss genau `16A4 A3EE 563A EF51 FCF0 C55D ED7B 57C4 A190 4342` sein, der des Signier-Unterschlüssels
`372A 583D 05BF 8362 604C F25D E26A 2347 F2B1 C097` (mit der Projektseite vergleichen). Sonst: abbrechen.

```sh
gpg --dearmor < "$tmp/key.asc" > /etc/apt/keyrings/freesynergy-archive-keyring.pgp
curl -fsSL https://freesynergy-net.github.io/Repository/apt/freesynergy.sources -o /etc/apt/sources.list.d/freesynergy.sources
rm -rf "$tmp"
apt update
apt install zentinel        # oder kanidmd
```

Die Datei `freesynergy.sources` enthält `Types: deb`, `URIs: https://freesynergy-net.github.io/Repository/apt/`, `Suites: stable`, `Components: main` und
`Signed-By: /etc/apt/keyrings/freesynergy-archive-keyring.pgp`.

**Suiten:** `stable` = volle Releases, `testing` = Vorab-Releases. Solange ein Programm nur Vorab-Releases hat (z. B. Zentinel vor dem ersten vollen
Release), gibt es `stable` noch nicht; die fertige Datei (von `make-site.sh`) steht dann schon auf `Suites: testing`. Das Wort auf `stable` ändern,
sobald nur volle Releases gewünscht sind. Meldet `apt update` „not signed“ oder „NO_PUBKEY“, nichts installieren.
