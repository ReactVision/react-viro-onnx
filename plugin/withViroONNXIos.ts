import { ConfigPlugin, withDangerousMod } from "@expo/config-plugins";
import fs from "fs";

// 2-space indented (inside the target), no leading/trailing newline.
const ONNX_POD_BLOCK =
  "  # ONNX Runtime inference provider for ViroObjectDetector\n" +
  "  # Downloads onnxruntime.xcframework (~60 MB) automatically on first pod install.\n" +
  "  pod 'ViroReactONNX', :path => '../node_modules/@reactvision/react-viro-onnx/ios'";

export const withViroONNXIos: ConfigPlugin = (config) => {
  return withDangerousMod(config, [
    "ios",
    async (newConfig) => {
      const podfilePath = `${newConfig.modRequest.platformProjectRoot}/Podfile`;
      const data = fs.readFileSync(podfilePath, "utf-8");

      // Idempotent: skip if already present.
      if (data.includes("ViroReactONNX")) {
        return newConfig;
      }

      // The ViroReactONNX pod MUST be declared after `use_react_native!` AND after the
      // ViroReact/ViroKit pods. Declaring it earlier breaks React Native's pod setup —
      // e.g. ExpoModulesJSI then builds at gnu++14 and fails to compile RN 0.83's jsi.h.
      //
      // We can't anchor on the ViroKit pod line, because the order in which two plugins'
      // dangerous mods run is NOT guaranteed (react-viro may write its pods before or after
      // this mod). Instead we insert the pod at the very END of the target — right before
      // the target's closing `end`, after the `post_install` block. react-viro always
      // inserts its pods *before* `post_install`, so ours always lands *after* ViroKit
      // regardless of mod order. A `pod` after `post_install` is valid: CocoaPods collects
      // every pod in the target definition irrespective of position relative to the hook.
      const lines = data.split("\n");
      const targetIdx = lines.findIndex((l) => /^target\s+['"].*\bdo\b/.test(l));
      // Everything inside the target body is indented, so the first column-0 `end` after
      // the target line is the target's own closing `end` (the post_install `end` is indented).
      let endIdx = -1;
      for (let i = targetIdx >= 0 ? targetIdx + 1 : 0; i < lines.length; i++) {
        if (/^end\s*$/.test(lines[i])) {
          endIdx = i;
          break;
        }
      }

      if (endIdx < 0) {
        console.warn(
          "[react-viro-onnx] Could not find the target's closing `end` in the Podfile; " +
            "the ViroReactONNX pod was not added."
        );
        return newConfig;
      }

      lines.splice(endIdx, 0, "", ...ONNX_POD_BLOCK.split("\n"));
      fs.writeFileSync(podfilePath, lines.join("\n"), "utf-8");

      return newConfig;
    },
  ]);
};
