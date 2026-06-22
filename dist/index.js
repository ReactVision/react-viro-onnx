"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ViroONNX = void 0;
const react_native_1 = require("react-native");
/**
 * ViroONNX — ONNX Runtime inference provider for ViroObjectDetector.
 *
 * The provider registers itself automatically when the native pod/AAR is linked
 * (via +load on iOS / React Native module init on Android). There is nothing to
 * call from JS — having the package installed and the plugin configured is enough.
 */
exports.ViroONNX = {
    /** Returns the ONNX Runtime version string linked into the app, e.g. "1.22.0". */
    getVersion() {
        var _a, _b, _c;
        return (_c = (_b = (_a = react_native_1.NativeModules.ViroONNX) === null || _a === void 0 ? void 0 : _a.getVersion) === null || _b === void 0 ? void 0 : _b.call(_a)) !== null && _c !== void 0 ? _c : 'unavailable';
    },
};
//# sourceMappingURL=index.js.map