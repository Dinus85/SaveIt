#!/usr/bin/env python3
"""Validate a compiled SaveIn simulator .app or its ZIP archive."""

from __future__ import annotations

import argparse
import plistlib
import sys
import zipfile
from pathlib import Path


class BundleReader:
    def __init__(self, source: Path) -> None:
        self.source = source
        self.archive = zipfile.ZipFile(source) if source.suffix.lower() == ".zip" else None

        if self.archive:
            app_plists = [
                name
                for name in self.archive.namelist()
                if name.endswith(".app/Info.plist")
                and "/PlugIns/" not in name
                and "/Frameworks/" not in name
            ]
            if len(app_plists) != 1:
                raise ValueError(f"Expected one app Info.plist, found {len(app_plists)}")
            self.root = app_plists[0][: -len("Info.plist")]
        else:
            if not source.is_dir() or source.suffix != ".app":
                raise ValueError("Input must be a compiled .app directory or a ZIP containing one")
            self.root = ""

    def names(self) -> list[str]:
        if self.archive:
            return self.archive.namelist()
        return [
            path.relative_to(self.source).as_posix()
            for path in self.source.rglob("*")
            if path.is_file()
        ]

    def read(self, relative_path: str) -> bytes:
        if self.archive:
            return self.archive.read(f"{self.root}{relative_path}")
        return (self.source / relative_path).read_bytes()

    def exists(self, relative_path: str) -> bool:
        if self.archive:
            return f"{self.root}{relative_path}" in self.archive.namelist()
        return (self.source / relative_path).is_file()


def require(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact", type=Path, help="Runner.app or Runner.app.zip")
    args = parser.parse_args()

    try:
        bundle = BundleReader(args.artifact)
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2

    extension_plists = [
        name
        for name in bundle.names()
        if name.endswith(".appex/Info.plist") and "/PlugIns/" in name
    ]
    if bundle.archive:
        extension_plists = [
            name[len(bundle.root) :]
            for name in extension_plists
            if name.startswith(bundle.root)
        ]

    errors: list[str] = []
    require(
        len(extension_plists) == 1,
        f"Expected exactly one embedded extension, found {len(extension_plists)}",
        errors,
    )
    if errors:
        print("\n".join(f"ERROR: {error}" for error in errors), file=sys.stderr)
        return 1

    extension_plist_path = extension_plists[0]
    host = plistlib.loads(bundle.read("Info.plist"))
    extension = plistlib.loads(bundle.read(extension_plist_path))

    host_id = host.get("CFBundleIdentifier")
    extension_id = extension.get("CFBundleIdentifier")
    host_version = host.get("CFBundleShortVersionString")
    host_build = host.get("CFBundleVersion")

    require(host_id == "eu.savein.app", f"Unexpected host bundle ID: {host_id}", errors)
    require(
        isinstance(extension_id, str) and extension_id.startswith(f"{host_id}."),
        f"Extension bundle ID is not prefixed by host ID: {extension_id}",
        errors,
    )
    require(extension.get("CFBundlePackageType") == "XPC!", "Extension package type is not XPC!", errors)
    require(extension.get("CFBundleExecutable"), "Extension executable name is missing", errors)
    require(host_version == extension.get("CFBundleShortVersionString"), "Marketing versions differ", errors)
    require(host_build == extension.get("CFBundleVersion"), "Build numbers differ", errors)
    require(
        "iPhoneSimulator" in host.get("CFBundleSupportedPlatforms", []),
        "Host was not built for iPhoneSimulator",
        errors,
    )
    require(
        "iPhoneSimulator" in extension.get("CFBundleSupportedPlatforms", []),
        "Extension was not built for iPhoneSimulator",
        errors,
    )

    extension_directory = extension_plist_path[: -len("Info.plist")]
    executable_path = f"{extension_directory}{extension.get('CFBundleExecutable', '')}"
    require(bundle.exists(executable_path), f"Missing extension executable: {executable_path}", errors)

    extension_entries = [
        name
        for name in bundle.names()
        if extension_directory in name
    ]
    require(
        not any("/Frameworks/" in name or "Flutter.framework" in name for name in extension_entries),
        "The extension embeds frameworks; it must remain dependency-free",
        errors,
    )

    ns_extension = extension.get("NSExtension", {})
    require(
        ns_extension.get("NSExtensionPointIdentifier") == "com.apple.share-services",
        "Wrong or missing Share Extension point identifier",
        errors,
    )
    require(
        bool(ns_extension.get("NSExtensionPrincipalClass")),
        "NSExtensionPrincipalClass is missing",
        errors,
    )

    if errors:
        print("\n".join(f"ERROR: {error}" for error in errors), file=sys.stderr)
        return 1

    print(
        "PASS:",
        f"{host_id} {host_version}+{host_build}",
        "embeds",
        extension_id,
        "with matching simulator metadata",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
