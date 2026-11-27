#!/usr/bin/env python3
"""Generate one Sparkle appcast item after verifying its archive signature."""

import argparse
import base64
import binascii
from datetime import datetime, timezone
from email.utils import format_datetime
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
from urllib.parse import quote
import xml.etree.ElementTree as ET


SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)
SEMVER = re.compile(
    r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-((?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
    r"(?:\.(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*))?"
    r"(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
)
BUILD = re.compile(r"[1-9][0-9]*(?:\.(?:0|[1-9][0-9]*)){0,2}")
MIN_OS = re.compile(r"[1-9][0-9]*\.(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*))?")
REPOSITORY = re.compile(r"Wentao-Zhao/[A-Za-z0-9][A-Za-z0-9_.-]*")


class AppcastError(Exception):
    """An expected input, signing, or verification failure."""


def required_string(info, key):
    value = info.get(key)
    if not isinstance(value, str) or not value or value != value.strip():
        raise AppcastError(f"{key} must be a nonempty string without surrounding whitespace")
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        raise AppcastError(f"{key} contains control characters")
    return value


def decode_base64(value, length, label):
    try:
        decoded = base64.b64decode(value, validate=True)
    except (ValueError, binascii.Error) as error:
        raise AppcastError(f"{label} is not valid base64") from error
    if len(decoded) != length or base64.b64encode(decoded).decode("ascii") != value:
        raise AppcastError(f"{label} must be canonical base64 encoding of {length} bytes")
    return decoded


def run_tool(command, purpose):
    try:
        result = subprocess.run(command, capture_output=True, text=True, check=False)
    except (OSError, UnicodeError) as error:
        raise AppcastError(f"Cannot run {purpose}: {error}") from error
    if result.returncode != 0:
        # Do not echo signing-tool output: it is not needed to diagnose a failed step.
        raise AppcastError(f"{purpose} failed (exit {result.returncode})")
    return result.stdout.strip()


def verify_public_key(public_key, signature, archive, verify_tool):
    if verify_tool:
        run_tool(
            [str(verify_tool), public_key, signature, str(archive)],
            "independent embedded-public-key verification",
        )
        return
    try:
        from cryptography.exceptions import InvalidSignature
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    except ImportError as error:
        raise AppcastError(
            "Independent verification needs --verify-tool PATH or Python cryptography"
        ) from error
    try:
        Ed25519PublicKey.from_public_bytes(decode_base64(public_key, 32, "SUPublicEDKey")).verify(
            decode_base64(signature, 64, "signature"), archive.read_bytes()
        )
    except InvalidSignature as error:
        raise AppcastError("Signature does not match the app's embedded SUPublicEDKey") from error


def generate(args):
    app = args.app.resolve(strict=True)
    archive = args.dmg.resolve(strict=True)
    output = args.output.resolve()
    sign_tool = args.sign_tool.resolve(strict=True)
    verify_tool = args.verify_tool.resolve(strict=True) if args.verify_tool else None
    info_path = app / "Contents" / "Info.plist"
    if not app.is_dir() or not archive.is_file() or archive.suffix.lower() != ".dmg":
        raise AppcastError("--app must be an app directory and --dmg must be a regular .dmg file")
    if output in (archive, info_path.resolve()):
        raise AppcastError("--output must not overwrite the archive or app metadata")
    if not REPOSITORY.fullmatch(args.repo) or args.repo.split("/", 1)[1] in (".", ".."):
        raise AppcastError("--repo must have the form Wentao-Zhao/repository-name")
    if not args.key_account or args.key_account != args.key_account.strip():
        raise AppcastError("--key-account must be nonempty without surrounding whitespace")
    with info_path.open("rb") as source:
        info = plistlib.load(source)
    if not isinstance(info, dict):
        raise AppcastError("Info.plist must contain a dictionary")
    version = required_string(info, "CFBundleShortVersionString")
    build = required_string(info, "CFBundleVersion")
    minimum = required_string(info, "LSMinimumSystemVersion")
    name_key = "CFBundleDisplayName" if "CFBundleDisplayName" in info else "CFBundleName"
    name = required_string(info, name_key)
    public_key = required_string(info, "SUPublicEDKey")
    for label, value, pattern in (
        ("CFBundleShortVersionString", version, SEMVER),
        ("CFBundleVersion", build, BUILD),
        ("LSMinimumSystemVersion", minimum, MIN_OS),
    ):
        if not pattern.fullmatch(value):
            raise AppcastError(f"Malformed {label}")
    decode_base64(public_key, 32, "SUPublicEDKey")
    before = archive.stat()
    if before.st_size == 0:
        raise AppcastError("DMG archive must not be empty")
    signature = run_tool(
        [str(sign_tool), "--account", args.key_account, "-p", str(archive)],
        "archive signing",
    )
    decode_base64(signature, 64, "sign_update signature")
    run_tool(
        [str(sign_tool), "--account", args.key_account, "--verify", str(archive), signature],
        "sign_update verification",
    )
    verify_public_key(public_key, signature, archive, verify_tool)
    after = archive.stat()
    if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != (
        after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns
    ):
        raise AppcastError("DMG archive changed during signing or verification")

    tag = quote(f"v{version}", safe="")
    release = f"https://github.com/{args.repo}/releases/tag/{tag}"
    download = f"https://github.com/{args.repo}/releases/download/{tag}/{quote(args.dmg.name, safe='')}"
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = f"{name} Updates"
    ET.SubElement(channel, "link").text = f"https://github.com/{args.repo}/releases"
    ET.SubElement(channel, "description").text = f"Updates for {name}"
    ET.SubElement(channel, "language").text = "zh-CN"
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"{name} {version}"
    ET.SubElement(item, "link").text = release
    ET.SubElement(item, "pubDate").text = format_datetime(datetime.now(timezone.utc), usegmt=True)
    ET.SubElement(item, f"{{{SPARKLE}}}version").text = build
    ET.SubElement(item, f"{{{SPARKLE}}}shortVersionString").text = version
    ET.SubElement(item, f"{{{SPARKLE}}}minimumSystemVersion").text = minimum
    ET.SubElement(item, "enclosure", {
        "url": download,
        "length": str(after.st_size),
        "type": "application/octet-stream",
        f"{{{SPARKLE}}}edSignature": signature,
    })
    ET.indent(rss, space="  ")
    payload = ET.tostring(rss, encoding="utf-8", xml_declaration=True) + b"\n"
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix=f".{output.name}.", suffix=".tmp", dir=output.parent, delete=False) as target:
            temporary = Path(target.name)
            target.write(payload)
            target.flush()
            os.fsync(target.fileno())
        temporary.chmod(0o644)
        os.replace(temporary, output)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return name, version, build


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True, help="Packaged .app with Sparkle metadata")
    parser.add_argument("--dmg", type=Path, required=True, help="Final DMG release archive")
    parser.add_argument("--repo", required=True, help="GitHub repository, e.g. Wentao-Zhao/SystemMonitor")
    parser.add_argument("--sign-tool", type=Path, required=True, help="Sparkle sign_update executable")
    parser.add_argument("--key-account", required=True, help="Signing key's Keychain account name")
    parser.add_argument("--output", type=Path, required=True, help="Destination appcast.xml (replaced atomically)")
    parser.add_argument(
        "--verify-tool", type=Path,
        help="Independent verifier executable: PUBLICKEY_BASE64 SIGNATURE_BASE64 FILE; exit 0 on success. "
             "Defaults to Python cryptography Ed25519 verification.",
    )
    args = parser.parse_args()
    try:
        name, version, build = generate(args)
    except (AppcastError, OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(f"Wrote {args.output}: {name} {version} (build {build}); archive signature independently verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
