#!/usr/bin/env python3
"""
Bundle Swift executable into macOS .app format.

Usage:
    python3 scripts/bundle-app.py --executable .build/debug/AdaptiveSound --output .build/debug/AdaptiveSound.app
"""

import argparse
import shutil
import subprocess
from pathlib import Path


def create_app_bundle(executable_path: Path, output_path: Path, info_plist: Path = None, icon_icns: Path = None):
    """Create a macOS .app bundle from an executable."""

    executable_path = Path(executable_path).resolve()
    output_path = Path(output_path).resolve()

    if not executable_path.exists():
        raise FileNotFoundError(f"Executable not found: {executable_path}")

    app_name = executable_path.name

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

    # Copy Info.plist if provided
    if info_plist and Path(info_plist).exists():
        shutil.copy2(info_plist, output_path / "Contents" / "Info.plist")
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

    args = parser.parse_args()

    try:
        create_app_bundle(
            executable_path=args.executable,
            output_path=args.output,
            info_plist=args.info_plist,
            icon_icns=args.icon
        )
    except Exception as e:
        print(f"❌ Error: {e}")
        return 1

    return 0


if __name__ == "__main__":
    exit(main())
