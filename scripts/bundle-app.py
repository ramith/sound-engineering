#!/usr/bin/env python3
"""
Bundle Swift executable into macOS .app format.

Usage:
    python3 scripts/bundle-app.py --executable .build/debug/AdaptiveSound --output .build/debug/AdaptiveSound.app
"""

import argparse
import plistlib
import shutil
import subprocess
from pathlib import Path


def create_app_bundle(executable_path: Path, output_path: Path, info_plist: Path = None, icon_icns: Path = None,
                      overrides: dict = None):
    """Create a macOS .app bundle from an executable.

    `overrides` replaces Info.plist keys in the bundled copy (never the source plist). A new
    CFBundleExecutable also renames the bundled executable, so the two always match.
    """

    executable_path = Path(executable_path).resolve()
    output_path = Path(output_path).resolve()
    overrides = overrides or {}

    if not executable_path.exists():
        raise FileNotFoundError(f"Executable not found: {executable_path}")

    app_name = overrides.get("CFBundleExecutable", executable_path.name)

    # Create bundle structure
    macos_dir = output_path / "Contents" / "MacOS"
    resources_dir = output_path / "Contents" / "Resources"
    macos_dir.mkdir(parents=True, exist_ok=True)
    resources_dir.mkdir(parents=True, exist_ok=True)

    # Copy executable
    target_executable = macos_dir / app_name
    shutil.copy2(executable_path, target_executable)
    target_executable.chmod(0o755)
    print(f"✅ Copied executable: {app_name}")

    # Copy Info.plist if provided, with any overridden keys
    if info_plist and Path(info_plist).exists():
        bundled_plist = output_path / "Contents" / "Info.plist"
        shutil.copy2(info_plist, bundled_plist)
        if overrides:
            with open(bundled_plist, "rb") as source:
                plist = plistlib.load(source)
            plist.update(overrides)
            with open(bundled_plist, "wb") as target:
                plistlib.dump(plist, target)
        print(f"✅ Copied Info.plist")

    # Copy icon if provided
    if icon_icns and Path(icon_icns).exists():
        shutil.copy2(icon_icns, resources_dir / "AppIcon.icns")
        print(f"✅ Copied app icon")

    print(f"✅ App bundle created: {output_path}")
    return output_path


def main():
    parser = argparse.ArgumentParser(description="Bundle Swift executable into macOS .app")
    parser.add_argument("--executable", required=True, help="Path to Swift executable")
    parser.add_argument("--output", required=True, help="Output .app bundle path")
    parser.add_argument("--info-plist", help="Path to Info.plist file")
    parser.add_argument("--icon", help="Path to AppIcon.icns file")
    # A second app from the same binary (the debug test library, S10.8 C1): its own identifier keeps
    # AppKit's saved state apart; its own names tell the two copies apart in the Dock and in pgrep.
    parser.add_argument("--bundle-id", help="Override CFBundleIdentifier")
    parser.add_argument("--bundle-name", help="Override CFBundleName")
    parser.add_argument("--executable-name", help="Override CFBundleExecutable (renames the bundled executable)")

    args = parser.parse_args()
    overrides = {
        key: value for key, value in (
            ("CFBundleIdentifier", args.bundle_id),
            ("CFBundleName", args.bundle_name),
            ("CFBundleExecutable", args.executable_name),
        ) if value
    }

    try:
        create_app_bundle(
            executable_path=args.executable,
            output_path=args.output,
            info_plist=args.info_plist,
            icon_icns=args.icon,
            overrides=overrides
        )
    except Exception as e:
        print(f"❌ Error: {e}")
        return 1

    return 0


if __name__ == "__main__":
    exit(main())
