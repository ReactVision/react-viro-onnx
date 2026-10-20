# viro_onnx core

The detection core of `@reactvision/react-viro-onnx`, written in
[Eskiu](https://github.com/eskiu-lang/eskiu) over the [`onnx`](https://github.com/eskiu-lang/onnx)
package. Both bridges call it: `ios/ViroONNX.mm` through the C API in
[`include/viro_onnx.h`](include/viro_onnx.h), and the Android module through the JNI entry
points in `src/android.esk` (class `com.reactvision.viroonnx.ViroONNXCore`). It does what the
Objective-C++ and Java code used to do twice:

- keeps one ONNX Runtime session per model (path on iOS, bytes from the APK assets on Android,
  NNAPI with FP16 when asked, falling back to the CPU);
- reads the class names from the model's `names` metadata;
- decodes the 300 YOLOE proposals (confidence threshold, boxes normalized to [0, 1] and clamped);
- sorts by confidence, runs greedy NMS at IoU 0.45 and returns up to 50 detections.

A detection in flight keeps its session when `viro_onnx_release_all` runs (the iOS
`VRODetectorSessionReleased` notification), and class names stay valid for the life of the
process.

## Layout

| Path | |
|---|---|
| `src/viro_onnx.esk` | the core and its C API |
| `src/android.esk` | the JNI entry points (built into `libviro_onnx.so`) |
| `include/viro_onnx.h` | the C header |
| `tests/reference.py` | the bridges' post-processing in Python over onnxruntime, the oracle |
| `tests/check.sh` | the core and the JNI layer (through a fake `JNIEnv`) against the reference |
| `tests/mobile.sh` | the built libraries on an iOS simulator and an Android device or emulator |

## Building

`scripts/build_core.sh` (or `npm run build:core`) needs `eskiuc`, Xcode and the Android NDK,
and writes:

- `ios/dist/ViroONNXCore.xcframework`: a static library for the device and the simulator
  (arm64, x86_64), vendored by the podspec next to `onnxruntime.xcframework`;
- `android/src/main/jniLibs/{arm64-v8a,x86_64}/libviro_onnx.so`: 16 KB-aligned, linked
  against the `libonnxruntime.so` of the `onnxruntime-android` AAR the module depends on.

Only `viro_onnx_*` and the `Java_*` entry points are exported; the Eskiu code behind them,
standard library included, stays private to the library. Run it before `npm pack`: the
npm package ships the built libraries, so apps do not need Eskiu.

## Testing

```bash
MODEL=path/to/yoloe-26n.onnx core/tests/check.sh photo.jpg ...
MODEL=path/to/yoloe-26n.onnx IMAGE=photo.jpg core/tests/mobile.sh   # booted simulator + adb device
```

`check.sh` compares byte for byte with the reference at three thresholds. `mobile.sh` allows
for the rounding of other ONNX Runtime versions (the pod's 1.20 on iOS, the AAR's 1.22 on
Android) in the last digits.

## Platforms

arm64 and x86_64: the iOS device and simulator, Android `arm64-v8a` and `x86_64`. The 32-bit
Android ABIs (`armeabi-v7a`, `x86`) are not built yet; on those devices the provider does not
register and detection returns empty.
