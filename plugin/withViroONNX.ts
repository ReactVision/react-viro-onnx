import { ConfigPlugin, withPlugins } from "@expo/config-plugins";
import { withViroONNXIos } from "./withViroONNXIos";
import { withViroONNXAndroid } from "./withViroONNXAndroid";

/**
 * Expo config plugin for @reactvision/react-viro-onnx.
 *
 * Automatically configures the native project to include ONNX Runtime:
 * - iOS:     Adds `pod 'ViroReactONNX'` to the Podfile, which downloads
 *            onnxruntime.xcframework (~60 MB) on first `pod install`.
 * - Android: Adds `onnxruntime-android:1.20.0` to app/build.gradle.
 *
 * Usage in app.json:
 * ```json
 * {
 *   "plugins": [
 *     "@reactvision/react-viro",
 *     "@reactvision/react-viro-onnx"
 *   ]
 * }
 * ```
 *
 * Then call ViroONNX.install() once at app startup:
 * ```tsx
 * import { ViroONNX } from '@reactvision/react-viro-onnx';
 * ViroONNX.install();
 * ```
 */
const withViroONNX: ConfigPlugin = (config) => {
  return withPlugins(config, [withViroONNXIos, withViroONNXAndroid]);
};

export default withViroONNX;
