#!/bin/bash
# Downloads onnxruntime.xcframework (dynamic, iOS) for react-viro-onnx.
# Called automatically by the CocoaPods prepare_command during pod install.
# Safe to run multiple times (skips download if already present).

set -e

ONNX_VERSION="1.20.0"
DEST="$(dirname "$0")/../ios/dist/Frameworks"
XCFWK="$DEST/onnxruntime.xcframework"

if [ -d "$XCFWK" ]; then
  echo "onnxruntime.xcframework already present, skipping download."
  exit 0
fi

echo "Downloading onnxruntime.xcframework v${ONNX_VERSION}..."
mkdir -p "$DEST"

ZIP_URL="https://github.com/microsoft/onnxruntime/releases/download/v${ONNX_VERSION}/onnxruntime-ios-xcframework-${ONNX_VERSION}.zip"
TMP_ZIP="/tmp/ort-ios-${ONNX_VERSION}.zip"

curl -L "$ZIP_URL" -o "$TMP_ZIP"
unzip -q "$TMP_ZIP" -d "$DEST"
rm "$TMP_ZIP"

echo "onnxruntime.xcframework ready at $XCFWK"
