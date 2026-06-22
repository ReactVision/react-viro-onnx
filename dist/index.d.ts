/**
 * ViroONNX — ONNX Runtime inference provider for ViroObjectDetector.
 *
 * The provider registers itself automatically when the native pod/AAR is linked
 * (via +load on iOS / React Native module init on Android). There is nothing to
 * call from JS — having the package installed and the plugin configured is enough.
 */
export declare const ViroONNX: {
    /** Returns the ONNX Runtime version string linked into the app, e.g. "1.22.0". */
    getVersion(): string;
};
//# sourceMappingURL=index.d.ts.map