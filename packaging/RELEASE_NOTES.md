Download **ImageUpscaler-0.3.0-arm64.dmg** below. Requires Apple Silicon and macOS 14 or later.

### Install

1. Open the DMG and drag **Image Upscaler** into **Applications**.
2. Open the app. Its bundled engine is installed locally; Python and Xcode are not required.
3. Choose **Download Models** in the setup window. All presets total approximately 78 MB.
4. Open an image, choose a preset and scale, and click **Enhance**. Save the result separately.

The app and processing are free. There are no accounts, activation, telemetry, or hosted inference.
Model downloads are explicit. Once set up, processing works offline.

### Not notarized by Apple

This build has a local ad-hoc signature, **not** an Apple Developer ID signature or Apple notarization.
macOS may block its first launch. If you trust this release and have checked its source and checksum,
use **System Settings → Privacy & Security → Open Anyway**, then confirm **Open**.
See [Apple's instructions](https://support.apple.com/en-us/102445).
Do not override a warning that macOS detected malware or a damaged application.

### Changes in 0.3.0

- A standalone, relocatable Python/MLX engine, pinned and verified during packaging.
- Offline first-launch engine installation into Application Support, separate from source installations.
- Native model setup with explicit download, progress, cancellation, and verification.
- Bundled third-party and Python license notices; SHA-256 checksum for the DMG.
- Automated verification of a relocated app and runtime without system Python or downloaded models.

The pipeline uses 8-bit RGB/RGBA. Animations, multipage images, HDR, and 16-bit workflows are unsupported.
The alpha channel is preserved independently; the model does not reconstruct the alpha mask.
