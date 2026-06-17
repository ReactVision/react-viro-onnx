require 'json'
package = JSON.parse(File.read(File.join(__dir__, '../package.json')))

Pod::Spec.new do |s|
  s.name             = 'ViroReactONNX'
  s.version          = package['version']
  s.summary          = 'ONNX Runtime inference provider for ViroObjectDetector'
  s.homepage         = 'https://github.com/ReactVision/react-viro-onnx'
  s.license          = { :type => 'MIT' }
  s.author           = 'ReactVision'
  s.platform         = :ios, '14.0'
  s.source           = { :git => 'https://github.com/ReactVision/react-viro-onnx.git', :tag => "v#{s.version}" }

  s.source_files     = '*.{h,m,mm}'

  # Downloads onnxruntime.xcframework (dynamic) from the official onnxruntime pod archive.
  # This avoids the static_framework = true constraint of onnxruntime-c CocoaPod.
  # The xcframework is NOT committed to git; downloaded once on first pod install.
  # prepare_command runs from the directory containing this podspec (ios/).
  s.prepare_command = <<-CMD
    set -e
    ONNX_VERSION="1.20.0"
    DEST="dist/Frameworks"
    XCFWK="$DEST/onnxruntime.xcframework"
    if [ ! -d "$XCFWK" ]; then
      echo "react-viro-onnx: downloading onnxruntime.xcframework v${ONNX_VERSION}..."
      mkdir -p "$DEST"
      curl -L "https://download.onnxruntime.ai/pod-archive-onnxruntime-c-${ONNX_VERSION}.zip" \
           -o /tmp/ort-ios.zip
      unzip -q /tmp/ort-ios.zip "onnxruntime.xcframework/*" -d "$DEST"
      rm /tmp/ort-ios.zip
      echo "react-viro-onnx: onnxruntime.xcframework ready."
    else
      echo "react-viro-onnx: onnxruntime.xcframework already present, skipping."
    fi
  CMD

  # Vendored dynamic xcframework — no static/dynamic conflict with use_frameworks! :linkage => :dynamic
  s.vendored_frameworks = 'dist/Frameworks/onnxruntime.xcframework'

  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'OTHER_CPLUSPLUSFLAGS'        => '$(inherited) -std=c++17',
    # CocoaPods does not always propagate vendored xcframework headers to the pod's
    # own compilation unit — add the parent dir explicitly so the compiler can find
    # onnxruntime.xcframework/ios-arm64/onnxruntime.framework/Headers/*.h
    'FRAMEWORK_SEARCH_PATHS'      => '$(inherited) "$(PODS_TARGET_SRCROOT)/dist/Frameworks"',
  }

  # No React or ViroReact pod dependencies — this is a plain iOS framework.
  # VRTObjectDetectorView is located at runtime via NSClassFromString (avoids the
  # libViroReact.a static/dynamic conflict). React symbols resolved from host app.
end
