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

  s.source_files     = 'ios/**/*.{h,m,mm}'

  # Downloads onnxruntime.xcframework (dynamic) if not already present.
  # The xcframework is NOT committed to git to keep the repo lean.
  s.prepare_command = <<-CMD
    set -e
    ONNX_VERSION="1.20.0"
    DEST="ios/dist/Frameworks"
    XCFWK="$DEST/onnxruntime.xcframework"
    if [ ! -d "$XCFWK" ]; then
      echo "react-viro-onnx: downloading onnxruntime.xcframework v${ONNX_VERSION}..."
      mkdir -p "$DEST"
      curl -sL "https://github.com/microsoft/onnxruntime/releases/download/v${ONNX_VERSION}/onnxruntime-ios-xcframework-${ONNX_VERSION}.zip" \
           -o /tmp/ort-ios.zip
      unzip -q /tmp/ort-ios.zip -d "$DEST"
      rm /tmp/ort-ios.zip
      echo "react-viro-onnx: onnxruntime.xcframework ready."
    fi
  CMD

  # Vendored dynamic xcframework — no static/dynamic conflict with use_frameworks! :linkage => :dynamic
  s.vendored_frameworks = 'ios/dist/Frameworks/onnxruntime.xcframework'

  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'OTHER_CPLUSPLUSFLAGS'        => '$(inherited) -std=c++17',
  }

  s.dependency 'React-Core'
  s.dependency 'ViroReact'
end
