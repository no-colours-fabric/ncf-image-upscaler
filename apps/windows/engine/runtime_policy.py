"""Privacy policy for the pinned Windows ONNX Runtime, before any session work."""


def configure_runtime():
    import onnxruntime as ort

    # Official Windows 1.17.3 CPU/DirectML builds enable platform TraceLogging by default.
    # Use that version's supported API, not unrelated/newer environment flags.
    ort.disable_telemetry_events()
    return ort
