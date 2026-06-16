"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ViroONNX = void 0;
const react_native_1 = require("react-native");
/**
 * ViroONNX — ONNX Runtime inference provider for ViroObjectDetector.
 *
 * The provider is registered automatically when the native pod is linked
 * (via +load on iOS / static initializer on Android). No manual install()
 * call is required — just having the pod in your Podfile is enough.
 *
 * install() is kept for backward compatibility but is now a no-op in JS.
 */
exports.ViroONNX = {
    /** No-op — registration happens automatically via +load when pod is linked. */
    install() {
        // Native side auto-registers via +load. Nothing to do here.
    },
    /** Returns the ONNX Runtime version string linked into the app, e.g. "1.20.0". */
    getVersion() {
        var _a, _b, _c;
        return (_c = (_b = (_a = react_native_1.NativeModules.ViroONNX) === null || _a === void 0 ? void 0 : _a.getVersion) === null || _b === void 0 ? void 0 : _b.call(_a)) !== null && _c !== void 0 ? _c : 'unavailable';
    },
};
//# sourceMappingURL=index.js.map