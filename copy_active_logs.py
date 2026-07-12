#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import shutil
import sys
from pathlib import Path

CHUNK_SIZE = 1024 * 1024

def copy_active_file(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with source.open("rb") as src, destination.open("wb") as dst:
        shutil.copyfileobj(src, dst, length=CHUNK_SIZE)
    stat = source.stat()
    os.utime(destination, ns=(stat.st_atime_ns, stat.st_mtime_ns))

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--destination", required=True, type=Path)
    args = parser.parse_args()

    source_root = args.source.expanduser().resolve()
    destination_root = args.destination.expanduser().resolve()

    if not source_root.is_dir():
        print(f"ERROR: source does not exist: {source_root}", file=sys.stderr)
        return 2

    destination_root.mkdir(parents=True, exist_ok=True)
    copied = 0
    warnings = 0

    for source_path in sorted(source_root.rglob("*")):
        if not source_path.is_file():
            continue
        destination_path = destination_root / source_path.relative_to(source_root)
        try:
            print(f"Copying: {source_path} -> {destination_path}")
            copy_active_file(source_path, destination_path)
            copied += 1
        except (FileNotFoundError, PermissionError, OSError) as exc:
            warnings += 1
            print(f"WARNING: failed to copy {source_path}: {exc}", file=sys.stderr)

    print(f"Copy complete: copied={copied} warnings={warnings}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
