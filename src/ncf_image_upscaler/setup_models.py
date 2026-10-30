"""Explicit model setup for the native app; status checks never use the network."""

import argparse
import json

from .models import download_model, registry, require_model


def emit(event: str, **values) -> None:
    print(json.dumps({"event": event, **values}), flush=True)


def status() -> list[dict]:
    result = []
    for spec in registry().values():
        try:
            require_model(spec)
            installed = True
        except (FileNotFoundError, ValueError):
            installed = False
        result.append(
            {"id": spec.id, "title": spec.title, "size": spec.size, "installed": installed}
        )
    return result


def run(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Check or explicitly download NCF Image Upscaler models"
    )
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--status", action="store_true")
    action.add_argument("--download", action="store_true")
    args = parser.parse_args(argv)
    if args.download:
        specs = registry()
        total = sum(spec.size for spec in specs.values())
        finished = 0
        for spec in specs.values():
            emit("model", title=spec.title)

            def progress(received, _size, offset=finished):
                emit("progress", completed=offset + received, total=total)

            download_model(spec, progress=progress)
            finished += spec.size
            emit("progress", completed=finished, total=total)
    emit("status", models=status())
    emit("completed")
    return 0


def main() -> int:
    try:
        return run()
    except KeyboardInterrupt:
        emit("cancelled")
        return 130
    except Exception as error:
        emit("error", message=str(error))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
