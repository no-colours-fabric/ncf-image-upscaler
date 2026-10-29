#!/usr/bin/env python3
"""Verify a relocated DMG installation with a restricted PATH and no existing runtime."""

import argparse
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    parser.add_argument(
        "--gpu", action="store_true", help="use already-installed models and Apple GPU"
    )
    args = parser.parse_args()
    home = (
        Path(
            os.environ.get(
                "IMAGE_UPSCALER_HOME", Path.home() / "Library/Application Support/image-upscaler"
            )
        )
        .expanduser()
        .resolve()
    )
    with tempfile.TemporaryDirectory(prefix="binary-check-", dir=home / "runtime") as name:
        root = Path(name)
        mount = root / "mount"
        mount.mkdir()
        subprocess.run(
            [
                "/usr/bin/hdiutil",
                "attach",
                "-readonly",
                "-nobrowse",
                "-mountpoint",
                str(mount),
                str(args.image.resolve()),
            ],
            check=True,
        )
        try:
            relocated = root / "Applications with spaces" / "Image Upscaler.app"
            relocated.parent.mkdir()
            shutil.copytree(mount / "Image Upscaler.app", relocated, symlinks=True)
        finally:
            subprocess.run(["/usr/bin/hdiutil", "detach", str(mount)], check=True)
        resources = relocated / "Contents/Resources"
        subprocess.run(
            ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(relocated)], check=True
        )
        info = plistlib.loads((relocated / "Contents/Info.plist").read_bytes())
        assert "ImageUpscalerDataDirectory" not in info
        manifest = json.loads((resources / "portable-runtime.json").read_text())
        with (resources / manifest["archive"]).open("rb") as stream:
            assert hashlib.file_digest(stream, "sha256").hexdigest() == manifest["sha256"]
        notices = resources / "Licenses/Runtime"
        assert (notices / "python-provenance.json").is_file()
        for package in (
            "image_upscaler",
            "numpy",
            "scipy",
            "pillow",
            "mlx",
            "mlx_metal",
            "certifi",
        ):
            assert any(path.name.lower().startswith(package + "-") for path in notices.iterdir()), (
                package
            )
        data = root / "isolated data"
        environment = {
            **os.environ,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "IMAGE_UPSCALER_HOME": str(data),
            "PYTHONPATH": "/does/not/exist",
            "PYTHONHOME": "/does/not/exist",
            "DEVELOPER_DIR": "/does/not/exist",
        }
        executable = relocated / "Contents/MacOS/ImageUpscaler"
        # GUI bootstrap is native and therefore ignores Python environment variables.
        installed = subprocess.check_output(
            [str(executable), "--prepare-runtime"], env=environment, cwd=root, text=True
        ).strip()
        python = Path(installed)
        assert python.is_file() and python.is_relative_to(data)
        again = subprocess.check_output(
            [str(executable), "--prepare-runtime"], env=environment, cwd=root, text=True
        ).strip()
        assert again == installed
        # The app can be removed after extraction; the runtime has no bundle/build paths.
        shutil.rmtree(relocated)

        def run(*arguments, check=True):
            process = subprocess.run(
                [str(python), "-I", "-B", *map(str, arguments)],
                env=environment,
                cwd=root,
                text=True,
                capture_output=True,
                timeout=120,
            )
            if check and process.returncode:
                raise RuntimeError(process.stdout + process.stderr)
            return process

        run(
            "-c",
            "import numpy, scipy, PIL, certifi, ssl, sys; "
            "assert sys.prefix.startswith(sys.argv[1]); "
            "ssl.create_default_context(cafile=certifi.where())",
            str(data),
        )
        assert info["CFBundleShortVersionString"] in run("-m", "image_upscaler", "--version").stdout
        status = run("-m", "image_upscaler.setup_models", "--status")
        events = [json.loads(line) for line in status.stdout.splitlines()]
        assert not any(model["installed"] for model in events[0]["models"])
        assert not (data / "models").exists()
        fixture = root / "source.png"
        run(
            "-c",
            "from PIL import Image; import sys; "
            "Image.new('RGBA',(45,37),(220,80,30,128)).save(sys.argv[1])",
            fixture,
        )
        original = fixture.read_bytes()
        missing = run(
            "-m",
            "image_upscaler.worker",
            "--input",
            fixture,
            "--output",
            root / "missing.png",
            check=False,
        )
        assert missing.returncode == 1 and "is not installed" in missing.stdout
        assert not (root / "missing.png").exists() and not (data / "models").exists()
        assert fixture.read_bytes() == original
        entry = python.parent / "upscale"
        command = subprocess.run(
            [str(entry), "--version"], env=environment, cwd=root, text=True, capture_output=True
        )
        assert command.returncode == 0, command.stderr
        print(
            "PASS: relocated DMG, offline extraction, isolated Python and CLI, "
            "no build/source/system-Python paths, and safe missing-model failure",
            flush=True,
        )
        if args.gpu:
            models = home / "models"
            (data / "models").symlink_to(models, target_is_directory=True)
            script = r"""
import socket, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
from image_upscaler.models import registry, require_model
from image_upscaler.engine import MLXEngine
from image_upscaler.imaging import upscale_image

def forbidden(*a, **kw):
    raise AssertionError("Inference attempted network access")
socket.socket.connect = forbidden
socket.socket.connect_ex = forbidden
socket.create_connection = forbidden
root=Path(sys.argv[1])
source=root/'rgba.png'
image=Image.new('RGBA',(45,37))
draw=ImageDraw.Draw(image)
draw.ellipse((5,5,39,31),fill=(230,100,40,128))
draw.ellipse((12,10,32,26),fill=(230,100,40,255))
image.save(source)
before=source.read_bytes()
cases=[('x4plus',4),('x2plus',2),('anime',4),('fast',4),
       ('x2plus',1),('anime',1),('fast',1)]
for key,scale in cases:
    spec=registry()[key]
    destination=root/f'{key}-{scale}.png'
    upscale_image(source,destination,MLXEngine(spec,require_model(spec),tile=32),scale=scale)
    with Image.open(destination) as output:
        assert output.mode=='RGBA' and output.size==(45*scale,37*scale)
        expected=image.getchannel('A').resize(output.size,Image.Resampling.LANCZOS)
        np.testing.assert_array_equal(output.getchannel('A'),expected)
        rgb=np.asarray(output)[:,:,:3]
        visible=np.asarray(expected)>128
        assert rgb[visible,0].mean()>rgb[visible,2].mean()
        for bg in (0,255):
            composite=Image.alpha_composite(Image.new('RGBA',output.size,(bg,bg,bg,255)),output)
            pixels=np.asarray(output)
            a=pixels[:,:,3:4].astype(float)/255
            expected_rgb=np.rint(pixels[:,:,:3]*a+bg*(1-a)).astype(np.uint8)
            assert np.abs(np.asarray(composite)[:,:,:3].astype(int)-expected_rgb).max()<=1
    assert source.read_bytes()==before
    print(f'PASS: portable {key} x{scale}, alpha, light/dark edges, no network',flush=True)
"""
            result = run("-c", script, root)
            print(result.stdout, end="", flush=True)


if __name__ == "__main__":
    main()
