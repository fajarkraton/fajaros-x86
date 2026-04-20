#!/usr/bin/env python3
"""
V30 Track 4 — Build deterministic ext2 / FAT32 test disk images.

Usage:
  build_test_disk.py --fs ext2  -o build/test-disks/ext2.img
  build_test_disk.py --fs fat32 -o build/test-disks/fat32.img
  build_test_disk.py --self-test

Manifest format: tests/test-disks/manifest.json. Files with
  content_ascii → UTF-8 encoded bytes
  content_hex   → hex-decoded bytes

Both images use the SAME manifest so a roundtrip test can expect
identical file contents across both filesystems.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST_PATH = REPO_ROOT / "tests" / "test-disks" / "manifest.json"


def load_manifest(path: Path = MANIFEST_PATH) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def resolve_content(entry: dict) -> bytes:
    if "content_ascii" in entry:
        return entry["content_ascii"].encode("utf-8")
    if "content_hex" in entry:
        return bytes.fromhex(entry["content_hex"])
    raise ValueError(f"manifest entry {entry['path']!r} has no content_ascii/hex")


def require_tool(name: str) -> str:
    path = shutil.which(name)
    if not path:
        sys.stderr.write(
            f"[ERR] {name} not found — install it (debian: "
            f"apt install e2fsprogs dosfstools mtools).\n"
        )
        sys.exit(2)
    return path


def make_blank_image(path: Path, size_mb: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as f:
        f.truncate(size_mb * 1024 * 1024)


def build_ext2(out: Path, manifest: dict) -> None:
    require_tool("mkfs.ext2")
    require_tool("debugfs")
    size_mb = manifest["size_mb"]
    make_blank_image(out, size_mb)

    subprocess.run(
        ["mkfs.ext2", "-F", "-q", "-L", "FJTEST", str(out)],
        check=True,
    )

    # Populate via debugfs — one command stream.
    cmds: list[str] = []
    created_dirs: set[str] = set()
    with tempfile.TemporaryDirectory() as tmpdir:
        for entry in manifest["files"]:
            disk_path = entry["path"]
            parent = os.path.dirname(disk_path)
            if parent and parent not in created_dirs:
                # Create intermediate dirs (only one level deep in manifest;
                # extend here if manifest grows).
                cmds.append(f"mkdir {parent}")
                created_dirs.add(parent)
            # Stage real file on host, then inject.
            host_file = Path(tmpdir) / disk_path.replace("/", "_")
            host_file.write_bytes(resolve_content(entry))
            cmds.append(f"write {host_file} {disk_path}")
        script = "\n".join(cmds) + "\n"
        subprocess.run(
            ["debugfs", "-w", "-f", "-", str(out)],
            input=script,
            text=True,
            check=True,
            # debugfs spams version banner to stderr — quiet it.
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def build_fat32(out: Path, manifest: dict) -> None:
    require_tool("mkfs.fat")
    require_tool("mcopy")
    require_tool("mmd")
    size_mb = manifest["size_mb"]
    # FAT32 needs at least 33 MB per the spec — grow if manifest is smaller.
    fat32_size = max(size_mb, 33)
    make_blank_image(out, fat32_size)

    subprocess.run(
        ["mkfs.fat", "-F", "32", "-n", "FJTEST", str(out)],
        check=True,
        stdout=subprocess.DEVNULL,
    )

    # Populate via mtools; disable config-file lookup for reproducibility.
    env = {**os.environ, "MTOOLS_SKIP_CHECK": "1"}
    mtools_cfg = f"drive x: file=\"{out}\" exclusive mformat_only\n"
    with tempfile.NamedTemporaryFile("w", suffix=".mtoolsrc", delete=False) as cfg:
        cfg.write(mtools_cfg)
        cfg_path = cfg.name
    env["MTOOLSRC"] = cfg_path

    try:
        created_dirs: set[str] = set()
        with tempfile.TemporaryDirectory() as tmpdir:
            for entry in manifest["files"]:
                disk_path = entry["path"].upper()
                parent = os.path.dirname(disk_path)
                if parent and parent not in created_dirs:
                    subprocess.run(
                        ["mmd", "-i", str(out), f"::/{parent}"],
                        check=True,
                        env=env,
                    )
                    created_dirs.add(parent)
                host_file = Path(tmpdir) / disk_path.replace("/", "_")
                host_file.write_bytes(resolve_content(entry))
                subprocess.run(
                    ["mcopy", "-i", str(out), str(host_file), f"::/{disk_path}"],
                    check=True,
                    env=env,
                )
    finally:
        os.unlink(cfg_path)


def self_test() -> int:
    """Build both images in a temp dir, verify file presence + byte
    round-trip. Exit 0 on pass, nonzero on failure."""
    require_tool("mkfs.ext2")
    require_tool("mkfs.fat")
    manifest = load_manifest()
    expected = {e["path"].upper(): resolve_content(e) for e in manifest["files"]}

    passed = 0
    total = 0

    with tempfile.TemporaryDirectory() as tmpdir:
        # ext2 — case-sensitive, use manifest paths as-is
        ext2_path = Path(tmpdir) / "ext2.img"
        build_ext2(ext2_path, manifest)
        for entry in manifest["files"]:
            total += 1
            want = resolve_content(entry)
            disk_path = entry["path"]
            cp = subprocess.run(
                ["debugfs", "-R", f"cat {disk_path}", str(ext2_path)],
                capture_output=True,
                check=False,
            )
            got = cp.stdout
            if got == want:
                passed += 1
            else:
                sys.stderr.write(
                    f"[FAIL] ext2 {disk_path}: want {want!r} got {got!r}\n"
                )

        # FAT32
        fat32_path = Path(tmpdir) / "fat32.img"
        build_fat32(fat32_path, manifest)
        env = {**os.environ, "MTOOLS_SKIP_CHECK": "1"}
        for disk_path, want in expected.items():
            total += 1
            host_copy = Path(tmpdir) / f"fat32-check-{total}"
            cp = subprocess.run(
                ["mcopy", "-i", str(fat32_path), f"::/{disk_path}", str(host_copy)],
                env=env,
                capture_output=True,
                check=False,
            )
            if cp.returncode != 0 or not host_copy.exists():
                sys.stderr.write(f"[FAIL] fat32 {disk_path}: mcopy rc={cp.returncode}\n")
                continue
            got = host_copy.read_bytes()
            if got == want:
                passed += 1
            else:
                sys.stderr.write(
                    f"[FAIL] fat32 {disk_path}: want {want!r} got {got!r}\n"
                )

    print(f"[self-test] {passed}/{total} passed")
    return 0 if passed == total else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--fs", choices=["ext2", "fat32"], help="filesystem type")
    ap.add_argument("-o", "--output", help="output image path")
    ap.add_argument(
        "--manifest",
        default=str(MANIFEST_PATH),
        help="manifest JSON path (default tests/test-disks/manifest.json)",
    )
    ap.add_argument("--self-test", action="store_true", help="run builder self-test")
    args = ap.parse_args()

    if args.self_test:
        return self_test()

    if not args.fs or not args.output:
        ap.error("--fs and -o required unless --self-test")

    manifest = load_manifest(Path(args.manifest))
    out = Path(args.output)
    if args.fs == "ext2":
        build_ext2(out, manifest)
    else:
        build_fat32(out, manifest)
    print(f"[OK] {args.fs} image written to {out} ({out.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
