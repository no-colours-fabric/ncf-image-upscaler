# User guide

## Native app

### First launch and model setup

Install the [Apple Silicon DMG](https://github.com/no-colours-fabric/image-upscaler/releases/latest)
or use the [source installer](installation.md#install-or-update-from-source).
The DMG includes its engine; no separate Python or Xcode installation is needed.

On the DMG app's first launch, wait for the bundled engine to be installed locally.
In **Image Upscaler Setup**, choose **Download Models** to fetch all four models
(about 78 MB). This is the step that needs an internet connection.
Wait for **Ready for offline image processing.** before enhancing images.

Use **Cancel Download** to stop a download. You can reopen setup with
**Image Upscaler → Models…** and retry; successfully installed models are retained.
When all models are installed, **Verify Again** checks them without network access.
Processing never downloads a missing model automatically.

### Open and enhance an image

Open an image or folder with **⌘O**, drag it into the window, or use Finder's
**Open With → Image Upscaler**. Each folder gets its own window. The sidebar
shows supported images in that folder, excluding hidden files and subfolders.

Select **Photo**, **Illustration**, or **Fast**, choose **×1**, **×2**, or **×4**,
and click **Enhance** (**⌘U**). Progress and cancellation are available while
processing. One image is processed at a time in each window; you can browse
other images while it runs. Each file retains its result and viewing position
for the current session.

### Browse and compare

- **Z** moves to the previous image; **X** or **Space** moves to the next.
  Physical key positions work across keyboard layouts. Navigation stops at the ends.
- Click a thumbnail to select it. **⌘-click** toggles selection and **Shift-click**
  selects a range. Drag a selection rectangle, use arrow keys, or press **⌘A**
  for all visible files and **⌘⌥A** to deselect.
- **Page Up / Page Down** move by a visible thumbnail page; **Home / End** and
  **⌘↑ / ⌘↓** move to the ends. Hold **Shift** to extend selection. On Mac keyboards,
  these keys are **Fn↑ / Fn↓ / Fn← / Fn→**.
- Filter by filename and sort by name, modification date, creation date, size,
  or type, in either direction. Navigation follows the visible sorted list.
- Resize the sidebar by dragging its right edge. Use the slider for thumbnail
  size and the grid buttons for regular or adaptive layout. Adaptive layout
  preserves image proportions without cropping. Collapse the sidebar using its
  header; the target button finds the current thumbnail. Layout preferences persist.
- Scroll or pinch to zoom; drag to pan. **⌘0** fits the image, **⌘1** sets 100%,
  and **⌘+ / ⌘−** change zoom. Double-click toggles fitting and 100%.
  Small images initially open at 100%; explicit fitting can enlarge them.
- Drag the comparison divider: the original is on the left, the result on the
  right. Both share the same zoom and position. A fixed checkerboard shows
  transparency; it is never added to the output file.

Text fields and dialogs retain normal macOS editing and navigation shortcuts.

### Save and manage files

**Save** (**⌘S**) creates a PNG beside the original. Occupied names get a numeric
suffix: `photo_4x.png`, `photo_4x_2.png`, and so on. Saving the same result again
does not create an extra copy. **Save As…** (**⌘⇧S**) chooses another destination;
the original is always protected, including aliases through symbolic or hard links.

Unsaved results have a sparkle indicator. Closing a window or quitting asks about
each unsaved result: save, discard, or cancel. Failed saves keep the result available.

Right-click thumbnails for actions on the selection, or right-click the main image
for actions on that image. Supported actions include:

| Action | Shortcut |
| --- | --- |
| Rename one file | Return |
| Duplicate selected files | ⌘D |
| Copy files / paste into this folder | ⌘C / ⌘V |
| Move clipboard files here | ⌘⌥V |
| Move to Trash | ⌘⌫ |
| Delete permanently, with confirmation | ⌘⌥⌫ |
| Undo / redo supported file operations | ⌘Z / ⌘⇧Z |

The menus also provide paths, Get Info, Show in Finder, Open With, and batch saving
or discarding of unsaved enhancements. Permanent deletion cannot be undone.
File drags work with Finder; files dropped onto the sidebar are copied without
replacing existing files. Copy Image and Copy Enhanced Image include transparency,
without the preview checkerboard. Pasting image data creates a separate PNG.

External folder changes are tracked. Renaming retains the current enhancement;
if an original disappears externally, an unsaved result remains available to save.
Changing a file being processed is disabled until processing finishes.

## CLI

```sh
upscale input.png --scale 4 --model photo
upscale input.png --scale 1 --output enhanced.png
upscale input.png --model fast --tile 128 --quiet
```

| Option | Behavior |
| --- | --- |
| `--scale 1`, `2`, `4` | Output multiplier; default 4 |
| `--model photo`, `anime`, `fast` | Model preset; default photo |
| `-o`, `--output` | Output PNG; defaults beside the original |
| `--tile` | Even tile size of at least 32; default 256 |
| `--overwrite` | Allow replacing an output, never the input |
| `--quiet` | Print only the absolute output path to stdout |
| `--help`, `--version` | Help and version |

Diagnostics and progress go to stderr. Processing returns 0 on success, 1 on a
runtime error, 2 for invalid arguments, and 130 when interrupted.

## Models

| Preset | Model | Weight size | Native scale |
| --- | --- | --- | --- |
| Photo | RealESRGAN_x4plus / RealESRGAN_x2plus | ~33.5 MB each | ×4 / ×2 |
| Illustration (`anime`) | RealESRGAN_x4plus_anime_6B | ~9 MB | ×4 |
| Fast | realesr-general-x4v3 | ~2.4 MB | ×4 |

At ×1, Photo uses the ×2 model. The other presets use their ×4 models at all
output sizes. RGB is resized with Lanczos to the requested final dimensions.
Alpha is copied unchanged at ×1, or resized directly to the final size otherwise.

```sh
upscale models list
upscale models download x4plus
upscale models download x2plus
upscale models download anime
upscale models download fast
upscale models download all
upscale models verify
```

Downloads are explicit and require no account. Valid installed weights are reused
without network access. A missing or corrupted model causes processing to fail
with an instruction to download it; processing never installs it automatically.

## Transparency and formats

The pipeline supports ordinary single-frame 8-bit images readable by Pillow,
including PNG, JPEG, WebP, TIFF, and BMP. The app's file picker and folder browser
use those five formats. RGBA, grayscale with alpha, palette transparency, and
transparent-color PNG are handled. EXIF orientation is applied before processing.

Invisible RGB is extended from the nearest visible pixel before neural inference,
so hidden black or white pixels do not contaminate colored edges. The RGB model
does not infer alpha. Partial alpha and soft shadows remain separate from RGB;
no background is flattened into the output.

ICC profiles are retained. Other EXIF metadata is omitted. Animations, multipage
files, HDR, and 16-bit workflows are unsupported. Some high-bit-depth inputs may
be decoded to 8-bit by Pillow; they will not retain their original precision.
