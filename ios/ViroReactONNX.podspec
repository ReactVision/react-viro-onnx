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

  # ViroONNXModule.mm is a React Native module, so it needs the bridge headers. ViroONNX.mm
  # itself still links nothing beyond ONNX Runtime: it resolves the host view at runtime.
  s.dependency 'React-Core'

  # onnxruntime.xcframework is not committed; `prepare_command` fetches it on pod install,
  # through the script that is the single source of truth for where it comes from.
  #
  # It has to happen at *install* time, not build time. CocoaPods wires the framework's copy
  # phase from what exists when the project is generated, so a framework that appears later
  # fails the build in `rsync` with "No such file or directory" — a build-time script_phase
  # cannot rescue it, which was tried and does not work.
  s.prepare_command = 'bash ../scripts/download_onnxruntime.sh'

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
