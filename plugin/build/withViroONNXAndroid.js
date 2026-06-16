"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.withViroONNXAndroid = void 0;
const config_plugins_1 = require("@expo/config-plugins");
const ONNX_DEPENDENCY = "    implementation 'com.microsoft.onnxruntime:onnxruntime-android:1.20.0'";
const withViroONNXAndroid = (config) => {
    return (0, config_plugins_1.withAppBuildGradle)(config, (newConfig) => {
        const gradle = newConfig.modResults.contents;
        // Idempotent: skip if already present
        if (gradle.includes("onnxruntime-android")) {
            return newConfig;
        }
        // Insert inside the dependencies { } block, right before the closing brace
        if (!gradle.includes("dependencies {")) {
            console.warn("[react-viro-onnx] Could not find dependencies block in build.gradle.");
            return newConfig;
        }
        newConfig.modResults.contents = gradle.replace(/dependencies\s*\{/, `dependencies {\n${ONNX_DEPENDENCY} // react-viro-onnx`);
        return newConfig;
    });
};
exports.withViroONNXAndroid = withViroONNXAndroid;
//# sourceMappingURL=withViroONNXAndroid.js.map