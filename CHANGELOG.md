# Changelog

## 1.0.1

### Fixed

- **iOS could not build from a clean install: `'onnxruntime/onnxruntime_cxx_api.h' file not found`.** The xcframework is downloaded rather than committed, and the script that fetched it pointed at a GitHub release asset that does not exist — ONNX Runtime publishes the iOS build through CocoaPods and has never shipped an `onnxruntime-ios-xcframework-*.zip` release. `curl` saved the 9-byte "Not Found" body, `unzip` then failed with *"cannot find zipfile directory"*, and the real cause read as a corrupt download rather than a wrong URL. It now fetches from `download.onnxruntime.ai`, which is where the podspec was already looking.

  There were two downloaders disagreeing about the source: the podspec's inline `prepare_command` used the correct URL, `scripts/download_onnxruntime.sh` used the invented one. The podspec now calls the script, so there is one place that knows where the framework comes from.

  The script also resolves its destination absolutely instead of relative to the working directory, and passes `curl -fL`, so an HTTP error fails at the download rather than three steps later at compile time.

## 1.0.0

First published release. The ONNX Runtime inference provider behind `ViroObjectDetector`: an Objective-C++ provider over `onnxruntime.xcframework` on iOS, a Java module using the NNAPI execution provider on Android, and an Expo config plugin that wires both.
