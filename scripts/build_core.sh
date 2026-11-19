#!/usr/bin/env bash
#
# Builds the Eskiu detection core (core/) for the two bridges:
#
#   ios/dist/ViroONNXCore.xcframework            static library, device + simulator
#   android/src/main/jniLibs/<abi>/libviro_onnx.so   arm64-v8a, x86_64
#
# Only the C API (viro_onnx_*) and the JNI entry points (Java_*) are exported; the rest
# of the Eskiu code, stdlib included, stays private to the library, so two Eskiu
# libraries in one app do not collide.
#
# Needs eskiuc (https://eskiu.dev), Xcode for iOS and the Android NDK for Android
# ($ANDROID_NDK_HOME, or the newest ndk/ of the SDK). The Android build links against
# libonnxruntime.so from the onnxruntime-android AAR (ONNX_ANDROID_VERSION, the same
# version as android/build.gradle), downloaded once into core/build/.
#
#   scripts/build_core.sh [ios] [android]     # both by default

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/core"
BUILD="$CORE/build"
ESKIUC="${ESKIUC:-eskiuc}"
IOS_MIN="${IOS_MIN:-14.0}"
ANDROID_API="${ANDROID_API:-24}"
ONNX_ANDROID_VERSION="${ONNX_ANDROID_VERSION:-1.22.0}"

want_ios=0
want_android=0
[ $# -eq 0 ] && { want_ios=1; want_android=1; }
for a in "$@"; do
    case "$a" in
        ios) want_ios=1 ;;
        android) want_android=1 ;;
        *) echo "usage: $0 [ios] [android]" >&2; exit 2 ;;
    esac
done

mkdir -p "$BUILD"
cd "$CORE"
"$ESKIUC" fetch > /dev/null

build_ios() {
    local syms="$BUILD/ios.exports"
    printf '_viro_onnx_*\n' > "$syms"
    for t in "arm64-apple-ios$IOS_MIN" "arm64-apple-ios$IOS_MIN-simulator" "x86_64-apple-ios$IOS_MIN-simulator"; do
        local d="$BUILD/$t"
        mkdir -p "$d"
        "$ESKIUC" src/viro_onnx.esk --target "$t" -O2 -c -o "$d/viro_onnx.o"
        # A relocatable link that keeps only the exported symbols global.
        xcrun ld -r -arch "${t%%-*}" "$d/viro_onnx.o" -exported_symbols_list "$syms" -o "$d/core.o"
        rm -f "$d/libviro_onnx.a"
        xcrun libtool -static -o "$d/libviro_onnx.a" "$d/core.o" 2> /dev/null
    done
    local sim="$BUILD/ios-simulator"
    mkdir -p "$sim"
    xcrun lipo -create "$BUILD/arm64-apple-ios$IOS_MIN-simulator/libviro_onnx.a" \
        "$BUILD/x86_64-apple-ios$IOS_MIN-simulator/libviro_onnx.a" -output "$sim/libviro_onnx.a"
    local out="$ROOT/ios/dist/ViroONNXCore.xcframework"
    rm -rf "$out"
    mkdir -p "$ROOT/ios/dist"
    xcodebuild -create-xcframework \
        -library "$BUILD/arm64-apple-ios$IOS_MIN/libviro_onnx.a" -headers "$CORE/include" \
        -library "$sim/libviro_onnx.a" -headers "$CORE/include" \
        -output "$out" > /dev/null
    echo "built $out"
}

build_android() {
    local aar="$BUILD/onnxruntime-android-$ONNX_ANDROID_VERSION"
    if [ ! -d "$aar/jni" ]; then
        local url="https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/$ONNX_ANDROID_VERSION/onnxruntime-android-$ONNX_ANDROID_VERSION.aar"
        curl -fsSL "$url" -o "$aar.aar"
        mkdir -p "$aar"
        unzip -q -o "$aar.aar" 'jni/*' -d "$aar"
        rm -f "$aar.aar"
    fi
    local vs="$BUILD/android.map"
    printf '{\n  global:\n    viro_onnx_*;\n    Java_com_reactvision_viroonnx_*;\n  local:\n    *;\n};\n' > "$vs"
    for pair in arm64-v8a:aarch64-linux-android x86_64:x86_64-linux-android; do
        local abi="${pair%%:*}" triple="${pair#*:}$ANDROID_API"
        local out="$ROOT/android/src/main/jniLibs/$abi"
        mkdir -p "$out"
        "$ESKIUC" src/android.esk --target "$triple" -O2 -o "$out/libviro_onnx.so" -L"$aar/jni/$abi" \
            --link-arg=-Wl,--version-script="$vs" --link-arg=-Wl,-z,max-page-size=16384 \
            --link-arg=-Wl,--gc-sections --link-arg=-s
        echo "built $out/libviro_onnx.so"
    done
}

[ $want_ios -eq 1 ] && build_ios
[ $want_android -eq 1 ] && build_android
exit 0
