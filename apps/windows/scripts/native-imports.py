"""Read PE imports; report packaged versus explicit Windows/system prerequisites."""

import argparse
import hashlib
import json
import os
import re
import struct
from pathlib import Path


def pe_imports(path):
    data = path.read_bytes()
    pe = struct.unpack_from("<I", data, 60)[0]
    count = struct.unpack_from("<H", data, pe + 6)[0]
    optional, size = pe + 24, struct.unpack_from("<H", data, pe + 20)[0]
    is64 = struct.unpack_from("<H", data, optional)[0] == 0x20B
    directories = optional + (112 if is64 else 96)
    imagebase = struct.unpack_from("<Q" if is64 else "<I", data, optional + (24 if is64 else 28))[0]
    sections = []
    for i in range(count):
        virtual_size, va, raw_size, raw = struct.unpack_from(
            "<IIII", data, optional + size + 40 * i + 8
        )
        sections.append((va, max(virtual_size, raw_size), raw))

    def offset(rva):
        for va, length, raw in sections:
            if va <= rva < va + length:
                return raw + rva - va
        return rva

    def text(rva):
        start = offset(rva)
        return data[start : data.index(b"\0", start)].decode("ascii")

    imports = {}
    for index, step, name_index in [(1, 20, 3), (13, 32, 1)]:
        rva, _ = struct.unpack_from("<II", data, directories + 8 * index)
        if not rva:
            continue
        cursor = offset(rva)
        while True:
            values = struct.unpack_from("<" + "I" * (step // 4), data, cursor)
            if not any(values):
                break
            name = values[name_index]
            if index == 13 and not values[0] & 1:
                name -= imagebase
            library = text(name).lower()
            exports = []
            thunk = values[0] or values[4] if index == 1 else values[4]
            if thunk and index == 1:
                pointer = offset(thunk)
                width = 8 if is64 else 4
                while True:
                    value = struct.unpack_from("<Q" if is64 else "<I", data, pointer)[0]
                    pointer += width
                    if not value:
                        break
                    exports.append(
                        "#" + str(value & 65535)
                        if value & (1 << (width * 8 - 1))
                        else text(value + 2)
                    )
            imports[library] = exports
            cursor += step
    return imports


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = args.bundle.resolve()
    runtime = root / "runtime"
    binaries = [p for p in runtime.rglob("*") if p.suffix.lower() in {".exe", ".dll", ".pyd"}]
    provided = {p.name.lower() for p in binaries}
    rows = []
    required = None
    for path in binaries:
        imports = pe_imports(path)
        for library in imports:
            if library in provided:
                kind = "packaged native file"
            elif library == "msvcp140.dll":
                kind = "required system VC++ runtime; installer/startup gate"
            elif library.startswith(("api-ms-", "ext-ms-")):
                kind = "Windows API set"
            elif (Path(os.environ["WINDIR"]) / "System32" / library).is_file():
                kind = "Windows system dependency (not copied)"
            else:
                raise RuntimeError("Unclassified native dependency: " + library)
            rows.append(
                dict(file=path.relative_to(root).as_posix(), imports=library, classification=kind)
            )
        if path.name == "onnxruntime_pybind11_state.pyd":
            required = sorted(imports["msvcp140.dll"])
    app = Path(__file__).resolve().parents[1]
    declared = re.findall(
        r'"([^"]+)"', (app / "src/RequiredMsvcExports.cs").read_text(encoding="utf-8")
    )
    assert required == sorted(declared), "Pinned ORT required-export gate must be updated"
    components = json.loads((app / "native-components.json").read_text(encoding="utf-8"))
    dml = runtime / "Lib/site-packages/onnxruntime/capi/DirectML.dll"
    assert hashlib.sha256(dml.read_bytes()).hexdigest() == components["bundled_dll_sha256"]
    notice = app / components["license_file"]
    assert hashlib.sha256(notice.read_bytes()).hexdigest() == components["license_sha256"]
    local = []
    for name in ["vcruntime140.dll", "vcruntime140_1.dll"]:
        path = runtime / name
        local.append(
            dict(
                file="runtime/" + name,
                sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                origin="pinned official CPython embedded archive; not System32",
            )
        )
    args.output.write_text(
        json.dumps(
            dict(
                imports=rows,
                local_vcruntime=local,
                required_msvcp_exports=len(required),
                native_closure_claimed=False,
                system_prerequisite=(
                    "Microsoft Visual C++ x64; version/loader/pinned exports checked"
                ),
            ),
            indent=2,
        ),
        encoding="utf-8",
    )
    print(
        json.dumps(
            dict(
                native_binaries=len(binaries),
                imports=len(rows),
                required_msvcp_exports=len(required),
                system_vc_required=True,
            )
        )
    )


if __name__ == "__main__":
    main()
