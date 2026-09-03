# Sisyphus Pacman Repository

This is the Arch Linux and compatible Arch-based distribution repository
maintained by SisyphusAeolides. Non-Arch package targets are intentionally
outside this repository's maintenance scope.

This repository publishes x86_64 packages for:

- `iwchaos`
- `blerust`
- `ccze-rs`
- `elan-guardian`
- `libinput-rs`
- `tuned-rs`


Add the repository to `/etc/pacman.conf`:

```ini
[sisyphus]
SigLevel = Required DatabaseRequired
Server = https://sisyphusaeolides.github.io/Sisyphus-Repo/$arch
```

Install the repository key before refreshing the database. Check the
fingerprint independently before adding or locally trusting the key:

```sh
curl --fail --location --output sisyphus-repo.asc \
  https://raw.githubusercontent.com/SisyphusAeolides/Sisyphus-Repo/main/keys/sisyphus-repo.asc
gpg --show-keys --with-fingerprint --keyid-format long sisyphus-repo.asc
# Expected primary fingerprint: A31AA80E123526D235385F4F590D7A398A6D75BB
sudo pacman-key --add sisyphus-repo.asc
sudo pacman-key --lsign-key A31AA80E123526D235385F4F590D7A398A6D75BB
sudo pacman -Syy
sudo pacman -S blerust ccze-rs elan-guardian iwchaos libinput-rs tuned-rs
```

`SigLevel = Required DatabaseRequired` rejects unsigned packages and unsigned
repository databases. Do not change it to `Optional` or `TrustAll`.

Each published repository state also has a signed, immutable package snapshot
at `https://sisyphusaeolides.github.io/Sisyphus-Repo/snapshots/<commit-sha>/`.
It retains the exact package archives, detached signatures, database, and
signed checksum manifest. The manifest records its source commit, workflow
run, timestamp, and SHA-256 checksums. The publishing workflow refuses to
replace an existing snapshot.

The packages replace their corresponding `-git` names. `blerust` replaces
`blesh`, `ccze-rs` replaces `ccze`, `iwchaos` replaces in-tree `iwlwifi` and
`iwlmvm`, `libinput-rs` replaces `libinput`, and `tuned-rs` replaces `tuned`
and `power-profiles-daemon` when those packages are installed.

