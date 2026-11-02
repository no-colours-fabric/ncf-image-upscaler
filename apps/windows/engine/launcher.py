"""Owns a process-local Job cap and forwards worker JSON Lines to the interface."""

import json
import sys
import threading
import time
import uuid
from pathlib import Path

from job_guard import GuardedProcess, system_memory


def emit(event, **values):
    print(json.dumps({"event": event, **values}, ensure_ascii=True), flush=True)


def main():
    arguments = sys.argv[1:]
    output = Path(arguments[arguments.index("--output") + 1])
    output.parent.mkdir(parents=True, exist_ok=True)
    log = output.with_suffix(".worker-" + uuid.uuid4().hex + ".log")
    bundle = Path(__file__).resolve().parents[1]
    memory = system_memory()
    if (
        memory["physical_available_bytes"] < 3 * 2**30
        or memory["commit_headroom_bytes"] < 3 * 2**30
    ):
        raise RuntimeError(
            "Not enough free memory to start. Close other applications and try again."
        )
    cancel = threading.Event()

    def read_cancel():
        for line in sys.stdin:
            if line.strip() == "cancel":
                cancel.set()
                break

    threading.Thread(target=read_cancel, daemon=True).start()
    proc = GuardedProcess(
        [sys.executable, str(bundle / "engine/worker.py")] + arguments, log, bundle, 8 * 2**30
    )
    position = 0
    completed = False
    worker_error = False
    reason = None

    def drain():
        nonlocal position, completed, worker_error
        with log.open("r", encoding="utf-8", errors="replace") as reader:
            reader.seek(position)
            while True:
                line_start = reader.tell()
                line = reader.readline()
                if not line:
                    break
                if not line.endswith("\n"):
                    reader.seek(line_start)
                    break
                try:
                    data = json.loads(line)
                    if isinstance(data, dict) and "event" in data:
                        print(json.dumps(data, ensure_ascii=True), flush=True)
                        completed |= data["event"] == "completed"
                        worker_error |= data["event"] == "error"
                    else:
                        print(line.rstrip(), file=sys.stderr, flush=True)
                except ValueError:
                    print(line.rstrip(), file=sys.stderr, flush=True)
            position = reader.tell()

    try:
        while proc.poll() is None:
            drain()
            if cancel.is_set():
                reason = "cancelled"
            current = system_memory()
            if (
                current["physical_available_bytes"] < 3 * 2**30
                or current["commit_headroom_bytes"] < 2 * 2**30
            ):
                reason = "memory reserve"
            if reason:
                proc.kill()
                break
            time.sleep(0.08)
        drain()
        code = proc.poll()
        if completed:
            return 0
        if reason == "cancelled":
            emit("cancelled")
            return 130
        if reason == "memory reserve":
            emit(
                "error",
                message=(
                    "Processing stopped because free memory was running low. "
                    "Try Fast or a smaller image."
                ),
            )
            return 1
        if code != 0 and not worker_error:
            emit(
                "error",
                message=(
                    "The image worker stopped unexpectedly or reached "
                    "the 8 GiB memory safety limit. "
                    "Try Fast or a smaller image."
                ),
            )
        return code or (0 if completed else 1)
    finally:
        proc.finish()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        emit("error", message=str(error))
        sys.exit(1)
