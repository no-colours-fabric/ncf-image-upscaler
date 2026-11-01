# Windows application

- This is an experimental Windows CPU application, independently versioned from
  macOS. Do not change the macOS source, dependency pins or `v*` release workflow
  as part of Windows changes.
- English interface and diagnostics. Preserve Unicode paths, input/alias safety,
  partial alpha, private unsaved results and per-window cancellation.
- Installation is per-user under `%LOCALAPPDATA%\Programs\NCF Image Upscaler`.
  Models are separate under `%LOCALAPPDATA%\NCF Image Upscaler\models`;
  sessions and preferences use that same application data root. Uninstall keeps
  models and user images. Never ship weights inside an installer or GitHub asset.
- Network access is restricted to explicit model preparation and developer
  dependency preparation. Enhance must never initiate downloads. Pin every
  download by revision, size and SHA-256; verify before atomic publication.
- `models.json` and the Windows dependency lock describe Windows artifacts only.
  Never mechanically replace macOS pins or claim numerical MLX parity.
- Keep environments, caches, downloaded tools, models and binary builds outside
  Git. Scripts must accept an external build root; no personal/research paths.
- Run relevant Windows component/worker/installer checks. Label controlled WPF
  harness evidence separately from native desktop input and manual observations.
- Preserve licenses/notices. Public reports contain relative paths, safe samples
  and necessary OS/runtime versions only. Do not publish usernames or hostnames.
