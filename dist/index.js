"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ViroONNX = void 0;
const react_native_1 = require("react-native");
const LINKING_ERROR = `The package '@reactvision/react-viro-onnx' doesn't seem to be linked. ` +
    `Make sure to run 'pod install' on iOS or rebuild the app on Android.`;
const ViroONNXNative = react_native_1.NativeModules.ViroONNX
    ? react_native_1.NativeModules.ViroONNX
    : new Proxy({}, {
        get() {
            throw new Error(LINKING_ERROR);
        },
    });
/**
 * ViroONNX — ONNX Runtime inference provider for ViroObjectDetector.
 *
 * Call `ViroONNX.install()` once at app startup (before mounting any
 * ViroObjectDetector). The native module loads ONNX Runtime and registers
 * itself as the inference provider. From that point on, ViroObjectDetector
 * runs real YOLOE inference on every camera frame.
 *
 * @example
 * ```tsx
 * // App.tsx
 * import { ViroONNX } from '@reactvision/react-viro-onnx';
 * ViroONNX.install();
 *
 * // Anywhere in your app:
 * <ViroObjectDetector model={require('./yoloe-26n.onnx')} mode="prompt-free" ... />
 * ```
 */
exports.ViroONNX = {
    /**
     * Installs the ONNX Runtime inference provider into ViroObjectDetector.
     * Safe to call multiple times (no-op after first call).
     */
    install() {
        ViroONNXNative.install();
    },
    /** Returns the ONNX Runtime version string, e.g. "1.20.0". */
    getVersion() {
        return ViroONNXNative.getVersion();
    },
};
//# sourceMappingURL=index.js.map