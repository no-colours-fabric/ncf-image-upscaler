"""Explicit local asset decoding; no dependency or model downloads."""

import json
import sys
from pathlib import Path

if sys.argv[1] == "--sizes":
    from PIL import Image

    sizes = {}
    for path in json.loads(Path(sys.argv[2]).read_text(encoding="utf-8-sig")):
        try:
            with Image.open(path) as image:
                w, h = image.size
                if image.getexif().get(274, 1) in {5, 6, 7, 8}:
                    w, h = h, w
                sizes[path] = [w, h]
        except (OSError, ValueError):
            sizes[path] = None
    print(json.dumps(sizes, ensure_ascii=True))
else:
    from ncf_image_upscaler.imaging import open_image

    source, destination = map(Path, sys.argv[1:])
    image, icc = open_image(source)
    with destination.open("xb") as stream:
        image.save(stream, format="PNG", **({"icc_profile": icc} if icc else {}))
    image.close()
