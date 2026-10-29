#!/usr/bin/env python3
"""Check non-editable source installation offline, without GPU or model downloads."""

import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path


def main() -> None:
    archive = Path(sys.argv[1]).resolve()
    app_home = Path(
        os.environ.get(
            "IMAGE_UPSCALER_HOME", Path.home() / "Library/Application Support/image-upscaler"
        )
    ).expanduser()
    uv = app_home / "runtime/tooling/bin/uv"
    with tempfile.TemporaryDirectory(
        prefix="source-install-check-", dir=app_home / "runtime"
    ) as name:
        root = Path(name)
        source_root = root / "source"
        source_root.mkdir()
        with tarfile.open(archive, "r:gz") as bundle:
            bundle.extractall(source_root, filter="data")
        sources = list(source_root.iterdir())
        if len(sources) != 1 or not (sources[0] / "pyproject.toml").is_file():
            raise SystemExit("Expected one project root in the source archive")
        source = sources[0]
        runtime = root / "data/runtime/env"
        environment = {
            **os.environ,
            "UV_CACHE_DIR": str(app_home / "cache/uv"),
            "UV_PROJECT_ENVIRONMENT": str(runtime),
            "UV_PYTHON_DOWNLOADS": "never",
            "IMAGE_UPSCALER_HOME": str(root / "data"),
            "PYTHONDONTWRITEBYTECODE": "1",
        }

        def run(*arguments: str | Path, check: bool = True) -> subprocess.CompletedProcess:
            result = subprocess.run(
                [str(argument) for argument in arguments],
                env=environment,
                cwd=root,
                text=True,
                capture_output=True,
                timeout=120,
            )
            if check and result.returncode:
                sys.stderr.write(result.stdout + result.stderr)
                result.check_returncode()
            return result

        run(
            uv,
            "sync",
            "--locked",
            "--no-dev",
            "--no-editable",
            "--offline",
            "--python",
            sys.executable,
            "--project",
            source,
        )
        python = runtime / "bin/python"
        entry = runtime / "bin/upscale"
        commands = root / "commands"
        profile = root / "profile"
        run(
            python,
            "-c",
            "from pathlib import Path; import sys; "
            "from image_upscaler.installation import install_command; "
            "install_command(Path(sys.argv[1]), launcher=Path(sys.argv[2]), "
            "bin_dir=Path(sys.argv[3]), search_path=sys.argv[3], profile=Path(sys.argv[4]))",
            source,
            entry,
            commands,
            profile,
        )
        shutil.rmtree(source_root)
        command = commands / "upscale"
        version = run(command, "--version")
        assert "Image Upscaler" in version.stdout
        assert "--overwrite" in run(command, "--help").stdout
        run(command, "models", "list")
        imported = run(python, "-c", "import image_upscaler; print(image_upscaler.__file__)")
        assert str(runtime) in imported.stdout and "site-packages" in imported.stdout
        fixture = root / "original.png"
        run(
            python,
            "-c",
            "from PIL import Image; import sys; "
            "Image.new('RGBA', (12, 10), (220, 80, 30, 128)).save(sys.argv[1])",
            fixture,
        )
        original = fixture.read_bytes()
        missing = run(command, fixture, "--quiet", check=False)
        assert missing.returncode == 1 and "is not installed" in missing.stderr
        assert fixture.read_bytes() == original
        assert not (root / "original_4x.png").exists()
        assert not (root / "data/models").exists()
        assert not profile.exists()
    print("Source installation passed after source removal; no model download or GPU required")


if __name__ == "__main__":
    main()
