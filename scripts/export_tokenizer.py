#!/usr/bin/env python3
"""
export_tokenizer.py — Export HuggingFace tokenizer to .fjt (Fajar Token) binary format.

Usage:
    # Create tiny test tokenizer (256 byte tokens + 50 common words):
    python export_tokenizer.py --test -o test.fjt

    # Export SmolLM tokenizer:
    python export_tokenizer.py --model HuggingFaceTB/SmolLM-135M -o smollm.fjt

    # Write to NVMe disk image:
    python export_tokenizer.py --test -o test.fjt --write-disk ../disk.img --lba 1000

.fjt format:
    Header (32 bytes):
        magic:     "FJT1" (4B)
        version:   1 (4B)
        vocab_size: N (4B)
        max_len:   M (4B)
        reserved:  16B

    Entries (16 bytes each, sorted by first byte then length descending):
        len:   u8 (1B)
        bytes: u8[15] (15B, zero-padded)

Author: Muhamad Fajar Putranto, SE., SH., MH. (TaxPrime / PrimeCore.id)
"""

import argparse
import struct
import sys
from pathlib import Path

FJT_MAGIC = 0x314D4A46  # Note: actual bytes are "FJT1" = 0x46,0x4A,0x54,0x31
FJT_MAGIC_BYTES = b"FJT1"
FJT_HEADER_SIZE = 32
FJT_ENTRY_SIZE = 16
FJT_MAX_TOKEN_BYTES = 15


def create_test_tokenizer() -> bytes:
    """Create a small test tokenizer: 256 byte-level + 50 common words."""
    tokens = []

    # 256 byte-level tokens (ID 0-255)
    for i in range(256):
        tokens.append(bytes([i]))

    # Common English subwords/words
    common = [
        b" the", b" and", b" of", b" to", b" in", b" is",
        b"hello", b"world", b"the", b"ing", b"tion",
        b" a", b"er", b"ed", b"es", b"th", b"an", b"in",
        b"on", b"re", b" for", b" with", b" that", b" this",
        b" not", b" but", b" are", b" was", b" have", b" from",
        b" be", b" at", b" or", b" by", b" it", b" on",
        b" you", b" can", b" we", b" he", b" she", b" do",
        b" my", b" no", b" so", b" up", b" if", b" me",
        b" his", b" her",
    ]
    tokens.extend(common)

    return build_fjt(tokens)


def export_huggingface(model_name: str) -> bytes:
    """Export a HuggingFace tokenizer to .fjt format."""
    try:
        from transformers import AutoTokenizer
    except ImportError:
        print("ERROR: pip install transformers")
        sys.exit(1)

    print(f"Loading tokenizer for {model_name}...")
    tokenizer = AutoTokenizer.from_pretrained(model_name)
    vocab = tokenizer.get_vocab()

    tokens = []
    for token_str, token_id in sorted(vocab.items(), key=lambda x: x[1]):
        # Convert token string to bytes
        # SentencePiece uses \u2581 (▁) for space prefix
        token_bytes = token_str.replace("\u2581", " ").encode("utf-8", errors="replace")
        if len(token_bytes) > FJT_MAX_TOKEN_BYTES:
            token_bytes = token_bytes[:FJT_MAX_TOKEN_BYTES]
        tokens.append(token_bytes)

    print(f"Vocab size: {len(tokens)}")
    return build_fjt(tokens)


def build_fjt(tokens: list) -> bytes:
    """Build .fjt binary from list of token byte sequences."""
    vocab_size = len(tokens)
    max_len = max(len(t) for t in tokens)
    if max_len > FJT_MAX_TOKEN_BYTES:
        max_len = FJT_MAX_TOKEN_BYTES

    # Sort by first byte, then by length descending (for greedy longest-match)
    indexed = list(enumerate(tokens))
    indexed.sort(key=lambda x: (x[1][0] if x[1] else 0, -len(x[1])))

    # Build header
    header = struct.pack("<4sIIII",
        FJT_MAGIC_BYTES, 1, vocab_size, max_len, 0)
    header += b"\x00" * (FJT_HEADER_SIZE - len(header))

    # Build entries (in sorted order — IDs are positional)
    entries = b""
    for orig_id, token_bytes in indexed:
        tok_len = min(len(token_bytes), FJT_MAX_TOKEN_BYTES)
        entry = bytes([tok_len]) + token_bytes[:tok_len]
        entry += b"\x00" * (FJT_ENTRY_SIZE - len(entry))
        entries += entry

    fjt = header + entries
    total = len(fjt)

    print(f"Tokenizer: {vocab_size} tokens, max_len={max_len}")
    print(f"Total size: {total} bytes ({total/1024:.1f} KB)")

    # Print first-byte index stats
    fb_counts = {}
    for _, t in indexed:
        fb = t[0] if t else 0
        fb_counts[fb] = fb_counts.get(fb, 0) + 1
    printable = sum(1 for fb in fb_counts if 32 <= fb < 127)
    print(f"First-byte buckets: {len(fb_counts)} ({printable} printable)")

    return fjt


def write_to_disk(data: bytes, disk_path: str, lba: int):
    """Write data to raw disk image at given LBA."""
    offset = lba * 512
    disk = Path(disk_path)
    if not disk.exists():
        print(f"Creating disk image: {disk_path} (64MB)")
        with open(disk_path, "wb") as f:
            f.write(b"\x00" * 64 * 1024 * 1024)

    with open(disk_path, "r+b") as f:
        f.seek(offset)
        f.write(data)
        remainder = len(data) % 512
        if remainder:
            f.write(b"\x00" * (512 - remainder))

    sectors = (len(data) + 511) // 512
    print(f"Written to {disk_path} at LBA {lba} ({sectors} sectors)")


def main():
    parser = argparse.ArgumentParser(description="Export tokenizer to .fjt format")
    parser.add_argument("--model", type=str, help="HuggingFace model name")
    parser.add_argument("--test", action="store_true", help="Create test tokenizer")
    parser.add_argument("-o", "--output", type=str, required=True, help="Output .fjt file")
    parser.add_argument("--write-disk", type=str, help="Write to raw disk image")
    parser.add_argument("--lba", type=int, default=0, help="Start LBA for disk write")
    args = parser.parse_args()

    if args.test:
        fjt = create_test_tokenizer()
    elif args.model:
        fjt = export_huggingface(args.model)
    else:
        parser.error("Specify --model or --test")

    with open(args.output, "wb") as f:
        f.write(fjt)
    print(f"Saved: {args.output}")

    if args.write_disk:
        write_to_disk(fjt, args.write_disk, args.lba)


if __name__ == "__main__":
    main()
