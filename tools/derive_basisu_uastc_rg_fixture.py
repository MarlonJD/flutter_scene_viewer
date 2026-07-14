#!/usr/bin/env python3
"""Derive the Plan 014 KHR_texture_basisu UASTC-RG fixture.

The pinned Khronos KTX-Software-CTS source contains an 8x8 UASTC payload
encoded from R8G8 input, but its generic KTX DFD uses BT709 primaries and the
UASTC_RRRG channel category. KHR_texture_basisu requires non-color RG data to
use UNSPECIFIED+LINEAR and UASTC_RG. This tool changes only those two DFD
bytes; the official compressed payload and every other container byte remain
unchanged.
"""

from __future__ import annotations

import argparse
import hashlib
import struct
import sys
from pathlib import Path


SOURCE_SHA256 = "318f68b48970fcdf76fbc407bfdc83a8afef6f611382f1283ff8106345b4a5d9"
OUTPUT_SHA256 = "602fcde544d7bb6c9272bea35f420c9fc9e76e2f7b182d7849dfa5d5bdde8bbd"
KTX2_IDENTIFIER = bytes.fromhex("ab4b5458203230bb0d0a1a0a")
SOURCE_LENGTH = 304
DFD_OFFSET = 104
DFD_LENGTH = 44
UASTC_MODEL = 166
BT709_PRIMARIES = 1
UNSPECIFIED_PRIMARIES = 0
LINEAR_TRANSFER = 1
UASTC_RRRG_CHANNEL = 5
UASTC_RG_CHANNEL = 6


class DerivationError(RuntimeError):
    pass


def _u32(data: bytes | bytearray, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def _sha256(data: bytes | bytearray) -> str:
    return hashlib.sha256(data).hexdigest()


def derive(source: bytes) -> bytes:
    if len(source) != SOURCE_LENGTH or _sha256(source) != SOURCE_SHA256:
        raise DerivationError("source byte identity does not match pinned Khronos CTS")
    if source[:12] != KTX2_IDENTIFIER:
        raise DerivationError("source is not KTX2")
    if (
        _u32(source, 12) != 0
        or _u32(source, 16) != 1
        or _u32(source, 20) != 8
        or _u32(source, 24) != 8
        or _u32(source, 40) != 1
        or _u32(source, 44) != 0
    ):
        raise DerivationError("source KTX2 header contract changed")
    if _u32(source, 48) != DFD_OFFSET or _u32(source, 52) != DFD_LENGTH:
        raise DerivationError("source DFD range changed")
    if tuple(source[DFD_OFFSET + 12 : DFD_OFFSET + 16]) != (
        UASTC_MODEL,
        BT709_PRIMARIES,
        LINEAR_TRANSFER,
        0,
    ):
        raise DerivationError("source DFD color contract changed")
    if source[DFD_OFFSET + 31] & 0x0F != UASTC_RRRG_CHANNEL:
        raise DerivationError("source DFD channel contract changed")

    derived = bytearray(source)
    derived[DFD_OFFSET + 13] = UNSPECIFIED_PRIMARIES
    derived[DFD_OFFSET + 31] = (
        derived[DFD_OFFSET + 31] & 0xF0
    ) | UASTC_RG_CHANNEL
    if _sha256(derived) != OUTPUT_SHA256:
        raise DerivationError("derived byte identity changed")
    changed_offsets = [
        index for index, (left, right) in enumerate(zip(source, derived)) if left != right
    ]
    if changed_offsets != [DFD_OFFSET + 13, DFD_OFFSET + 31]:
        raise DerivationError("derivation changed bytes outside the two DFD fields")
    return bytes(derived)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--write", action="store_true")
    action.add_argument("--check", action="store_true")
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)

    try:
        derived = derive(args.source.read_bytes())
        if args.write:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_bytes(derived)
            print(f"wrote {args.output} sha256={OUTPUT_SHA256}")
        else:
            if not args.output.is_file() or args.output.read_bytes() != derived:
                raise DerivationError("derived output is absent or stale")
            print(f"verified {args.output} sha256={OUTPUT_SHA256}")
    except (OSError, DerivationError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
