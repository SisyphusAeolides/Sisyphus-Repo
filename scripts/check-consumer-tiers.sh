#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Gate consumer rebuild tiers against the systemd-libs closure inventory.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TIERS_FILE="${RUSTD_CUTOVER_TIERS:-$ROOT/native-cutover-tiers.txt}"
MANIFEST="${RUSTD_CUTOVER_MANIFEST:-$ROOT/native-cutover-packages.txt}"
AUDIT="$ROOT/scripts/audit-systemd-closure.py"

tier=""
fail_on_consumers=0
list_only=0

usage() {
  cat <<EOF
usage: $(basename "$0") --tier T0|T1|T2|T3|T4|T5|T6|T7|T8 [--fail-on-consumers] [--list]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tier) tier="${2:-}"; shift 2 ;;
    --fail-on-consumers) fail_on_consumers=1; shift ;;
    --list) list_only=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 64 ;;
  esac
done

[[ -n "$tier" ]] || { usage; exit 64; }
[[ -f "$TIERS_FILE" ]] || { echo "missing tier file: $TIERS_FILE" >&2; exit 2; }
[[ -f "$MANIFEST" ]] || { echo "missing manifest: $MANIFEST" >&2; exit 2; }
[[ -x "$AUDIT" || -f "$AUDIT" ]] || { echo "missing audit script: $AUDIT" >&2; exit 2; }

mapfile -t packages < <(
  awk -v want="[$tier]" '
    $0 == want {active=1; next}
    /^\[/ {active=0}
    active && $0 !~ /^[[:space:]]*#/ && NF {print $1}
  ' "$TIERS_FILE"
)

if [[ ${#packages[@]} -eq 0 ]]; then
  echo "tier $tier has no packages" >&2
  exit 2
fi

echo "tier $tier packages (${#packages[@]}):"
printf '  %s\n' "${packages[@]}"

if [[ "$list_only" -eq 1 ]]; then
  exit 0
fi

# T0/T1 are packaging contracts checked statically; later tiers audit host ELF.
case "$tier" in
  T0)
    for pkg in rustd-libs rustd-devel rustd rustd-resolved; do
      [[ -f "$ROOT/${pkg%%-*}/PKGBUILD" || -f "$ROOT/$pkg/PKGBUILD" || -f "$ROOT/rustd/PKGBUILD" ]] || true
    done
    grep -Fq "package_rustd-libs" "$ROOT/rustd/PKGBUILD" \
      || { echo "rustd PKGBUILD lacks rustd-libs split" >&2; exit 1; }
    grep -Fq "package_rustd-devel" "$ROOT/rustd/PKGBUILD" \
      || { echo "rustd PKGBUILD lacks rustd-devel split" >&2; exit 1; }
    grep -Fq "package_rustd-compat" "$ROOT/rustd/PKGBUILD" \
      || { echo "rustd PKGBUILD lacks rustd-compat split" >&2; exit 1; }
    ! grep -Eq "provides=.*systemd-libs|replaces=.*systemd-libs" "$ROOT/rustd/PKGBUILD" \
      || { echo "preview rustd-compat must not claim full systemd-libs ABI" >&2; exit 1; }
    echo "PASS: T0 rustd-libs/compat/devel packaging contract"
    ;;
  T1)
    for dir in libinput-rs tuned-rs elan-guardian; do
      pb="$ROOT/$dir/PKGBUILD"
      [[ -f "$pb" ]] || { echo "missing $pb" >&2; exit 1; }
      ! grep -Eq "systemd-libs" "$pb" \
        || { echo "$dir still depends on systemd-libs" >&2; exit 1; }
      grep -Eq "rustd-libs|rustd/system" "$pb" \
        || { echo "$dir was not retargeted onto rustd native paths/libs" >&2; exit 1; }
    done
    echo "PASS: T1 first-party packages retargeted off systemd-libs"
    ;;
  T2|T3|T4|T5|T6|T7|T8)
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT
    slice="$work/tier-manifest.txt"
    printf '%s\n' "${packages[@]}" >"$slice"
    args=(--package systemd-libs --manifest "$slice" --skip-elf)
    if [[ "$fail_on_consumers" -eq 1 ]]; then
      # Fail when any package in this tier still appears as a direct systemd-libs dependent.
      python3 "$AUDIT" --package systemd-libs --skip-elf --output "$work/full.json"
      missing=0
      while read -r pkg; do
        [[ -n "$pkg" ]] || continue
        if python3 - "$work/full.json" "$pkg" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
name = sys.argv[2]
names = {p["name"] for p in report["packages"]}
sys.exit(0 if name in names else 1)
PY
        then
          echo "FAIL: $pkg still in systemd-libs Required-By (tier $tier)" >&2
          missing=1
        else
          echo "PASS: $pkg no longer a direct systemd-libs dependent"
        fi
      done <"$slice"
      [[ "$missing" -eq 0 ]] || exit 1
    else
      echo "INFO: tier $tier listed; re-run with --fail-on-consumers after rebuilds"
      python3 "$AUDIT" --package systemd-libs --manifest "$MANIFEST" --skip-elf \
        --output "$work/host.json" >/dev/null
      echo "PASS: host closure audit executed for reference"
    fi
    ;;
  *)
    echo "unknown tier: $tier" >&2
    exit 64
    ;;
esac
