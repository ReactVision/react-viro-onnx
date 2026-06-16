"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.withViroONNXIos = void 0;
const config_plugins_1 = require("@expo/config-plugins");
const fs_1 = __importDefault(require("fs"));
const VIROKIT_POD_LINE = "pod 'ViroKit', :path => '../node_modules/@reactvision/react-viro/ios/dist/ViroRenderer/'";
const ONNX_POD_LINE = "\n  # ONNX Runtime inference provider for ViroObjectDetector\n" +
    "  # Downloads onnxruntime.xcframework (~60 MB) automatically on first pod install.\n" +
    "  pod 'ViroReactONNX', :path => '../node_modules/@reactvision/react-viro-onnx/ios'";
const withViroONNXIos = (config) => {
    return (0, config_plugins_1.withDangerousMod)(config, [
        "ios",
        async (newConfig) => {
            const root = newConfig.modRequest.platformProjectRoot;
            const podfilePath = `${root}/Podfile`;
            const data = fs_1.default.readFileSync(podfilePath, "utf-8");
            // Idempotent: skip if already present
            if (data.includes("ViroReactONNX")) {
                return newConfig;
            }
            // Insert after the ViroKit pod line
            if (!data.includes(VIROKIT_POD_LINE)) {
                console.warn("[react-viro-onnx] Could not find ViroKit pod in Podfile. " +
                    "Make sure @reactvision/react-viro plugin is configured first.");
                return newConfig;
            }
            const updated = data.replace(VIROKIT_POD_LINE, VIROKIT_POD_LINE + ONNX_POD_LINE);
            fs_1.default.writeFileSync(podfilePath, updated, "utf-8");
            return newConfig;
        },
    ]);
};
exports.withViroONNXIos = withViroONNXIos;
//# sourceMappingURL=withViroONNXIos.js.map