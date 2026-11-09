"""DirectML preference with explicit CPU fallback and measured node assignment."""

import json
from collections import Counter
from pathlib import Path


class ExecutionBackend:
    def __init__(self, ort, model, preference, output, emit):
        self.ort, self.model, self.output, self.emit = ort, model, output, emit
        self.fallback_reason = ""
        self.node_events = {}
        use_gpu = preference != "cpu" and "DmlExecutionProvider" in ort.get_available_providers()
        if preference != "cpu" and not use_gpu:
            self.fallback_reason = "DirectML is unavailable; using CPU"
        try:
            self.session = self.create(use_gpu)
        except Exception as error:
            if not use_gpu:
                raise
            self.fallback_reason = "DirectML initialization failed; using CPU: " + str(error)[:300]
            self.session = self.create(False)
        self.backend = (
            "DirectML selected (execution pending)"
            if "DmlExecutionProvider" in self.session.get_providers()
            else "CPU"
        )
        if use_gpu and "DmlExecutionProvider" not in self.session.get_providers():
            self.fallback_reason = (
                self.fallback_reason or "DirectML could not be selected; using CPU"
            )
        self.profile_pending = True

    def create(self, gpu):
        o = self.ort.SessionOptions()
        o.intra_op_num_threads = 4
        o.inter_op_num_threads = 1
        o.enable_mem_pattern = False
        o.execution_mode = self.ort.ExecutionMode.ORT_SEQUENTIAL
        o.enable_profiling = True
        o.profile_file_prefix = str(self.output.with_suffix(".execution"))
        providers = (
            ["DmlExecutionProvider", "CPUExecutionProvider"] if gpu else ["CPUExecutionProvider"]
        )
        session = self.ort.InferenceSession(str(self.model), sess_options=o, providers=providers)
        session.disable_fallback()
        return session

    def run(self, outputs, inputs):
        try:
            result = self.session.run(outputs, inputs)
        except Exception as error:
            if "DmlExecutionProvider" not in self.session.get_providers():
                raise
            try:
                self.session.end_profiling()
            except Exception:
                pass
            self.fallback_reason = "DirectML execution failed; using CPU: " + str(error)[:300]
            self.session = self.create(False)
            self.profile_pending = True
            result = self.session.run(outputs, inputs)
        if self.profile_pending:
            profile = Path(self.session.end_profiling())
            events = json.loads(profile.read_text(encoding="utf-8"))
            measured = Counter(
                e.get("args", {}).get("provider")
                for e in events
                if e.get("args", {}).get("provider")
            )
            cumulative = Counter(self.node_events)
            cumulative.update(measured)
            self.node_events = dict(cumulative)
            gpu = self.node_events.get("DmlExecutionProvider", 0)
            cpu = self.node_events.get("CPUExecutionProvider", 0)
            self.backend = (
                ("GPU DirectML" + (" + CPU nodes" if cpu else ""))
                if gpu
                else ("CPU" if cpu else "Execution provider unverified")
            )
            if not gpu and not cpu:
                self.fallback_reason = "No execution-provider events recorded"
            elif not gpu and "DmlExecutionProvider" in self.session.get_providers():
                self.fallback_reason = "No DirectML node execution recorded in the profiled forward"
            self.profile_pending = False
            self.emit(
                "backend",
                backend=self.backend,
                node_events=self.node_events,
                fallback_reason=self.fallback_reason,
            )
        return result
