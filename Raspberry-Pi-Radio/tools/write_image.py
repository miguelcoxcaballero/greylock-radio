#!/usr/bin/env python3
"""Stream an xz-compressed Raspberry Pi image to a Windows physical disk."""

from __future__ import annotations

import argparse
import lzma
import os
import sys
import time
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    parser.add_argument("device", help=r"Windows device path such as \\.\PhysicalDrive2")
    parser.add_argument(
        "--defer-header",
        type=int,
        default=0,
        help="Write this many leading bytes last so Windows does not mount a half-written partition",
    )
    args = parser.parse_args()

    compressed_size = args.image.stat().st_size
    copied = 0
    started = time.monotonic()
    flags = os.O_WRONLY | getattr(os, "O_BINARY", 0)

    print(f"Writing {args.image.name} to {args.device}", flush=True)
    destination = os.open(args.device, flags)
    try:
        with lzma.open(args.image, "rb") as source:
            deferred_header = source.read(args.defer_header) if args.defer_header else b""
            if deferred_header:
                os.lseek(destination, len(deferred_header), os.SEEK_SET)
                copied = len(deferred_header)
            while True:
                block = source.read(4 * 1024 * 1024)
                if not block:
                    break
                view = memoryview(block)
                while view:
                    written = os.write(destination, view)
                    view = view[written:]
                copied += len(block)
                elapsed = max(time.monotonic() - started, 0.1)
                print(
                    f"\rWritten {copied / (1024 ** 3):.2f} GiB "
                    f"at {copied / elapsed / (1024 ** 2):.1f} MiB/s",
                    end="",
                    flush=True,
                )
            if deferred_header:
                os.lseek(destination, 0, os.SEEK_SET)
                view = memoryview(deferred_header)
                while view:
                    written = os.write(destination, view)
                    view = view[written:]
        try:
            os.fsync(destination)
        except OSError:
            pass
    finally:
        os.close(destination)

    print(f"\nFinished. Compressed source size: {compressed_size / (1024 ** 2):.1f} MiB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
