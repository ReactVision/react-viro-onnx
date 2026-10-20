package com.reactvision.viroonnx;

/**
 * ViroONNXCore — the JNI surface of libviro_onnx.so, the detection core shared with iOS
 * (core/, written in Eskiu). It holds the ORT sessions and does the YOLOE decoding, NMS
 * and class-name lookup; this side only supplies model bytes and image buffers.
 */
final class ViroONNXCore {

    static {
        // libviro_onnx.so links against the ONNX Runtime library of the onnxruntime-android AAR.
        System.loadLibrary("onnxruntime");
        System.loadLibrary("viro_onnx");
    }

    private ViroONNXCore() {}

    /** Loads a model from its bytes under key, once. NNAPI (FP16) falls back to the CPU. */
    static native boolean nativeLoad(String key, byte[] model, boolean nnapi);

    static native boolean nativeIsLoaded(String key);

    /** The execution provider of the session under key ("CPU", "NNAPI"), "" when none. */
    static native String nativeProvider(String key);

    /**
     * Runs the model loaded under key on a [1, 3, inputSize, inputSize] NCHW buffer.
     * Each detection is 6 floats in boxes (x, y, width, height, confidence, class index,
     * the box normalized to [0, 1]) and its class name, or null, in labels; at most
     * min(boxes.length / 6, labels.length) of them, sorted by confidence after NMS.
     * Returns the count, or -1 on failure (see nativeLastError).
     */
    static native int nativeDetect(String key, float[] nchw, int inputSize, float confThreshold,
                                   float[] boxes, String[] labels);

    static native void nativeReleaseAll();

    static native String nativeOrtVersion();

    static native String nativeLastError();
}
