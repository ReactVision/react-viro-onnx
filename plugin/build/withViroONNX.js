"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const config_plugins_1 = require("@expo/config-plugins");
const withViroONNXIos_1 = require("./withViroONNXIos");
const withViroONNXAndroid_1 = require("./withViroONNXAndroid");
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
const withViroONNX = (config) => {
    return (0, config_plugins_1.withPlugins)(config, [withViroONNXIos_1.withViroONNXIos, withViroONNXAndroid_1.withViroONNXAndroid]);
};
exports.default = withViroONNX;
//# sourceMappingURL=withViroONNX.js.map