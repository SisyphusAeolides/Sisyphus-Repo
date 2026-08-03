# Sisyphus Pacman Repository

This repository publishes x86_64 packages for:

- `ccze-rs`
- `elan-guardian`
- `libinput-rs`
- `tuned-rs`

Add the repository to `/etc/pacman.conf`:

```ini
[sisyphus]
SigLevel = Optional TrustAll
Server = https://sisyphusaeolides.github.io/Sisyphus-Repo/$arch
```

Then refresh the database and install packages normally:

```sh
sudo pacman -Syy
sudo pacman -S ccze-rs elan-guardian libinput-rs tuned-rs
```

The packages replace their corresponding `-git` names. `ccze-rs` replaces
`ccze`, `libinput-rs` replaces `libinput`, and `tuned-rs` replaces `tuned`
and `power-profiles-daemon` when those packages are installed.

## Current ArachOS integration status

This project is maintained as part of the ArachOS production graph. Its role is
the signed binary repository publication and package release channel..

CI and release evidence are evaluated on immutable revisions. Hardware support
is reported by bounded route and support level; this README does not claim
universal native support. Gate 3 requires signed hardware identity, target
kernel provenance, package authority, health checks, rollback behavior, and
representative physical-hardware evidence before production qualification.
