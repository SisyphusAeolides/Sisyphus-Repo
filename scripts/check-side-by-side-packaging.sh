#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Verify side-by-side certification packaging contracts for RustD packages.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

check_pkgbuild() {
  local dir="$1"
  local name="$2"
  local commit="$3"
  local pb="$ROOT/$dir/PKGBUILD"
  local src="$ROOT/$dir/.SRCINFO"

  [[ -f "$pb" ]] || fail "missing $pb"
  [[ -f "$src" ]] || fail "missing $src"

  grep -Fq "_commit=$commit" "$pb" || fail "$name PKGBUILD commit pin mismatch"
  grep -Fq "commit=$commit" "$src" || fail "$name .SRCINFO commit pin mismatch"
  ! grep -E -q "provides=\\(['\"]?systemd" "$pb" || fail "$name must not provide systemd during certification"
  ! grep -E -q "conflicts=\\(['\"]?systemd" "$pb" || fail "$name must not conflict systemd during certification"
  ! grep -Fq "provides = systemd" "$src" || fail "$name .SRCINFO must not provide systemd"
  ! grep -Fq "conflicts = systemd" "$src" || fail "$name .SRCINFO must not conflict systemd"
  pass "$name side-by-side packaging contract"
}

check_boot_assets() {
  local dir="$ROOT/rustd"
  [[ -f "$dir/rustd-configure-boot" ]] || fail "missing rustd-configure-boot"
  [[ -f "$dir/rustd-boot-entry.conf" ]] || fail "missing rustd-boot-entry.conf"
  [[ -f "$dir/90-rustd-boot.hook" ]] || fail "missing alpm boot hook"
  grep -Fq 'init=/usr/lib/rustd/rustd' "$dir/rustd-configure-boot" \
    || fail "boot script missing RustD init="
  grep -Fq 'init=/usr/lib/rustd/rustd' "$dir/rustd-boot-entry.conf" \
    || fail "boot entry missing RustD init="
  bash -n "$dir/rustd-configure-boot"
  pass "RustD alternate-boot assets"
}

check_pkgbuild rustd rustd 661f8acc8e2dd67ac8e4933affb28174ba860cdc
check_pkgbuild rustd-resolved rustd-resolved d5f7610d2f8696c2b335115fe81c94fce362a05d
check_boot_assets

# Simulate boot entry generation against a fake loader directory.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/loader/entries" "$work/bootlib"
cp "$ROOT/rustd/rustd-boot-entry.conf" "$work/bootlib/rustd-boot-entry.conf"
cat >"$work/loader/entries/cachyos.conf" <<'EOF'
title   CachyOS
linux   /vmlinuz-linux-cachyos
initrd  /initramfs-linux-cachyos.img
options root=UUID=test rw quiet
EOF
RUSTD_LOADER_ENTRIES="$work/loader/entries" \
RUSTD_BOOT_CONF="$work/bootlib/rustd-boot-entry.conf" \
  bash "$ROOT/rustd/rustd-configure-boot"
[[ -f "$work/loader/entries/rustd-certification.conf" ]] \
  || fail "did not create rustd-certification.conf"
grep -Fq 'init=/usr/lib/rustd/rustd' "$work/loader/entries/rustd-certification.conf" \
  || fail "generated entry missing RustD init"
[[ -f "$work/loader/entries/.rustd-systemd-rollback" ]] \
  || fail "missing rollback marker"
pass "boot entry generation preserves systemd rollback"

echo "All side-by-side packaging checks passed."
