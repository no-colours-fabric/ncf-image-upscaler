# Windows application

- This is a Windows DirectML GPU/CPU application, independently versioned from
  macOS. Do not change the macOS source, dependency pins or `v*` release workflow
  as part of Windows changes.
- English interface and diagnostics. Preserve Unicode paths, input/alias safety,
  partial alpha, private unsaved results and per-window cancellation.
- Installation is per-user under `%LOCALAPPDATA%\Programs\NCF Image Upscaler`.
  Models are separate under `%LOCALAPPDATA%\NCF Image Upscaler\models`;
  sessions and preferences use that same application data root. Uninstall keeps
  models and user images. Never ship weights inside an installer or GitHub asset.
- Network access is restricted to model/developer dependency preparation.
  Missing/corrupt models are automatically prepared in visible cancellable setup
  at first use or before a requested Enhance. The inference worker never
  downloads; valid hash caches need no network. Cancel/error must not start a
  worker or trigger hidden retries. Pin revision/size/SHA and publish atomically.
- `models.json` and the Windows dependency lock describe Windows artifacts only.
  Never mechanically replace macOS pins or claim numerical MLX parity.
- Keep environments, caches, downloaded tools, models and binary builds outside
  Git. Scripts must accept an external build root; no personal/research paths.
- Run relevant Windows component/worker/installer checks. Label controlled WPF
  harness evidence separately from native desktop input and manual observations.
- Preserve licenses/notices. Public reports contain relative paths, safe samples
  and necessary OS/runtime versions only. Do not publish usernames or hostnames.

- DirectML is optional at execution time: hide the GPU control without a successful
  local capability probe; retain CPU fallback and report actual profiled providers.
  Disable ORT telemetry before both capability and image sessions. Preserve the
  separate Microsoft DirectML license and pinned native DLL/export checks.
