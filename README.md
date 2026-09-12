# Sisyphus Package Repository

This is the signed x86_64 package feed maintained by SisyphusAeolides for
compatible mkosi systems. The archives and repository index use Arch's
package format so mkosi can assemble a reproducible live image, and `pacman`
is the supported package interface.

This repository publishes x86_64 packages for:

- `iwchaos`
- `blerust`
- `ccze-rs`
- `libinput-rs`
- `tuned-rs`

Add the repository to `/etc/pacman.conf`:

```ini
[sisyphus]
SigLevel = Required DatabaseRequired
# CDN mirror first; raw GitHub remains the canonical fallback.
Server = https://cdn.jsdelivr.net/gh/SisyphusAeolides/Sisyphus-Repo@main/$arch
Server = https://raw.githubusercontent.com/SisyphusAeolides/Sisyphus-Repo/main/$arch
```

Install the repository key before refreshing the database. Check the
fingerprint independently before adding or locally trusting the key:

```sh
curl --fail --location --output sisyphus-repo.asc \
  https://raw.githubusercontent.com/SisyphusAeolides/Sisyphus-Repo/main/keys/sisyphus-repo.asc
curl --fail --location --output sisyphus-repo-2026.asc \
  https://raw.githubusercontent.com/SisyphusAeolides/Sisyphus-Repo/main/keys/sisyphus-repo-2026.asc
gpg --show-keys --with-fingerprint --keyid-format long sisyphus-repo.asc sisyphus-repo-2026.asc
# Expected primary fingerprints: A31AA80E123526D235385F4F590D7A398A6D75BB
#                              BB4B20152E487BEC32051E1C1466A088F999E0C8
sudo pacman-key --add sisyphus-repo.asc sisyphus-repo-2026.asc
sudo pacman-key --lsign-key A31AA80E123526D235385F4F590D7A398A6D75BB
sudo pacman-key --lsign-key BB4B20152E487BEC32051E1C1466A088F999E0C8
sudo pacman -Syy
sudo pacman -S blerust ccze-rs iwchaos libinput-rs tuned-rs
```

The commands above are for preparing an mkosi build host. A running
installation consumes the same signed feed through `pacman`:

```sh
pacman -Ss iwchaos
sudo pacman -S iwchaos
sudo pacman -Syu
sudo pacman -Rs iwchaos
```

`SigLevel = Required DatabaseRequired` rejects unsigned packages and unsigned
repository databases. Do not change it to `Optional` or `TrustAll`.

Each published repository state also has a signed, immutable package snapshot
at `https://raw.githubusercontent.com/SisyphusAeolides/Sisyphus-Repo/main/snapshots/<commit-sha>/`.
It retains the exact package archives, detached signatures, database, and
signed checksum manifest. The manifest records its source commit, workflow
run, timestamp, and SHA-256 checksums. The publishing workflow refuses to
replace an existing snapshot.

The packages replace their corresponding `-git` names. `blerust` replaces
`blesh`, `ccze-rs` replaces `ccze`, `iwchaos` replaces in-tree `iwlwifi` and
`iwlmvm`, `libinput-rs` replaces `libinput`, and `tuned-rs` replaces `tuned`
and `power-profiles-daemon` when those packages are installed.
