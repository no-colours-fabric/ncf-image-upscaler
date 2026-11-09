"""Local RGB inference; shared by worker and bounded tiling checks."""

import numpy as np


class OnnxEngine:
    def __init__(self, session, key, native, total, emit):
        self.session, self.key, self.native, self.total, self.emit = (
            session,
            key,
            native,
            total,
            emit,
        )
        self.count = 0

    def forward(self, rgb):
        value = np.ascontiguousarray(rgb.transpose(2, 0, 1)[None], dtype=np.float32) / 255
        result = self.session.run(None, {"input": value})[0][0].transpose(1, 2, 0)
        if not np.isfinite(result).all():
            raise RuntimeError("The model returned invalid pixel values.")
        return result

    def upscale(self, rgb, progress=None):
        key, native, total, emit = self.key, self.native, self.total, self.emit
        emit("phase", phase="inference")
        h, w = rgb.shape[:2]
        if key == "photo2":
            padded = np.pad(rgb, ((0, h % 2), (0, w % 2), (0, 0)), mode="reflect")
            out = self.forward(padded)[: h * native, : w * native]
            self.count = 1
            emit("progress", completed=1, total=1)
            result = np.rint(np.clip(out, 0, 1) * 255).astype(np.uint8)
            emit("phase", phase="finishing")
            return result
        result = np.empty((h * native, w * native, 3), dtype=np.uint8)
        for y in range(0, h, 256):
            for x in range(0, w, 256):
                y1, x1 = min(y + 256, h), min(x + 256, w)
                ya, xa, yb, xb = max(0, y - 64), max(0, x - 64), min(h, y1 + 64), min(w, x1 + 64)
                out = self.forward(rgb[ya:yb, xa:xb])
                crop = out[
                    (y - ya) * native : (y1 - ya) * native, (x - xa) * native : (x1 - xa) * native
                ]
                result[y * native : y1 * native, x * native : x1 * native] = np.rint(
                    np.clip(crop, 0, 1) * 255
                ).astype(np.uint8)
                self.count += 1
                emit("progress", completed=self.count, total=total)
        emit("phase", phase="finishing")
        return result
