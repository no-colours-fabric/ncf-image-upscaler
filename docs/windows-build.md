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
offers a shortcut and uninstall entry, and does not require administrator rights.
It is not Authenticode-signed. Its application models are separately prepared
from `apps/windows/models.json` by the installed Models window.

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
```

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
