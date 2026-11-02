# NCF Image Upscaler for Windows 0.1.0

Local CPU image enhancement. No accounts or hosted processing.
Unsigned Windows x64 installer; tested on Windows 10 x64 build 19045.
Windows 11, GPU execution and full native macOS parity are not validated.

The application installs for the current user, without admin **if .NET Framework
4.8 and a suitable Microsoft Visual C++ x64 Runtime are already available**.
Setup checks prerequisites before copying program files. Installing missing
system prerequisites may require administrator permission. Use the official
[Microsoft Visual C++ download](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist),
not individual DLL downloads. Python is included; no developer tools are needed.

**No weights in the installer or GitHub assets.** Missing/damaged models are
prepared automatically from Hugging Face (about 150 MiB for all presets), with
visible progress and Cancel. Valid caches need no network. Models offers repair
and retry; failed/cancelled setup does not start inference or silently retry.
Files are pinned and verified before atomic publication; the image worker never
downloads. A pending enhancement starts only if source/preset/window remain current.
The ORT platform telemetry API is explicitly disabled before session processing.
OS-wide telemetry/network isolation is not claimed.

Photo / Illustration / Fast; ×1 / ×2 / ×4; partial RGBA and ICC preservation;
original/result comparison; separate PNG export and original/alias protection.
Large CPU jobs may be slow or safely resource-limited. Photo ×1/×2 remains
untiled. Uninstall removes program files and shortcuts, retaining downloaded
models, preferences and user originals/results.

Verify `SHA256SUMS.txt`. Keep the macOS stable download separate; this release is
an independent Windows release and must not be marked latest.
