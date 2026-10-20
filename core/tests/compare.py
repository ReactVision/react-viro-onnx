"""compare.py REF OUT [TOL]: the same detections in the same order, the class index and
label exact, the numbers within TOL (default 0.002). Different ONNX Runtime versions
round the last digits differently."""
import sys

ref = [l.split(" ", 6) for l in open(sys.argv[1]).read().splitlines()]
out = [l.split(" ", 6) for l in open(sys.argv[2]).read().splitlines()]
tol = float(sys.argv[3]) if len(sys.argv) > 3 else 0.002
if len(ref) != len(out):
    sys.exit("%d detections, want %d" % (len(out), len(ref)))
for i, (r, o) in enumerate(zip(ref, out)):
    if r[5:] != o[5:] or any(abs(float(a) - float(b)) > tol for a, b in zip(r[:5], o[:5])):
        sys.exit("detection %d: %s, want %s" % (i, " ".join(o), " ".join(r)))
