"""Trace actual supported API calls through the production worker, not a fake ORT."""

import argparse
import json
import runpy
import sys
from pathlib import Path

from PIL import Image

from runtime_policy import configure_runtime

ort = configure_runtime()

parser = argparse.ArgumentParser()
parser.add_argument("--bundle", required=True, type=Path)
parser.add_argument("--model-root", required=True, type=Path)
parser.add_argument("--output", required=True, type=Path)
args = parser.parse_args()
assert ort.__version__ == "1.17.3"
assert Path(sys.executable).resolve().is_relative_to(args.bundle.resolve())
args.output.mkdir(parents=True, exist_ok=False)
source = args.output / "source.png"
result = args.output / "result.png"
Image.new("RGB", (23, 17), (80, 130, 190)).save(source)
trace = []
actual_disable = ort.disable_telemetry_events
actual_options = ort.SessionOptions
actual_session = ort.InferenceSession


def disable():
    actual_disable()
    trace.append("actual disable_telemetry_events returned")


def options(*a, **kw):
    assert trace and trace[0] == "actual disable_telemetry_events returned"
    trace.append("SessionOptions")
    return actual_options(*a, **kw)


def session(*a, **kw):
    assert trace[0] == "actual disable_telemetry_events returned"
    trace.append("InferenceSession")
    return actual_session(*a, **kw)


ort.disable_telemetry_events = disable
ort.SessionOptions = options
ort.InferenceSession = session
sys.argv = [
    "worker.py",
    "--input",
    str(source),
    "--output",
    str(result),
    "--model",
    "fast",
    "--scale",
    "1",
    "--model-root",
    str(args.model_root),
]
try:
    runpy.run_path(str(args.bundle / "engine/worker.py"), run_name="__main__")
except SystemExit as code:
    assert code.code == 0
assert trace == ["actual disable_telemetry_events returned", "SessionOptions", "InferenceSession"]
with Image.open(result) as image:
    image.load()
    assert image.size == (23, 17)
report = dict(
    ort=ort.__version__,
    trace=trace,
    actual_api_delegated=True,
    test_bootstrap_policy_applied=True,
    production_worker_path=True,
    real_cpu_inference=True,
    output_decode=True,
    scope=(
        "ORT per-process policy before session processing; "
        "not OS-wide telemetry or network isolation"
    ),
)
(args.output / "privacy.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(json.dumps(report))
