#!/usr/bin/python3
"""Package and register Focus Guard's local browser extensions."""

import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


HOST_NAME = "io.github.danielsintimbrean.focus_guard"
HOST_PATH = Path("/usr/local/bin/focus-guard-browser-host")
MOZILLA_HOST_DIR = Path("/usr/lib/mozilla/native-messaging-hosts")
CHROMIUM_HOST_DIR = Path("/etc/chromium/native-messaging-hosts")
CHROMIUM_EXTENSION_DIR = Path("/usr/share/chromium/extensions")
CHROMIUM_PACKAGE_DIR = Path("/usr/share/focus-guard")
STATE_DIR = Path("/var/lib/focus-guard")
CHROMIUM_KEY = STATE_DIR / "chromium-browser-extension.pem"
CHROMIUM_ID_FILE = STATE_DIR / "chromium-browser-extension.id"
COMMON_FILES = ("background.js", "blocked.html", "blocked.css", "blocked.js", "rules.json")
CHROMIUM_ID_PATTERN = re.compile(r"^[a-p]{32}$")


def source_dir():
    return Path(__file__).resolve().parent.parent / "browser-extension"


def write_json(path, contents):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8") as output:
        json.dump(contents, output, indent=2)
        output.write("\n")
    os.chmod(temporary, 0o644)
    temporary.replace(path)


def build_firefox_package(source, app_dir):
    manifest = json.loads((source / "firefox" / "manifest.json").read_text(encoding="utf-8"))
    extension_id = manifest["browser_specific_settings"]["gecko"]["id"]
    extension_dir = app_dir / "distribution" / "extensions"
    package_path = extension_dir / f"{extension_id}.xpi"
    temporary = package_path.with_suffix(".xpi.tmp")
    extension_dir.mkdir(parents=True, exist_ok=True)

    try:
        with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED) as package:
            package.write(source / "firefox" / "manifest.json", "manifest.json")
            for filename in COMMON_FILES:
                package.write(source / filename, filename)
        os.chmod(temporary, 0o644)
        temporary.replace(package_path)
    finally:
        temporary.unlink(missing_ok=True)

    return extension_id, package_path


def chromium_extension_id(private_key):
    public_key = subprocess.run(
        ["openssl", "pkey", "-in", str(private_key), "-pubout", "-outform", "DER"],
        capture_output=True,
        check=True,
    ).stdout
    digest = hashlib.sha256(public_key).digest()[:16]
    return "".join(chr(ord("a") + nibble) for byte in digest for nibble in (byte >> 4, byte & 0x0F))


def find_zen_app_dir():
    for command in ("zen-browser", "zen"):
        executable = shutil.which(command)
        if not executable:
            continue

        candidates = [Path(executable).resolve()]
        try:
            wrapper = Path(executable).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            wrapper = ""
        for line in wrapper.splitlines():
            try:
                parts = shlex.split(line.strip())
            except ValueError:
                continue
            if len(parts) >= 2 and parts[0] == "exec" and parts[1].startswith("/"):
                candidates.append(Path(parts[1]).resolve())

        for candidate in candidates:
            for parent in (candidate.parent, *candidate.parents[:4]):
                if (parent / "distribution").is_dir():
                    return parent
    return None


def install_mozilla(source):
    app_dir = find_zen_app_dir()
    if app_dir is None:
        return False

    extension_id, extension_path = build_firefox_package(source, app_dir)
    host_manifest = {
        "name": HOST_NAME,
        "description": "Read Focus Guard's current state",
        "path": str(HOST_PATH),
        "type": "stdio",
        "allowed_extensions": [extension_id],
    }
    write_json(MOZILLA_HOST_DIR / f"{HOST_NAME}.json", host_manifest)
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    state_path = STATE_DIR / "zen-browser-extension.path"
    state_path.write_text(f"{extension_path}\n", encoding="utf-8")
    os.chmod(state_path, 0o600)
    return True


