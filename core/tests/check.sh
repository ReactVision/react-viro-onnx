#!/usr/bin/env bash
# Checks the Eskiu core against tests/reference.py (Python onnxruntime, CPU) on a few
# images and thresholds, through the C API (detect.esk) and the JNI entry points
# (jni_fake.c). Needs eskiuc, Python onnxruntime + Pillow, and ONNX Runtime at $ORT
# (default: Homebrew).
#
#   MODEL=path/to/yoloe-26n.onnx tests/check.sh IMAGE...
set -euo pipefail
cd "$(dirname "$0")/.."
ORT="${ORT:-$(brew --prefix onnxruntime 2>/dev/null)}"
MODEL="${MODEL:?set MODEL to a YOLOE .onnx}"
ESKIUC="${ESKIUC:-eskiuc}"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
"$ESKIUC" tests/detect.esk -o "$out/detect" -L"$ORT/lib" --link-arg=-Wl,-rpath,"$ORT/lib"
"$ESKIUC" src/android.esk -c -o "$out/android.o"
cc tests/jni_fake.c "$out/android.o" -L"$ORT/lib" -lonnxruntime -Wl,-rpath,"$ORT/lib" -lpthread -lm -o "$out/jni_fake"
fail=0
for img in "$@"; do
    for conf in 0.25 0.05 0.01; do
        python3 tests/reference.py "$MODEL" "$img" "$out/in.bin" "$conf" > "$out/ref"
        "$out/detect" "$MODEL" "$out/in.bin" "$conf" > "$out/c"
        "$out/jni_fake" "$MODEL" "$out/in.bin" "$conf" > "$out/j"
        if diff -q "$out/ref" "$out/c" > /dev/null && diff -q "$out/ref" "$out/j" > /dev/null; then
            echo "PASS $(basename "$img") conf=$conf ($(wc -l < "$out/ref" | tr -d ' ') detections)"
        else
            echo "FAIL $(basename "$img") conf=$conf"
            diff "$out/ref" "$out/c" | head -5 || true
            fail=1
        fi
    done
done
exit $fail
