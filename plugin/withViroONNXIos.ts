import { ConfigPlugin, withDangerousMod } from "@expo/config-plugins";
import fs from "fs";

const VIROKIT_POD_LINE =
  "pod 'ViroKit', :path => '../node_modules/@reactvision/react-viro/ios/dist/ViroRenderer/'";

const ONNX_POD_LINE =
  "\n  # ONNX Runtime inference provider for ViroObjectDetector\n" +
  "  # Downloads onnxruntime.xcframework (~60 MB) automatically on first pod install.\n" +
  "  pod 'ViroReactONNX', :path => '../node_modules/@reactvision/react-viro-onnx/ios'";

export const withViroONNXIos: ConfigPlugin = (config) => {
  return withDangerousMod(config, [
    "ios",
    async (newConfig) => {
      const root = newConfig.modRequest.platformProjectRoot;
      const podfilePath = `${root}/Podfile`;

      const data = fs.readFileSync(podfilePath, "utf-8");

      // Idempotent: skip if already present
      if (data.includes("ViroReactONNX")) {
        return newConfig;
      }

      // Insert after the ViroKit pod line
      if (!data.includes(VIROKIT_POD_LINE)) {
        console.warn(
          "[react-viro-onnx] Could not find ViroKit pod in Podfile. " +
            "Make sure @reactvision/react-viro plugin is configured first."
        );
        return newConfig;
      }

      const updated = data.replace(VIROKIT_POD_LINE, VIROKIT_POD_LINE + ONNX_POD_LINE);
      fs.writeFileSync(podfilePath, updated, "utf-8");

      return newConfig;
    },
  ]);
};
