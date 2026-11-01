"""Embed source identity without developer paths or environment identifiers."""

import hashlib
import json
import subprocess
import sys
from pathlib import Path

app = Path(__file__).resolve().parents[1]
repo = app.parents[1]
stage = Path(sys.argv[1])
paths = list((app / "src").glob("*.cs")) + list((app / "engine").glob("*.py"))
paths += [app / "models.json", app / "wheels.json", app / "toolchain.json"]
paths += [repo / "src/ncf_image_upscaler/imaging.py", repo / "native/Tools/MakeIcon.swift"]
sources = {
    p.relative_to(repo).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths
}
commit = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
dirty = bool(
    subprocess.check_output(
        [
            "git",
            "-C",
            str(repo),
            "status",
            "--porcelain",
            "--",
            "apps/windows",
            "src",
            "native/Tools/MakeIcon.swift",
        ],
        text=True,
    ).strip()
)
(stage / "resources/build.json").write_text(
    json.dumps(
        dict(
            version=(app / "VERSION").read_text().strip(),
            source_commit=commit,
            source_dirty=dirty,
            source_sha256=sources,
            model_weights_bundled=False,
            runtime="CPython 3.11.3 / ONNX Runtime 1.17.3 CPU",
            signed=False,
        ),
        indent=2,
    ),
    encoding="utf-8",
)
