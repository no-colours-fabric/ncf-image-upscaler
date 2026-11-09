# Platform architecture

One repository, two independently delivered applications. macOS remains the
available Apple Silicon application and CLI. Windows is a GPU/CPU application with
separate source, dependencies, model format, installer and version.
Windows 10 tests include DirectML on Intel UHD Graphics and CPU fallback.
Windows 11 and other GPU vendors are not validated.

## Platform boundaries

Keep `native/`, `src/`, `uv.lock`, the MLX manifest and the macOS DMG/release
workflow in place. Windows lives in `apps/windows`; there is no mechanical move
of working macOS code. Windows `windows-v*` tags do not match the macOS `v*`
release trigger. Existing `v0.4.0` and historical releases stay intact.

Windows uses WPF on .NET Framework 4.8 and a bundled CPython/ONNX Runtime DirectML
worker with CPU fallback. macOS uses Swift/AppKit and Python/MLX. The shared Python
`imaging.upscale_image()` pipeline is copied at build time into the standalone
Windows payload; it has no UI or MLX dependency. Do not infer that the entire
Python package (which declares MLX and Python >=3.12) is installed on Windows.

Windows installation is per-user without elevation only when system .NET 4.8
and the suitable Microsoft Visual C++ x64 Runtime prerequisite are available.
Missing system prerequisites may require administrator permission to install;
the program does not install them automatically or copy system DLLs. ORT's
supported telemetry opt-out is applied before session processing.

The worker protocol is process arguments plus JSON Lines events on stdout,
with diagnostics on stderr, not a long-lived server. Events report started,
progress, completed and errors; Windows also reports preparation/inference/
finishing stages. Cancellation is a UI request followed by actual process exit.
The macOS UI may terminate the worker without receiving its Python `cancelled`
event; event, exit code/signal and user cancellation are distinct facts.

## Shared behavior

English interfaces; no accounts, payment, telemetry or hosted image processing.
Downloads occur during preparation: Windows automatically shows cancellable
setup for missing models before inference; macOS keeps its explicit action.
Preserve partial RGBA, ICC and
declared EXIF orientation behavior; never flatten the image or replace an input.
Processing produces a private result; Save exports a separate PNG with a free
name or explicit overwrite confirmation and alias protection.

The target common presets are Photo / Illustration / Fast and ×1 / ×2 / ×4.
Windows Photo ×1/×2 uses native ×2 (downsample for ×1); Photo ×4 uses native ×4.
Illustration and Fast use native ×4 then resize for ×1/×2. Similar controls do not
establish equal RGB or photographic quality across different model conversions.

Keep a familiar floating panel, folder grids, registered original/result viewer,
progress/cancel and unsaved-result lifecycle. OS dialogs, fonts and shell APIs
may differ. Reuse project-owned artwork sources; Windows embeds pinned portable
SVGs for actions, while adopting those SVGs on macOS remains a separate proposal.
Actual shared app-icon raster parity is still unverified.

Updated common desired behavior: Locate reveals once, then manual scrolling
remains free; Escape closes only the current image window via normal unsaved/
worker-close handling. Windows Preview08 has controlled component evidence.
The installed Mac 0.4.0 build3 was observed to satisfy the tested Locate scenarios
but to quit all windows on Escape. This document does not claim a Mac fix.

## Data and downloads

macOS keeps its existing Application Support data root. Windows installs per-user
under `%LOCALAPPDATA%\Programs\NCF Image Upscaler`; models, sessions and preferences
use `%LOCALAPPDATA%\NCF Image Upscaler`. These are separately implemented policies.
Windows uninstall removes installed program files, retaining model caches and
user images/results. Existing research/build folders are not installation input.

Windows installers and GitHub assets contain **no model weights**. Visible,
cancellable setup automatically prepares missing/damaged pinned public Hugging
Face ONNX files at first use or before requested enhancement. It checks size and
SHA-256 and atomically publishes each complete cache entry. Verified caches do
not cause network requests. Models remains available for repair/retry; cancelled
or failed preparation never starts a worker or causes hidden retries. A pending
enhancement checks source/preset/window state again before starting. The image
worker never downloads. First preparation requires internet; subsequent inference
is local. OS-level network-block verification remains outstanding.

## Verification and releases

Use independent platform checks, versions and release notes. Tests must distinguish
real native input from scripted WPF components and actual worker execution from
synthetic injected results. Small functional timings do not establish typical
FullHD speed or hardware minimums. Full native parity is not claimed.

Windows 0.2.0 uses `windows-v0.2.0` and a non-latest GitHub
release, independently of macOS. Review source/privacy/licenses, the pinned
downloads, installer contents and install/preparation/processing/removal results
before merge/publication. Keep binaries, environments, caches and weights out of
Git, and personal paths/identifiers/private photos out of public reports.

Windows 0.2.0 adds capability-gated GPU On/Off, profiled provider diagnostics,
three saved appearances and compact taskbar-aware window chrome. No model or
macOS runtime change is implied. GPU performance is workload-specific; the first
compiled forward can be slower than CPU.
