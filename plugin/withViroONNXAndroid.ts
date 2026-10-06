import { ConfigPlugin, withAppBuildGradle } from "@expo/config-plugins";

// Keep in step with android/build.gradle. 1.20.0's prebuilt libonnxruntime4j_jni.so is not
// 16 KB-page aligned, which Android 15+ and Google Play reject; 1.21.0 onward ships aligned
// Android libs. Injecting an older version here than the library declares is how an app with a
// pinned resolution (resolutionStrategy.force, a BOM, a lock file) ends up with the rejected one.
export const ONNX_RUNTIME_VERSION = "1.22.0";

const ONNX_DEPENDENCY = `    implementation 'com.microsoft.onnxruntime:onnxruntime-android:${ONNX_RUNTIME_VERSION}'`;

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
