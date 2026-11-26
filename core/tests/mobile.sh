#!/usr/bin/env bash
# Runs tests/capi.c against the built libraries (scripts/build_core.sh) on a booted iOS
# simulator and a connected arm64 Android device or emulator, and compares the output
# with tests/reference.py (tests/compare.py: within rounding of other ORT versions). Needs Xcode, the Android NDK and adb.
#
#   MODEL=path/to/yoloe-26n.onnx IMAGE=photo.jpg [SIM=udid] [ACCEL=2] tests/mobile.sh [ios] [android]
#
# ACCEL picks the iOS provider (viro_onnx.h: 0 CPU, 2 CoreML).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(cd .. && pwd)"
MODEL="${MODEL:?set MODEL}"
IMAGE="${IMAGE:?set IMAGE}"
SIM="${SIM:-booted}"
CONF="${CONF:-0.05}"
ACCEL="${ACCEL:-0}"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
python3 tests/reference.py "$MODEL" "$IMAGE" "$out/in.bin" "$CONF" > "$out/ref"
targets=("$@")
[ ${#targets[@]} -eq 0 ] && targets=(ios android)
fail=0
for t in "${targets[@]}"; do
    case "$t" in
    ios)
        ort="$ROOT/ios/dist/Frameworks/onnxruntime.xcframework/ios-arm64_x86_64-simulator"
        xcrun -sdk iphonesimulator clang -target arm64-apple-ios14.0-simulator -Iinclude tests/capi.c \
            "$ROOT/ios/dist/ViroONNXCore.xcframework/ios-arm64_x86_64-simulator/libviro_onnx.a" \
            -F"$ort" -framework onnxruntime -lc++ -framework Foundation -framework CoreML -o "$out/capi_ios"
        xcrun simctl spawn "$SIM" "$out/capi_ios" "$MODEL" "$out/in.bin" "$CONF" "$ACCEL" > "$out/ios" ;;
    android)
        ndk="${ANDROID_NDK_HOME:-$(ls -d "$HOME"/Library/Android/sdk/ndk/* | sort -V | tail -1)}"
        cc="$(ls "$ndk"/toolchains/llvm/prebuilt/*/bin/clang)"
        so="$ROOT/android/src/main/jniLibs/arm64-v8a"
        ort="$(ls -d build/onnxruntime-android-*/jni/arm64-v8a | tail -1)"
        "$cc" --target=aarch64-linux-android24 -Iinclude tests/capi.c -L"$so" -lviro_onnx -o "$out/capi_android"
        d=/data/local/tmp/viro_onnx
        adb shell mkdir -p $d
        for f in "$MODEL" "$out/in.bin" "$out/capi_android" "$so/libviro_onnx.so" "$ort/libonnxruntime.so"; do adb push "$f" $d/ > /dev/null; done
        # The emulator on Apple M4 hosts reports SME, which ONNX Runtime's KleidiAI kernels
        # cannot run there. ONNX Runtime 1.22 aborts at exit when the environment is not
        # released; the detections are printed before that.
        adb shell "cd $d && LD_LIBRARY_PATH=$d ONNX_CONFIG=mlas.disable_kleidiai=1 ./capi_android $(basename "$MODEL") in.bin $CONF" \
            2> /dev/null | tr -d '\r' | grep -v 'FORTIFY\|Aborted' > "$out/android" || true ;;
    *) echo "unknown target $t" >&2; exit 2 ;;
    esac
    if python3 tests/compare.py "$out/ref" "$out/$t"; then
        echo "PASS $t ($(wc -l < "$out/ref" | tr -d ' ') detections)"
    else
        echo "FAIL $t"; fail=1
    fi
done
exit $fail
