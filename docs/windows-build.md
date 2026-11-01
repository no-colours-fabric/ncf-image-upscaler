# Build the experimental Windows installer

Run on Windows x64 with .NET Framework 4.8 and a developer Python 3.11+.
The installed application needs no developer Python. Build tools/dependencies
and output directories must remain outside Git. No model export stack is needed.

```powershell
$cache = Join-Path $env:LOCALAPPDATA 'NCF Image Upscaler\build-cache'
$build = Join-Path $env:LOCALAPPDATA 'NCF Image Upscaler\builds\preview1'
# Explicit HTTPS preparation; system certificate validation stays enabled.
.\apps\windows\scripts\prepare-dependencies.ps1 -Cache $cache
# Install the pinned compiler locally (not in Program Files).
$compiler = Join-Path $cache 'inno'
Start-Process (Join-Path $cache 'innosetup-6.7.4.exe') -Wait -WindowStyle Hidden `
  -ArgumentList @('/VERYSILENT','/CURRENTUSER','/NORESTART',('/DIR="'+$compiler+'"'))
# Offline assembly. $build\app must not exist; earlier builds are preserved.
.\apps\windows\scripts\build.ps1 -Cache $cache -BuildRoot $build `
  -ISCC (Join-Path $compiler 'ISCC.exe')
```

`toolchain.json` pins the official Python embedded ZIP and Inno Setup compiler;
`wheels.json` and `requirements-inference.lock` pin exact CPython 3.11 x64 wheels.
The builder extracts these files without changing host packages or importing a
research environment. It disables Python site-path injection, copies only the
shared imaging module/package marker, and compiles Windows-owned source.
Dependency licenses remain in their package distributions.

The payload audit rejects weights, sample ONNX datasets, virtual-environment
references and `.pth` injection. No model cache is copied. The Inno installer
uses only this audited payload, installs for the current user, checks .NET 4.8,
offers a shortcut and uninstall entry without administrator rights when .NET 4.8
and a suitable Microsoft Visual C++ x64 Runtime are already installed. A small
x64 helper checks the actual system MSVCP140 version/loader and all required ORT
exports before setup copies app files; startup repeats this check. Installing
missing prerequisites may need admin. Python's app-local VCRUNTIME files come
from the pinned official embedded ZIP; MSVCP140 is a separate system component,
not a claimed native closure.
It is not Authenticode-signed. Its application models are separately prepared
from `apps/windows/models.json` by visible cancellable setup. Missing/corrupt
files are prepared automatically on first use or before requested enhancement;
Models also offers manual repair/retry. Valid caches never require network.

The icon converter reads the existing `native/Tools/MakeIcon.swift` geometry;
the Mac source is not rewritten. This is shared-source reuse, not evidence of
identical platform rasterization. Action SVG source/hash/license pins are in
`apps/windows/resources/icons/manifest.json`.

## Checks

Run relevant Windows component checks and installed-runtime worker checks.
Explicit network downloader checks use small Fast downloads and test-only caches:

```powershell
.\apps\windows\scripts\check-models.ps1 -TestRoot (Join-Path $build 'download-check')
.\apps\windows\scripts\prepare-test-models.ps1 -TestRoot (Join-Path $build 'model-check')
# Existing prepared cache; the following processing checks NEVER download:
$app = Join-Path $build 'app'
$models = Join-Path $build 'model-check\cache'
& (Join-Path $app 'runtime\python.exe') .\apps\windows\tests\check-worker.py `
  --bundle $app --model-root $models --output (Join-Path $build 'matrix')
& (Join-Path $app 'runtime\python.exe') .\apps\windows\tests\check-tiling.py `
  --bundle $app --model-root $models --output (Join-Path $build 'tiling')
.\apps\windows\scripts\check-prerequisites.ps1 -TestRoot (Join-Path $build 'prereq-check')
.\apps\windows\scripts\check-auto-preparation.ps1 -TestRoot (Join-Path $build 'auto-prep-check')
& (Join-Path $app 'runtime\python.exe') .\apps\windows\tests\check-privacy.py `
  --bundle $app --model-root $models --output (Join-Path $build 'privacy-check')
python .\apps\windows\scripts\native-imports.py --bundle $app `
  --output (Join-Path $build 'native-dependencies.json')
```

Graph-closure validation is developer-only. Use a separate environment with
`onnx==1.16.0` (never add it to the installed user runtime), then run:

```powershell
& $developerPython .\apps\windows\scripts\check-graph-closure.py `
  --model-root $models --output (Join-Path $build 'graph-closure.json')
```

The checker verifies every pinned file hash, parses nested/sparse tensors without
loading external data, rejects dependencies absent from the manifest, and invokes
the ONNX checker. `engine/runtime_policy.py` invokes the supported 1.17.3
`disable_telemetry_events()` API before creating options or sessions. This is an
ORT process policy, not a claim to control Windows-wide telemetry or prove a
network block. `tests/check-privacy.py` delegates to the actual API while tracing
the production worker's order, with one small prepared Fast inference.
The native-import checker reads normal and delayed PE imports, classifies bundled
libraries versus Windows/API-set dependencies, and verifies that the pinned ORT
MSVCP140 named-import list matches the installer/startup export gate. It never
copies System32 files. This separates package isolation from the explicit system
VC++ prerequisite; it does not claim a clean-machine native closure.

Inference checks must use already prepared files. Do not run the old macOS
Python package installation on Windows or use macOS test success as Windows
evidence. No model weights may be uploaded to GitHub, including hidden inside
archives or dependency test datasets. Inspect installer files and checksums
before publishing. Retain relative public reports; keep local paths private.

## Release

Windows versions are independent: `apps/windows/VERSION`, assembly information,
installer metadata and release notes must agree. First tag:
`windows-v0.1.0-preview.1`. It must not trigger the macOS `v*` workflow.
Use the reviewed merged commit as tag target. Publish only
`NCFImageUpscaler-0.1.0-preview.1-windows-x64-setup.exe` and `SHA256SUMS.txt` in
a GitHub prerelease, without marking it latest. Verify downloaded asset hashes
and the release flags before completion. Keep stable macOS downloads prominent.

The separate Windows workflow keeps PR/build permissions read-only. Only a
trusted `push` of the exact `windows-v` version tag can upload those two allowlisted
files between jobs and invoke a separate contents-write job. That job checks the
clean build/source commit and hashes, creates a **draft** prerelease with
`make_latest=false`, uploads only the setup/checksums, and downloads them again
to verify hashes. It does not publish. An existing release (draft or published)
causes a safe failure instead of replacement. Final publication remains a separate
reviewed operation. Local builds use scratch space inside the chosen build root;
developer artifacts can stay entirely on D:.
