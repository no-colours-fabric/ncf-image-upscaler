#!/usr/bin/env python3
"""Explicit release build/download command. All artifacts live in Application Support."""

import base64
import csv
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import tomllib
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
APP_HOME = (
    Path(
        os.environ.get(
            "NCF_IMAGE_UPSCALER_HOME",
            Path.home() / "Library/Application Support/ncf-image-upscaler",
        )
    )
    .expanduser()
    .resolve()
)
UV = APP_HOME / "runtime/tooling/bin/uv"
VERSION = tomllib.loads((ROOT / "pyproject.toml").read_text())["project"]["version"]
BUILD = APP_HOME / "runtime/release-build" / VERSION
OUTPUT = APP_HOME / "runtime/releases" / VERSION
ENV = {
    **os.environ,
    "UV_CACHE_DIR": str(APP_HOME / "cache/uv"),
    "UV_PYTHON_DOWNLOADS": "never",
    "PYTHONDONTWRITEBYTECODE": "1",
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
}
MACHO = {
    b"\xcf\xfa\xed\xfe",
    b"\xce\xfa\xed\xfe",
    b"\xfe\xed\xfa\xcf",
    b"\xfe\xed\xfa\xce",
    b"\xca\xfe\xba\xbe",
    b"\xbe\xba\xfe\xca",
}


def run(*args, **kwargs):
    subprocess.run([str(arg) for arg in args], env=ENV, check=True, **kwargs)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def download_python(spec):
    directory = APP_HOME / "cache/release-downloads"
    directory.mkdir(parents=True, exist_ok=True)
    suffix = ".tar.zst" if spec["url"].endswith(".tar.zst") else ".tar.gz"
    archive = directory / (spec["sha256"] + suffix)
    if (
        archive.is_file()
        and archive.stat().st_size == spec["size"]
        and digest(archive) == spec["sha256"]
    ):
        return archive
    temporary = archive.with_suffix(".download")
    try:
        print("Downloading a pinned standalone Python build artifact…", flush=True)
        with (
            urlopen(
                Request(spec["url"], headers={"User-Agent": "ncf-image-upscaler-release-builder"}),
                timeout=60,
            ) as source,
            temporary.open("wb") as target,
        ):
            size = 0
            while chunk := source.read(1024 * 1024):
                size += len(chunk)
                if size > spec["size"]:
                    raise RuntimeError("Unexpected Python archive size")
                target.write(chunk)
        if temporary.stat().st_size != spec["size"] or digest(temporary) != spec["sha256"]:
            raise RuntimeError("Python archive integrity verification failed")
        temporary.replace(archive)
    finally:
        temporary.unlink(missing_ok=True)
    return archive


