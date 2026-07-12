#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

BINARY_SUFFIXES = {".gz", ".zip", ".bz2", ".xz", ".7z", ".sqlite", ".db", ".bin"}
PART_PATTERN = re.compile(r"\.part\d{4}(?:\.|$)")

def part_path(source: Path, index: int) -> Path:
    return source.with_name(f"{source.stem}.part{index:04d}{source.suffix}")

def remove_existing_parts(source: Path) -> None:
    for part in source.parent.glob(f"{source.stem}.part*{source.suffix}"):
        part.unlink()

def split_binary(source: Path, max_bytes: int) -> list[Path]:
    parts = []
    with source.open("rb") as reader:
        index = 1
        while True:
            chunk = reader.read(max_bytes)
            if not chunk:
                break
            destination = part_path(source, index)
            destination.write_bytes(chunk)
            parts.append(destination)
            index += 1
    return parts

def split_lines(source: Path, max_bytes: int) -> list[Path]:
    parts = []
    writer = None
    current_size = 0
    index = 1
    try:
        with source.open("rb") as reader:
            for line in reader:
                if len(line) > max_bytes:
                    raise ValueError(f"one line is larger than max-bytes in {source}")
                if writer is None or (current_size and current_size + len(line) > max_bytes):
                    if writer is not None:
                        writer.close()
                    destination = part_path(source, index)
                    writer = destination.open("wb")
                    parts.append(destination)
                    current_size = 0
                    index += 1
                writer.write(line)
                current_size += len(line)
    finally:
        if writer is not None:
            writer.close()
    return parts

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--max-bytes", required=True, type=int)
    args = parser.parse_args()

    root = args.root.expanduser().resolve()
    if not root.is_dir() or args.max_bytes <= 0:
        print("ERROR: invalid root or max-bytes", file=sys.stderr)
        return 2

    candidates = [
        path for path in sorted(root.rglob("*"))
        if path.is_file()
        and path.stat().st_size > args.max_bytes
        and PART_PATTERN.search(path.name) is None
    ]

    for source in candidates:
        binary_mode = source.suffix.lower() in BINARY_SUFFIXES
        print(f"Splitting: {source} mode={'binary' if binary_mode else 'line-safe'}")
        remove_existing_parts(source)
        try:
            parts = (
                split_binary(source, args.max_bytes)
                if binary_mode
                else split_lines(source, args.max_bytes)
            )
            if not parts:
                raise RuntimeError(f"no parts created for {source}")
            oversized = [p for p in parts if p.stat().st_size > args.max_bytes]
            if oversized:
                raise RuntimeError(f"oversized parts remain: {oversized}")
            source.unlink()
        except Exception:
            remove_existing_parts(source)
            raise

        for part in parts:
            print(f"Created: {part} size={part.stat().st_size}")

        if binary_mode:
            print(
                f"Reassemble from {source.parent}: "
                f"cat '{source.stem}.part*{source.suffix}' > '{source.name}'"
            )

    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
