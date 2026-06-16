import { ConfigPlugin, withAppBuildGradle } from "@expo/config-plugins";

const ONNX_DEPENDENCY =
  "    implementation 'com.microsoft.onnxruntime:onnxruntime-android:1.20.0'";

export const withViroONNXAndroid: ConfigPlugin = (config) => {
  return withAppBuildGradle(config, (newConfig) => {
    const gradle = newConfig.modResults.contents;

    // Idempotent: skip if already present
    if (gradle.includes("onnxruntime-android")) {
      return newConfig;
    }

    // Insert inside the dependencies { } block, right before the closing brace
    if (!gradle.includes("dependencies {")) {
      console.warn(
        "[react-viro-onnx] Could not find dependencies block in build.gradle."
      );
      return newConfig;
    }

    newConfig.modResults.contents = gradle.replace(
      /dependencies\s*\{/,
      `dependencies {\n${ONNX_DEPENDENCY} // react-viro-onnx`
    );

    return newConfig;
  });
};
