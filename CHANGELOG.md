# Changelog

## 1.0.2

### Fixed

- **Android: the Expo plugin injects `onnxruntime-android` 1.22.0, the version the library declares.** It wrote 1.20.0, whose prebuilt `libonnxruntime4j_jni.so` is not 16 KB-page aligned, which Android 15+ and Google Play reject. Gradle usually resolved the conflict up to 1.22.0, but an app with `resolutionStrategy.force`, a BOM or a lock file got 1.20.0 and had its upload refused. The version is now one exported constant, `ONNX_RUNTIME_VERSION`.
- **iOS: `getVersion()` returns the ONNX Runtime version.** No React Native module was registered on iOS, so `NativeModules.ViroONNX` was undefined and the call returned `'unavailable'` on every device. A small bridge module, `ViroONNXModule`, forwards to the provider's existing `+ortVersion`; the pod now depends on `React-Core`.

## 1.0.1

### Fixed

- **iOS could not build from a clean install: `'onnxruntime/onnxruntime_cxx_api.h' file not found`.** The xcframework is downloaded rather than committed, and the script that fetched it pointed at a GitHub release asset that does not exist — ONNX Runtime publishes the iOS build through CocoaPods and has never shipped an `onnxruntime-ios-xcframework-*.zip` release. `curl` saved the 9-byte "Not Found" body, `unzip` then failed with *"cannot find zipfile directory"*, and the real cause read as a corrupt download rather than a wrong URL. It now fetches from `download.onnxruntime.ai`, which is where the podspec was already looking.

  There were two downloaders disagreeing about the source: the podspec's inline `prepare_command` used the correct URL, `scripts/download_onnxruntime.sh` used the invented one. The podspec now calls the script, so there is one place that knows where the framework comes from.

  The script also resolves its destination absolutely instead of relative to the working directory, and passes `curl -fL`, so an HTTP error fails at the download rather than three steps later at compile time.

## 1.0.0

First published release. The ONNX Runtime inference provider behind `ViroObjectDetector`: an Objective-C++ provider over `onnxruntime.xcframework` on iOS, a Java module using the NNAPI execution provider on Android, and an Expo config plugin that wires both.
