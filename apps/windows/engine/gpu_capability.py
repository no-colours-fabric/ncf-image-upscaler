"""Offline, weight-free DirectML execution probe; no user image or model needed."""

import base64
import json
import sys
from collections import Counter
from pathlib import Path

from runtime_policy import configure_runtime

# ONNX Add graph, two runtime inputs [1,4], no initializers/weights, opset17/IR8.
PROBE = (
    "CAg6XwoOCgF4CgF5EgF6IgNBZGQSDkdQVSBjYXBhYmlsaXR5WhMKAXgSDgoMCAESCAoCCAEK"
    "AggEWhMKAXkSDgoMCAESCAoCCAEKAggEYhMKAXoSDgoMCAESCAoCCAEKAggEQgQKABAR"
)


def probe(directory):
    import numpy as np

    ort = configure_runtime()
    if "DmlExecutionProvider" not in ort.get_available_providers():
        return dict(available=False, reason="DirectML is unavailable")
    options = ort.SessionOptions()
    options.enable_mem_pattern = False
    options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    options.enable_profiling = True
    options.profile_file_prefix = str(directory / "gpu-capability")
    options.add_session_config_entry("session.disable_cpu_ep_fallback", "1")
    session = ort.InferenceSession(
        base64.b64decode(PROBE), sess_options=options, providers=["DmlExecutionProvider"]
    )
    session.disable_fallback()
    profile = None
    try:
        result = session.run(
            None, {"x": np.ones((1, 4), np.float32), "y": np.ones((1, 4), np.float32)}
        )[0]
        profile = Path(session.end_profiling())
        events = json.loads(profile.read_text(encoding="utf-8"))
        counts = dict(
            Counter(
                e.get("args", {}).get("provider")
                for e in events
                if e.get("args", {}).get("provider")
            )
        )
        return dict(
            available=bool(
                np.array_equal(result, np.full((1, 4), 2, np.float32))
                and counts.get("DmlExecutionProvider", 0)
            ),
            node_events=counts,
        )
    finally:
        if profile is not None:
            profile.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        print(json.dumps(probe(Path(sys.argv[1]))))
    except Exception as error:
        print(json.dumps(dict(available=False, reason=str(error)[:500])))
