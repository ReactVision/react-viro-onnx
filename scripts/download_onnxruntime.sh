#!/usr/bin/env bash
#
# Fetches onnxruntime.xcframework (dynamic, iOS) into ios/dist/Frameworks.
#
# This is the single source of truth for that download. The podspec calls it from both
# `prepare_command` and a `script_phase`, and it is safe to run by hand.
#
# It comes from ONNX Runtime's own pod archive, not from a GitHub release: Microsoft
# distributes the iOS build through CocoaPods and publishes no iOS xcframework as a
# release asset. An earlier version of this script pointed at
# `github.com/microsoft/onnxruntime/releases/.../onnxruntime-ios-xcframework-*.zip`,
# which has never existed — curl saved the 9-byte "Not Found" body and unzip then failed
# with "cannot find zipfile directory", which reads as a corrupt download rather than a
# wrong URL.
#
# The dynamic xcframework is used rather than the `onnxruntime-c` pod because that pod is
# `static_framework = true`, which conflicts with `use_frameworks! :linkage => :dynamic`.
#
# Idempotent: does nothing when the framework is already in place.

set -euo pipefail

ONNX_VERSION="${ONNX_VERSION:-1.20.0}"
DEST="$(cd "$(dirname "$0")/.." && pwd)/ios/dist/Frameworks"
XCFWK="$DEST/onnxruntime.xcframework"

if [ -d "$XCFWK" ]; then
  echo "react-viro-onnx: onnxruntime.xcframework already present, skipping."
  exit 0
fi

ZIP_URL="https://download.onnxruntime.ai/pod-archive-onnxruntime-c-${ONNX_VERSION}.zip"
TMP_ZIP="$(mktemp -t ort-ios-XXXXXX).zip"
trap 'rm -f "$TMP_ZIP"' EXIT

echo "react-viro-onnx: downloading onnxruntime.xcframework v${ONNX_VERSION}..."
# --fail so an HTTP error is an error here, at the download, and not later as a
# confusing unzip failure or a missing header at compile time.
curl -fL "$ZIP_URL" -o "$TMP_ZIP"

mkdir -p "$DEST"
unzip -q "$TMP_ZIP" "onnxruntime.xcframework/*" -d "$DEST"

if [ ! -f "$XCFWK/ios-arm64/onnxruntime.framework/Headers/onnxruntime_cxx_api.h" ]; then
  echo "react-viro-onnx: the archive unpacked but the expected header is missing." >&2
  exit 1
fi

echo "react-viro-onnx: onnxruntime.xcframework ready at $XCFWK"
