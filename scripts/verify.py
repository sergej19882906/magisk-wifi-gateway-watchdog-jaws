#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import re
import stat
from pathlib import Path, PurePosixPath
from zipfile import ZIP_STORED, ZipFile

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
FORBIDDEN = (
    "settings put",
    "resetprop",
    "setprop",
    "ctl.restart",
    " reboot",
    "rmmod",
    "modprobe",
    "insmod",
    "ip link set",
    "power_save off",
    "power_save on",
    "service.adb.",
    "ro.boot.otg_device",
    "gpio474",
    "sys.usb",
    "usb_gadget",
    "/data/misc/wifi",
    "8.8.8.8",
    "1.1.1.1",
    "set-wifi-enabled",
)


def fail(message: str) -> None:
    raise SystemExit(f"verification failed: {message}")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def metadata() -> dict[str, str]:
    values: dict[str, str] = {}
    for line in (MODULE / "module.prop").read_text(encoding="utf-8").splitlines():
        if not line or "=" not in line:
            fail("invalid module.prop")
        key, value = line.split("=", 1)
        if key in values:
            fail(f"duplicate metadata key: {key}")
        values[key] = value
    if values.get("id") != "wifi_gateway_watchdog_jaws":
        fail("unexpected module id")
    if values.get("author") != "sergej19882906":
        fail("unexpected author")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", values.get("version", "")):
        fail("invalid semantic version")
    if not values.get("versionCode", "").isdigit():
        fail("invalid versionCode")
    return values


def verify_sources() -> None:
    scripts = "\n".join(
        path.read_text(encoding="utf-8") for path in MODULE.rglob("*.sh")
    ).lower()
    for token in FORBIDDEN:
        if token in scripts:
            fail(f"forbidden operation in module scripts: {token}")
    if scripts.count("wifi trigger-recovery") != 1:
        fail("unexpected Wi-Fi recovery command count")

    for name, source, _ in FILES:
        data = source.read_bytes()
        if data.startswith(b"\xef\xbb\xbf") or b"\r" in data:
            fail(f"invalid text encoding: {source.relative_to(ROOT)}")
        if data and not data.endswith(b"\n"):
            fail(f"missing final newline: {source.relative_to(ROOT)}")
        if name.endswith(".sh") and not data.startswith(b"#!/system/bin/sh\n"):
            fail(f"invalid shebang: {source.relative_to(ROOT)}")


def verify_zip(version: str) -> Path:
    archive_path = DIST / f"magisk-wifi-gateway-watchdog-jaws-v{version}.zip"
    expected_names = [entry[0] for entry in FILES]
    with ZipFile(archive_path) as archive:
        infos = archive.infolist()
        if [info.filename for info in infos] != expected_names:
            fail("unexpected ZIP entries or order")
        for info, (name, source, mode) in zip(infos, FILES, strict=True):
            path = PurePosixPath(info.filename)
            if path.is_absolute() or ".." in path.parts or "\\" in info.filename:
                fail(f"unsafe ZIP path: {info.filename}")
            if info.create_system != 3 or info.date_time != FIXED_TIMESTAMP:
                fail(f"non-reproducible metadata: {info.filename}")
            if info.compress_type != ZIP_STORED:
                fail(f"unexpected compression: {info.filename}")
            raw_mode = info.external_attr >> 16
            if stat.S_IFMT(raw_mode) != stat.S_IFREG or stat.S_IMODE(raw_mode) != mode:
                fail(f"wrong Unix mode: {info.filename}")
            if archive.read(name) != source.read_bytes():
                fail(f"content mismatch: {info.filename}")
    return archive_path


def main() -> None:
    verify_sources()
    values = metadata()
    archive_path = verify_zip(values["version"])
    digest = sha256(archive_path)
    expected = f"{digest}  {archive_path.name}\n"
    if (DIST / "SHA256SUMS").read_text(encoding="utf-8") != expected:
        fail("SHA256SUMS mismatch")
    print(f"Verified {archive_path.relative_to(ROOT)}")
    print(f"SHA-256 {digest}")


if __name__ == "__main__":
    main()
