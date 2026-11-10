#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import os
import re
import stat
import tempfile
from pathlib import Path
from zipfile import ZIP_STORED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parent.parent
MODULE = ROOT / "module"
DIST = ROOT / "dist"
FIXED_TIMESTAMP = (1980, 1, 1, 0, 0, 0)
FILES = (
    ("customize.sh", MODULE / "customize.sh", 0o755),
    ("LICENSE", ROOT / "LICENSE", 0o644),
    ("lib/watchdog-policy.sh", MODULE / "lib" / "watchdog-policy.sh", 0o644),
    ("module.prop", MODULE / "module.prop", 0o644),
    ("service.sh", MODULE / "service.sh", 0o755),
    ("skip_mount", MODULE / "skip_mount", 0o644),
    ("uninstall.sh", MODULE / "uninstall.sh", 0o755),
)


def module_version() -> str:
    metadata = (MODULE / "module.prop").read_text(encoding="utf-8")
    match = re.search(r"^version=([0-9]+\.[0-9]+\.[0-9]+)$", metadata, re.MULTILINE)
    if match is None:
        raise SystemExit("module.prop must contain a semantic version")
    return match.group(1)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_source(path: Path) -> bytes:
    data = path.read_bytes()
    if data.startswith(b"\xef\xbb\xbf"):
        raise SystemExit(f"UTF-8 BOM is not allowed: {path.relative_to(ROOT)}")
    if b"\r" in data:
        raise SystemExit(f"CRLF is not allowed: {path.relative_to(ROOT)}")
    if data and not data.endswith(b"\n"):
        raise SystemExit(f"final newline is required: {path.relative_to(ROOT)}")
    return data


def build() -> Path:
    version = module_version()
    DIST.mkdir(exist_ok=True)
    output = DIST / f"magisk-wifi-gateway-watchdog-jaws-v{version}.zip"

    with tempfile.NamedTemporaryFile(dir=DIST, delete=False) as temporary:
        temporary_path = Path(temporary.name)

    try:
        with ZipFile(temporary_path, "w", compression=ZIP_STORED) as archive:
            for archive_name, source, mode in FILES:
                info = ZipInfo(archive_name, date_time=FIXED_TIMESTAMP)
                info.create_system = 3
                info.compress_type = ZIP_STORED
                info.external_attr = (stat.S_IFREG | mode) << 16
                archive.writestr(info, validate_source(source))
        os.replace(temporary_path, output)
    finally:
        temporary_path.unlink(missing_ok=True)

    checksum = sha256(output)
    (DIST / "SHA256SUMS").write_text(
        f"{checksum}  {output.name}\n", encoding="utf-8", newline="\n"
    )
    print(f"Built {output.relative_to(ROOT)}")
    print(f"SHA-256 {checksum}")
    return output


if __name__ == "__main__":
    build()
