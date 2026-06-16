import { NativeModules } from 'react-native';

/**
 * ViroONNX — ONNX Runtime inference provider for ViroObjectDetector.
 *
 * The provider is registered automatically when the native pod is linked
 * (via +load on iOS / static initializer on Android). No manual install()
 * call is required — just having the pod in your Podfile is enough.
 *
 * install() is kept for backward compatibility but is now a no-op in JS.
 */
export const ViroONNX = {
  /** No-op — registration happens automatically via +load when pod is linked. */
  install(): void {
    // Native side auto-registers via +load. Nothing to do here.
  },

  /** Returns the ONNX Runtime version string linked into the app, e.g. "1.20.0". */
  getVersion(): string {
    return NativeModules.ViroONNX?.getVersion?.() ?? 'unavailable';
  },
};
