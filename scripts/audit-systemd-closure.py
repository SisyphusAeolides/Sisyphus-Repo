#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Inventory installed packages that must be rebuilt for native RustD."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys

FORBIDDEN_SONAMES = ("libsystemd.so.0", "libudev.so.1")


def command(*args: str) -> str:
    return subprocess.run(
        args,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    ).stdout


def package_info(name: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    current = ""
    for line in command("pacman", "-Qi", name).splitlines():
        if line.startswith(" "):
            if current:
                fields[current] += f" {line.strip()}"
            continue
        key, separator, value = line.partition(":")
        if separator:
            current = key.strip()
            fields[current] = value.strip()
    return fields


def package_files(name: str) -> list[Path]:
    files = []
    for line in command("pacman", "-Qlq", name).splitlines():
        path = Path(line)
        try:
            if path.is_file() and path.stat().st_size >= 4:
                files.append(path)
        except OSError:
            continue
    return files


def elf_dependencies(path: Path) -> list[str]:
    try:
        with path.open("rb") as stream:
            if stream.read(4) != b"\x7fELF":
                return []
        dynamic = command("readelf", "-d", str(path))
    except (OSError, subprocess.CalledProcessError):
        return []
    return [soname for soname in FORBIDDEN_SONAMES if f"[{soname}]" in dynamic]


def direct_dependents(package: str) -> list[str]:
    required_by = package_info(package).get("Required By", "")
    if not required_by or required_by == "None":
        return []
    return sorted(set(required_by.split()))


def audit(package: str, scan_elf: bool) -> dict[str, object]:
    dependents = direct_dependents(package)
    packages = []
    for name in dependents:
        linked = []
        if scan_elf:
            for path in package_files(name):
                sonames = elf_dependencies(path)
                if sonames:
                    linked.append({"path": str(path), "sonames": sonames})
        packages.append({"name": name, "elf_consumers": linked})
    return {
        "source_package": package,
        "forbidden_sonames": list(FORBIDDEN_SONAMES),
        "direct_dependent_count": len(dependents),
        "packages": packages,
    }

def load_manifest(path: Path) -> set[str]:
    return {
        line
        for raw in path.read_text().splitlines()
        if (line := raw.strip()) and not line.startswith("#")
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", default="systemd-libs")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument(
        "--skip-elf",
        action="store_true",
        help="only compare package metadata; skip the slower ELF scan",
    )
    parser.add_argument(
        "--fail-on-drift",
        action="store_true",
        help="fail when installed direct dependents differ from the manifest",
    )
    parser.add_argument(
        "--fail-on-consumers",
        action="store_true",
        help="fail when package or ELF consumers remain",
    )
    args = parser.parse_args()

    try:
        report = audit(args.package, scan_elf=not args.skip_elf)
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"closure audit failed: {error}", file=sys.stderr)
        return 2

    package_count = int(report["direct_dependent_count"])
    elf_count = sum(
        len(package["elf_consumers"]) for package in report["packages"]  # type: ignore[index]
    )
    print(
        f"systemd closure: {package_count} direct packages, "
        f"{elf_count} linked ELF files",
        file=sys.stderr,
    )
    drift = False
    if args.manifest:
        expected = load_manifest(args.manifest)
        actual = {package["name"] for package in report["packages"]}
        missing = sorted(expected - actual)
        untracked = sorted(actual - expected)
        report["manifest"] = {
            "path": str(args.manifest),
            "missing_from_host": missing,
            "untracked_on_host": untracked,
        }
        drift = bool(missing or untracked)
        if drift:
            print(
                f"manifest drift: {len(missing)} missing, {len(untracked)} untracked",
                file=sys.stderr,
            )

    rendered = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered)
    else:
        sys.stdout.write(rendered)

    if args.fail_on_drift and drift:
        return 3
    if args.fail_on_consumers and (package_count or elf_count):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
