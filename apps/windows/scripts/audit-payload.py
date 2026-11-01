"""Fail closed if weights, development paths or incomplete caches enter a payload."""

import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
files = [p for p in root.rglob("*") if p.is_file() and p.name != "payload-sha256.json"]
for path in files:
    assert not path.is_symlink(), "Payload must not depend on external files"
    assert path.suffix.lower() not in {
        ".onnx",
        ".pth",
        ".pt",
        ".safetensors",
        ".npz",
        ".partial",
    }, path.name
    assert path.name != "pyvenv.cfg", "Host virtual environment dependency"
for path in root.rglob("*.pth"):
    raise AssertionError("Unexpected Python site path injection: " + path.name)
paths = (root / "runtime/python311._pth").read_text().splitlines()
assert paths == ["python311.zip", ".", "Lib\\site-packages", "..\\engine"]
assert not (root / "models").exists()
assert len(json.loads((root / "resources/models.json").read_text())) == 4
manifest = {}
for path in files:
    with path.open("rb") as stream:
        manifest[path.relative_to(root).as_posix()] = hashlib.file_digest(
            stream, "sha256"
        ).hexdigest()
(root / "payload-sha256.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
print(json.dumps({"files": len(files), "model_weights_in_payload": 0, "host_venv": False}))
