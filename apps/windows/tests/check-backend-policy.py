"""Controlled provider failures/diagnostics; no model, network or real inference."""

import argparse
import json
from pathlib import Path
from types import SimpleNamespace

from execution_backend import ExecutionBackend

parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=False)
rows = []


class Runtime:
    ExecutionMode = SimpleNamespace(ORT_SEQUENTIAL="sequential")

    def __init__(self, mode):
        self.mode = mode
        self.sessions = []

    def SessionOptions(self):
        return SimpleNamespace()

    def get_available_providers(self):
        return (
            ["CPUExecutionProvider"]
            if self.mode == "unavailable"
            else ["DmlExecutionProvider", "CPUExecutionProvider"]
        )

    def InferenceSession(self, model, sess_options, providers):
        gpu = "DmlExecutionProvider" in providers
        if gpu and self.mode == "init_failure":
            raise RuntimeError("Controlled GPU initialization failure")
        assert sess_options.enable_mem_pattern is False
        assert sess_options.execution_mode == "sequential"
        session = Session(self, gpu and self.mode != "silent_fallback", len(self.sessions))
        self.sessions.append(session)
        return session


class Session:
    def __init__(self, runtime, gpu, index):
        self.runtime, self.gpu, self.index, self.calls = runtime, gpu, index, 0

    def get_providers(self):
        return (
            ["DmlExecutionProvider", "CPUExecutionProvider"]
            if self.gpu
            else ["CPUExecutionProvider"]
        )

    def disable_fallback(self):
        pass

    def run(self, outputs, inputs):
        self.calls += 1
        if self.gpu and (
            self.runtime.mode == "run_failure"
            or self.runtime.mode == "late_failure"
            and self.calls == 2
        ):
            raise RuntimeError("Controlled GPU execution failure")
        return [42]

    def end_profiling(self):
        path = args.output / (self.runtime.mode + str(self.index) + ".json")
        provider = "DmlExecutionProvider" if self.gpu else "CPUExecutionProvider"
        path.write_text(
            json.dumps(
                []
                if self.runtime.mode == "unverified"
                else [dict(args=dict(provider=provider))] * (20 if self.gpu else 7)
            ),
            encoding="utf-8",
        )
        return str(path)


for case in [
    "gpu",
    "cpu",
    "unavailable",
    "init_failure",
    "run_failure",
    "late_failure",
    "silent_fallback",
    "unverified",
]:
    runtime = Runtime(case)
    backend = ExecutionBackend(
        runtime,
        Path("controlled-no-model"),
        "cpu" if case == "cpu" else "auto",
        args.output / case,
        lambda *a, **kw: None,
    )
    assert backend.run(None, {}) == [42]
    if case == "late_failure":
        assert backend.run(None, {}) == [42]
        assert backend.node_events == {"DmlExecutionProvider": 20, "CPUExecutionProvider": 7}
        assert "CPU nodes" in backend.backend
    elif case == "unverified":
        assert backend.node_events == {}
        assert backend.backend == "Execution provider unverified"
    elif case == "gpu":
        assert backend.node_events == {"DmlExecutionProvider": 20}
    else:
        assert backend.node_events == {"CPUExecutionProvider": 7}
        assert backend.backend == "CPU"
    if case not in ["gpu", "cpu"]:
        assert backend.fallback_reason
    rows.append(
        dict(case=case, passed=True, backend=backend.backend, node_events=backend.node_events)
    )
(args.output / "report.json").write_text(
    json.dumps(dict(origin="controlled sessions, no actual inference", rows=rows), indent=2),
    encoding="utf-8",
)
print(json.dumps(rows))
