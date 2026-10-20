"""Reference for the detection core: the post-processing of the Java and Objective-C++
bridges, over Python onnxruntime on the CPU.

    python3 reference.py MODEL IMAGE OUT.bin   # writes the NCHW input, prints detections
"""
import sys

import numpy as np
import onnxruntime as ort
from PIL import Image

model, image, out = sys.argv[1:4]
img = Image.open(image).convert("RGB").resize((640, 640), Image.BILINEAR)
x = (np.asarray(img, dtype=np.float32) / 255.0).transpose(2, 0, 1)[None].copy()
x.tofile(out)

s = ort.InferenceSession(model, providers=["CPUExecutionProvider"])
raw = s.get_modelmeta().custom_metadata_map.get("names")
names = {}
if raw:
    import re
    for m in re.finditer(r"(\d+):\s*['\"]([^'\"]*)['\"]", raw):
        names[int(m.group(1))] = m.group(2)
y = s.run(["output0"], {"images": x})[0].reshape(-1)
conf_threshold = float(sys.argv[4]) if len(sys.argv) > 4 else 0.25
scale = np.float32(1.0) / np.float32(640)
dets = []
for i in range(300):
    p = y[i * 38:(i + 1) * 38]
    if p[4] < conf_threshold:
        continue
    x1, y1, x2, y2 = (float(np.clip(v * scale, 0, 1)) for v in p[:4])
    w, h = x2 - x1, y2 - y1
    if w <= 0 or h <= 0:
        continue
    c = int(p[5])
    dets.append((x1, y1, w, h, float(p[4]), c, names.get(c, str(c))))
dets.sort(key=lambda d: -d[4])


def iou(a, b):
    iw = max(0.0, min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0]))
    ih = max(0.0, min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1]))
    inter = iw * ih
    if inter == 0:
        return 0.0
    ua = a[2] * a[3] + b[2] * b[3] - inter
    return inter / ua if ua > 0 else 0.0


keep, gone = [], set()
for i, d in enumerate(dets):
    if i in gone:
        continue
    keep.append(d)
    for j in range(i + 1, len(dets)):
        if j not in gone and iou(d, dets[j]) > 0.45:
            gone.add(j)
for d in keep[:50]:
    print("%.4f %.4f %.4f %.4f %.4f %d %s" % d)