def prepare_runtime(spec):
    archive = download_python(spec)
    with tarfile.open(archive, "r:gz") as bundle:
        bundle.extractall(BUILD, filter="data")
    runtime = BUILD / "python"
    python = runtime / "bin/python3"
    requirements = BUILD / "requirements.txt"
    run(
        UV,
        "export",
        "--locked",
        "--no-dev",
        "--no-emit-project",
        "--format",
        "requirements-txt",
        "--output-file",
        requirements,
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
    )
    print("Installing locked runtime dependencies…", flush=True)
    run(
        UV,
        "pip",
        "install",
        "--python",
        python,
        "--break-system-packages",
        "--no-deps",
        "--require-hashes",
        "--python-platform",
        "aarch64-apple-darwin",
        "--only-binary",
        ":all:",
        "-r",
        requirements,
    )
    wheels = BUILD / "wheels"
    run(
        UV,
        "build",
        "--wheel",
        "--no-sources",
        "--python",
        sys.executable,
        "--out-dir",
        wheels,
        cwd=ROOT,
    )
    wheel = next(wheels.glob("*.whl"))
    run(UV, "pip", "install", "--python", python, "--break-system-packages", "--no-deps", wheel)
    for script in (runtime / "bin").iterdir():
        if script.is_file() and not script.is_symlink():
            data = script.read_bytes()
            lines = data.splitlines(keepends=True)
            python_script = lines and lines[0].startswith(b"#!") and b"python" in lines[0]
            trampoline = (
                len(lines) >= 3
                and lines[1].startswith(b"'''exec'")
                and lines[2].strip() == b"' '''"
            )
            if python_script or trampoline:
                body = b"".join(lines[3:] if trampoline else lines[1:])
                script.write_bytes(
                    b"#!/bin/sh\n'''exec' \"${0%/*}/python3\" -I -B \"$0\" \"$@\"\n' '''\n" + body
                )
    for origin in runtime.glob("lib/python*/site-packages/*.dist-info/direct_url.json"):
        origin.unlink()  # Build-machine wheel paths are not useful in a portable distribution.
    # Never ship bytecode containing paths from the build machine.
    for cache in list(runtime.rglob("__pycache__")):
        shutil.rmtree(cache)
    for bytecode in runtime.rglob("*.pyc"):
        bytecode.unlink()
    # Wheels and the standalone interpreter must remain relocatable.
    print("Checking dynamic libraries and applying local signatures…", flush=True)
    count = 0
    for path in sorted(runtime.rglob("*")):
        if path.is_symlink():
            if not path.resolve().is_relative_to(runtime.resolve()):
                raise RuntimeError(f"External runtime symlink: {path.relative_to(runtime)}")
            continue
        if not path.is_file():
            continue
        if path.suffix == ".safetensors":
            raise RuntimeError("Model weights must not be bundled")
        with path.open("rb") as stream:
            magic = stream.read(4)
        if magic not in MACHO:
            continue
        commands = subprocess.check_output(["/usr/bin/otool", "-l", str(path)], text=True)
        minimum_command = False
        for line in commands.splitlines():
            words = line.split()
            if len(words) == 2 and words[0] == "cmd":
                minimum_command = words[1] == "LC_VERSION_MIN_MACOSX"
            if words and (words[0] == "minos" or (minimum_command and words[0] == "version")):
                minimum = tuple(map(int, words[1].split(".")[:2]))
                if minimum > (14, 0):
                    raise RuntimeError(
                        f"{path.name} requires macOS {words[1]}, above the supported minimum"
                    )
        libraries = subprocess.check_output(["/usr/bin/otool", "-L", str(path)], text=True)
        identifiers = subprocess.check_output(["/usr/bin/otool", "-D", str(path)], text=True)
        install_ids = {
            line.strip()
            for line in identifiers.splitlines()
            if line.strip() and not line.endswith(":")
        }
        for line in libraries.splitlines():
            if line.startswith(("\t", " ")) and " (" in line:
                dependency = line.strip().split(" (", 1)[0]
                if dependency not in install_ids and not dependency.startswith(
                    ("@", "/usr/lib/", "/System/Library/")
                ):
                    raise RuntimeError(f"Nonportable library in {path.name}: {dependency}")
        run(
            "/usr/bin/codesign",
            "--force",
            "--sign",
            "-",
            path,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        count += 1
    print(f"Verified and locally signed {count} native runtime files.", flush=True)
    for record in runtime.glob("lib/python*/site-packages/*.dist-info/RECORD"):
        rows = []
        for row in csv.reader(record.read_text().splitlines()):
            path = (record.parent.parent / row[0]).resolve()
            if not path.is_file():
                continue
            if path == record:
                rows.append([row[0], "", ""])
            else:
                value = base64.urlsafe_b64encode(bytes.fromhex(digest(path))).decode().rstrip("=")
                rows.append([row[0], "sha256=" + value, str(path.stat().st_size)])
        with record.open("w", newline="") as stream:
            csv.writer(stream).writerows(rows)
    return runtime


def python_notices(spec, runtime):
    import zstandard

    archive = download_python(spec["license_archive"])
    destination = BUILD / "python-notices"
    destination.mkdir()
    with archive.open("rb") as source, zstandard.ZstdDecompressor().stream_reader(source) as stream:
        with tarfile.open(fileobj=stream, mode="r|") as bundle:
            for member in bundle:
                path = Path(member.name)
                if not member.isfile() or not path.is_relative_to("python") or ".." in path.parts:
                    continue
                if path.name == "PYTHON.json" or any(
                    word in path.name.lower() for word in ("license", "copying", "notice")
                ):
                    target = destination / path.relative_to("python")
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(bundle.extractfile(member).read())
    metadata = json.loads((destination / "PYTHON.json").read_text())
    allowed_missing = set()
    zlib_entries = metadata["build_info"]["extensions"].get("zlib", [])
    libraries = subprocess.check_output(
        ["/usr/bin/otool", "-L", str(runtime / "lib/libpython3.12.dylib")], text=True
    )
    # This pinned macOS build references an unused Linux zlib-ng notice in its
    # generic metadata. The interpreter actually links Apple's system libz.
    if (
        spec["release"] == "20261013"
        and spec["python_version"] == "3.12.15"
        and zlib_entries
        and all(entry.get("links") == [{"name": "z", "system": True}] for entry in zlib_entries)
        and "/usr/lib/libz.1.dylib" in libraries
    ):
        allowed_missing.add("licenses/LICENSE.zlib-ng.txt")
        (destination / "SYSTEM-LIBRARY-NOTES.txt").write_text(
            "The pinned macOS PYTHON.json mentions licenses/LICENSE.zlib-ng.txt, "
            "which upstream does not include in its archive. This macOS interpreter "
            "links /usr/lib/libz.1.dylib (verified with otool); zlib-ng is not shipped. "
            "The upstream zlib notice is retained. No runtime license text was omitted.\n"
        )

    def check_references(value):
        if isinstance(value, dict):
            for key, child in value.items():
                if key in {"license_path", "license_paths"}:
                    for name in [child] if isinstance(child, str) else (child or []):
                        if not (destination / name).is_file() and name not in allowed_missing:
                            raise RuntimeError(f"Missing Python component license: {name}")
                else:
                    check_references(child)
        elif isinstance(value, list):
            for child in value:
                check_references(child)

    check_references(metadata)
    return destination


def copy_notices(runtime, destination, python_licenses):
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copytree(python_licenses, destination / "Python-build-standalone")
    # Retain CPython's full license directory and every distribution's installed notices.
    python_notices = (
        list(runtime.glob("lib/python*/LICENSE*"))
        + list(runtime.glob("share/doc/python*/LICENSE*"))
        + list(runtime.glob("LICENSE*"))
    )
    if not python_notices:
        raise RuntimeError("Standalone Python license not found")
    for index, path in enumerate(python_notices):
        target = destination / f"Python-{index}-{path.name}"
        if path.is_dir():
            shutil.copytree(path, target)
        else:
            shutil.copy2(path, target)
    site = next(runtime.glob("lib/python*/site-packages"))
    inventory = []
    for metadata in sorted(site.glob("*.dist-info")):
        target = destination / metadata.name
        target.mkdir()
        for path in metadata.iterdir():
            if (
                path.name.lower().startswith(("license", "copying", "notice"))
                or path.name == "METADATA"
            ):
                if path.is_dir():
                    shutil.copytree(path, target / path.name)
                else:
                    shutil.copy2(path, target / path.name)
        inventory.append(metadata.name)
    (destination / "bundled-distributions.json").write_text(json.dumps(inventory, indent=2) + "\n")
    shutil.copy2(ROOT / "packaging/python-runtime.json", destination / "python-provenance.json")


def tar_filter(info):
    info.uid = info.gid = 0
    info.uname = info.gname = ""
    info.mtime = 0
    info.pax_headers = {}
    return info


def main():
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise SystemExit("Build on macOS with Apple Silicon")
    if not UV.is_file():
        raise SystemExit(
            "Install the development tooling first: scripts/install.sh --dev --cli-only"
        )
    if BUILD.is_symlink():
        raise SystemExit("Refusing a symlinked build directory")
    if BUILD.exists():
        shutil.rmtree(BUILD)
    BUILD.mkdir(parents=True)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    spec = json.loads((ROOT / "packaging/python-runtime.json").read_text())
    runtime = prepare_runtime(spec)
    python_licenses = python_notices(spec, runtime)
    print("Building the native interface…", flush=True)
    run(ROOT / "scripts/build-app.sh", cwd=ROOT)
    staging = BUILD / "dmg"
    staging.mkdir()
    app = staging / "NCF Image Upscaler.app"
    shutil.copytree(APP_HOME / "runtime/native-build/NCF Image Upscaler.app", app, symlinks=True)
    import plistlib

    info_path = app / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info.pop("NCFImageUpscalerDataDirectory", None)
    info_path.write_bytes(plistlib.dumps(info))
    resources = app / "Contents/Resources"
    copy_notices(runtime, resources / "Licenses/Runtime", python_licenses)
    payload = resources / "runtime.tar"
    print("Packing the portable engine…", flush=True)
    with tarfile.open(payload, "w", format=tarfile.PAX_FORMAT) as bundle:
        bundle.add(runtime, arcname="runtime", recursive=False, filter=tar_filter)
        for path in sorted(runtime.rglob("*")):
            bundle.add(
                path,
                arcname=str(Path("runtime") / path.relative_to(runtime)),
                recursive=False,
                filter=tar_filter,
            )
    manifest = {"archive": "runtime.tar", "sha256": digest(payload), "version": VERSION}
    (resources / "portable-runtime.json").write_text(json.dumps(manifest, indent=2) + "\n")
    shutil.copy2(ROOT / "src/ncf_image_upscaler/models.json", resources / "models.json")
    run("/usr/bin/codesign", "--force", "--sign", "-", app)
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", app)
    (staging / "Applications").symlink_to("/Applications", target_is_directory=True)
    shutil.copy2(ROOT / "packaging/INSTALL.txt", staging / "INSTALL.txt")
    image = OUTPUT / f"NCFImageUpscaler-{VERSION}-arm64.dmg"
    print("Creating the disk image…", flush=True)
    run(
        "/usr/bin/hdiutil",
        "create",
        "-volname",
        "NCF Image Upscaler",
        "-srcfolder",
        staging,
        "-ov",
        "-format",
        "UDZO",
        image,
    )
    run("/usr/bin/hdiutil", "verify", image)
    checksum = OUTPUT / "SHA256SUMS.txt"
    checksum.write_text(f"{digest(image)}  {image.name}\n")
    print(f"Ready: {image} ({image.stat().st_size / 1_000_000:.1f} MB)", flush=True)


if __name__ == "__main__":
    main()
