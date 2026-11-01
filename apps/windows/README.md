# NCF Image Upscaler for Windows

Experimental CPU preview. Windows 10 x64 build 19045 is the tested environment;
Windows 11 and GPU execution have not been validated. This is independently
versioned from the macOS application. Full native interaction/visual parity is
not yet verified.

## Install and use

Run the Windows setup executable. The application installs per-user without
administrator privileges **when system prerequisites are already installed**:
.NET Framework 4.8 and a suitable Microsoft Visual C++ 2015–2022 Redistributable
(x64, version 14.29 or newer with the required ORT exports). Setup checks them
before copying the app; startup also checks the native runtime. Installing a
missing system prerequisite may require administrator permission. Get the
[VC++ Runtime from Microsoft](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist).
Python is included. The preview is unsigned.

1. Open the application. If models are missing or damaged, visible setup starts
   automatically and prepares the required files from public Hugging Face.
2. Progress, model sizes and Cancel are shown. Every file is verified with SHA-256
   before atomic publication; incomplete files are never used. Ready files are
   reused without network. **Models…** offers an explicit repair/retry action.
3. Open an image or folder, choose Photo / Illustration / Fast and ×1 / ×2 / ×4,
   then Enhance. After preparation, processing requires no network or account.
4. Compare the original/result and choose Save or Save As to export a separate
   PNG. The input is protected, including filesystem aliases.

The installer contains no model weights. Models are not distributed through
GitHub. If Enhance needs an absent or corrupt artifact, it completes visible
preparation first, then starts the local worker only if the same image/preset
is still current. Cancel/error preserves prior results and does not start a
worker or silently retry. The image inference engine never downloads models.

## Storage and removal

- Program: `%LOCALAPPDATA%\Programs\NCF Image Upscaler` by default.
- Downloaded models: `%LOCALAPPDATA%\NCF Image Upscaler\models`.
- Private temporary results: `%LOCALAPPDATA%\NCF Image Upscaler\sessions`.
- Preferences: application data under `%LOCALAPPDATA%\NCF Image Upscaler`.
- Save exports belong to the user-selected folder.

Use Windows Installed Apps to uninstall. The uninstaller removes installed program
files and shortcuts; downloaded models, preferences and user images are retained.
Close the app before manually removing its retained application data.

## Limits

CPU only, four inference threads. The worker has an 8 GiB committed-memory guard
and checks system memory reserves; large images may fail safely. Photo ×1/×2
uses the untiled native ×2 model; its former experimental tiled path is disabled.
The other presets use tiled native ×4 inference. Processing may be slow; progress
is based on completed tiles, with stage/elapsed time for full-frame processing.

Windows uses separately pinned public ONNX conversions. These differ from the
earlier MLX-FP16-derived local Windows research models. Neither numerical identity
with macOS nor broad photographic quality is claimed. Canonical-folder alias
routing, some native shell/clipboard/accessibility interactions, exact shared
app-icon raster parity and full native desktop flows remain unverified/incomplete.
OS-level network isolation has not been tested. First preparation needs internet.

Build and release instructions are in `docs/windows-build.md` at the repository
root. Model provenance and exact pins are in `models.json` and the included model
cards. Never place model weights in an installer, Git commit or GitHub asset.