def build_chromium_package(source, chromium):
    old_id = ""
    try:
        old_id = CHROMIUM_ID_FILE.read_text(encoding="ascii").strip()
    except OSError:
        pass

    CHROMIUM_PACKAGE_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="focus-guard-extension-") as temporary_root:
        temporary_root = Path(temporary_root)
        package_source = temporary_root / "extension"
        package_source.mkdir()
        shutil.copyfile(source / "chromium" / "manifest.json", package_source / "manifest.json")
        for filename in COMMON_FILES:
            shutil.copyfile(source / filename, package_source / filename)

        command = [
            chromium,
            "--no-sandbox",
            "--headless",
            "--disable-gpu",
            f"--user-data-dir={temporary_root / 'profile'}",
            f"--pack-extension={package_source}",
        ]
        if CHROMIUM_KEY.is_file():
            command.append(f"--pack-extension-key={CHROMIUM_KEY}")

        subprocess.run(command, capture_output=True, check=True, timeout=60)
        packed_extension = Path(f"{package_source}.crx")
        generated_key = Path(f"{package_source}.pem")
        if not CHROMIUM_KEY.is_file():
            if not generated_key.is_file():
                raise RuntimeError("Chromium did not create the extension signing key")
            CHROMIUM_KEY.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(generated_key, CHROMIUM_KEY)
            os.chmod(CHROMIUM_KEY, 0o600)

        extension_id = chromium_extension_id(CHROMIUM_KEY)
        manifest = json.loads((source / "chromium" / "manifest.json").read_text(encoding="utf-8"))
        target_package = CHROMIUM_PACKAGE_DIR / "focus-guard.crx"
        temporary_package = target_package.with_suffix(".crx.tmp")
        shutil.copyfile(packed_extension, temporary_package)
        os.chmod(temporary_package, 0o644)
        temporary_package.replace(target_package)

    CHROMIUM_EXTENSION_DIR.mkdir(parents=True, exist_ok=True)
    if old_id and old_id != extension_id and CHROMIUM_ID_PATTERN.fullmatch(old_id):
        (CHROMIUM_EXTENSION_DIR / f"{old_id}.json").unlink(missing_ok=True)

    external_extension = {
        "external_crx": str(CHROMIUM_PACKAGE_DIR / "focus-guard.crx"),
        "external_version": manifest["version"],
    }
    write_json(CHROMIUM_EXTENSION_DIR / f"{extension_id}.json", external_extension)
    CHROMIUM_ID_FILE.parent.mkdir(parents=True, exist_ok=True)
    CHROMIUM_ID_FILE.write_text(f"{extension_id}\n", encoding="ascii")
    os.chmod(CHROMIUM_ID_FILE, 0o600)

    host_manifest = {
        "name": HOST_NAME,
        "description": "Read Focus Guard's current state",
        "path": str(HOST_PATH),
        "type": "stdio",
        "allowed_origins": [f"chrome-extension://{extension_id}/"],
    }
    write_json(CHROMIUM_HOST_DIR / f"{HOST_NAME}.json", host_manifest)


def main():
    if os.geteuid() != 0:
        print("Browser integration setup needs administrator privileges.", file=sys.stderr)
        return 1

    source = source_dir()
    host_source = Path(__file__).with_name("focus-guard-browser-host.py")
    shutil.copyfile(host_source, HOST_PATH)
    os.chmod(HOST_PATH, 0o755)

    installed = []
    failures = []
    try:
        if install_mozilla(source):
            installed.append("Zen Browser")
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        failures.append(f"Zen Browser page setup failed: {error}")

    chromium = shutil.which("chromium")
    if chromium:
        try:
            build_chromium_package(source, chromium)
            installed.append("Chromium")
        except (OSError, subprocess.SubprocessError, ValueError, RuntimeError) as error:
            failures.append(f"Chromium page setup failed: {error}")

    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1

    if installed:
        browsers = " and ".join(installed)
        print(f"Browser focus page installed for {browsers}. Restart {browsers} to load it.")
    else:
        print("No Zen Browser or Chromium installation was found; skipped the browser focus page.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
