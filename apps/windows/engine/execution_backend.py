"""DirectML preference with explicit CPU fallback and measured node assignment."""

import json
from collections import Counter
from pathlib import Path


class ExecutionBackend:
    def __init__(self, ort, model, preference, output, emit):
        self.ort, self.model, self.output, self.emit = ort, model, output, emit
        self.fallback_reason = ""
        self.node_events = {}
        self.profile_note = ""
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

    def finish_profile(self, read):
        """Diagnostics must not invalidate pixels from a successful session.run."""
        profile = None
        try:
            name = self.session.end_profiling()
            if not name:
                return None
            profile = Path(name)
            if not read:
                return None
            events = json.loads(profile.read_text(encoding="utf-8"))
            if not isinstance(events, list):
                return None
            measured = Counter()
            for event in events:
                args = event.get("args") if isinstance(event, dict) else None
                provider = args.get("provider") if isinstance(args, dict) else None
                if provider in ("DmlExecutionProvider", "CPUExecutionProvider"):
                    measured[provider] += 1
            return measured or None
        except Exception:
            return None
        finally:
            # Delete only our own private profiling output, never arbitrary paths.
            if profile is not None:
                try:
                    owned = self.output.with_suffix(".execution").resolve()
                    actual = profile.resolve()
                    if actual.parent == owned.parent and actual.name.startswith(owned.name + "_"):
                        actual.unlink(missing_ok=True)
                except Exception:
                    pass

    def run(self, outputs, inputs):
        try:
            result = self.session.run(outputs, inputs)
        except Exception as error:
            if "DmlExecutionProvider" not in self.session.get_providers():
                raise
            self.finish_profile(False)
            self.fallback_reason = "DirectML execution failed; using CPU: " + str(error)[:300]
            self.session = self.create(False)
            self.profile_pending = True
            result = self.session.run(outputs, inputs)
        if self.profile_pending:
            measured = self.finish_profile(True)
            if measured:
                cumulative = Counter(self.node_events)
                cumulative.update(measured)
                self.node_events = dict(cumulative)
                gpu = self.node_events.get("DmlExecutionProvider", 0)
                cpu = self.node_events.get("CPUExecutionProvider", 0)
                self.backend = ("GPU DirectML" + (" + CPU nodes" if cpu else "")) if gpu else "CPU"
                self.profile_note = ""
            else:
                self.backend = "Execution provider unverified"
                self.profile_note = "Profiling unavailable; computed image retained"
            self.profile_pending = False
            self.emit(
                "backend",
                backend=self.backend,
                node_events=self.node_events,
                fallback_reason=self.fallback_reason,
                profile_note=self.profile_note,
            )
        return result
