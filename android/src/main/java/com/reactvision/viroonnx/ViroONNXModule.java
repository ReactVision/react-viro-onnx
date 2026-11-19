package com.reactvision.viroonnx;

import android.content.Context;
import android.util.Log;

import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.viromedia.bridge.component.VRTObjectDetectorView;

import java.io.FileInputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * ViroONNXModule — React Native module that installs ONNX Runtime as the
 * inference provider for VRTObjectDetectorView.
 *
 * JS usage:
 *   import { ViroONNX } from '@reactvision/react-viro-onnx';
 *   ViroONNX.install();
 */
public class ViroONNXModule extends ReactContextBaseJavaModule {

    private static final String TAG = "ViroONNX";

    // Internal ceiling on returned detections; the host view trims further to its
    // maxDetections prop.
    private static final int MAX_RESULTS = 50;
    // Per-inference timing log. Keep false in shipping builds (fires every frame).
    private static final boolean DEBUG = false;

    private static boolean sInstalled = false;

    // App context for resolving bundled model assets by name.
    private static Context sAppContext = null;

    public ViroONNXModule(ReactApplicationContext ctx) {
        super(ctx);
        // Auto-register the provider at app startup (mirrors iOS's +load). The module is
        // constructed by ViroONNXPackage, so no explicit JS install() call is required.
        sAppContext = ctx.getApplicationContext();
        installSync();
    }

    @Override
    public String getName() { return "ViroONNX"; }

    // ── Install ──────────────────────────────────────────────────────────────

    @ReactMethod
    public void install() {
        installSync();
    }

    public static synchronized void installSync() {
        if (sInstalled) return;
        sInstalled = true;

        try {
            ViroONNXCore.nativeOrtVersion();
        } catch (Throwable t) {
            Log.e(TAG, "Failed to load the ONNX Runtime detection core", t);
            return;
        }

        VRTObjectDetectorView.registerInferenceProvider(
            (modelPath, floatData, inputSize, confThreshold) ->
                runInference(modelPath, floatData, inputSize, confThreshold)
        );

        Log.i(TAG, "ONNX Runtime inference provider registered.");
    }

    // ── Models ────────────────────────────────────────────────────────────────

    // The core keeps one session per model path. NNAPI (FP16) lets inference run on the
    // device GPU/NPU/DSP; the core falls back to the CPU when NNAPI is unavailable or
    // cannot compile the graph.
    private static synchronized boolean ensureLoaded(String modelPath) {
        if (ViroONNXCore.nativeIsLoaded(modelPath)) return true;
        try {
            byte[] modelBytes = readModelBytes(modelPath);
            if (!ViroONNXCore.nativeLoad(modelPath, modelBytes, true)) {
                Log.e(TAG, "Failed to load model: " + modelPath + ": " + ViroONNXCore.nativeLastError());
                return false;
            }
            boolean nnapi = "NNAPI".equals(ViroONNXCore.nativeProvider(modelPath));
            Log.i(TAG, "ORT session ready (NNAPI=" + nnapi + ") for " + modelPath);
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Failed to load model: " + modelPath, e);
            return false;
        }
    }

    // Absolute paths (or file:// URIs) are read directly; a bare name resolves to the
    // bundled asset models/<name>.onnx.
    private static byte[] readModelBytes(String path) throws Exception {
        if (path.startsWith("/") || path.startsWith("file://")) {
            String filePath = path.startsWith("file://") ? path.substring(7) : path;
            try (InputStream is = new FileInputStream(filePath)) {
                return is.readAllBytes();
            }
        }
        if (sAppContext == null) throw new IllegalStateException("ViroONNX: no app context for asset lookup");
        String asset = "models/" + path + ".onnx";
        try (InputStream is = sAppContext.getAssets().open(asset)) {
            return is.readAllBytes();
        }
    }

    // ── Inference ─────────────────────────────────────────────────────────────

    private static List<Map<String, Object>> runInference(
        String modelPath, float[] nchwData, int inputSize, float confThreshold)
    {
        List<Map<String, Object>> results = new ArrayList<>();
        if (!ensureLoaded(modelPath)) return results;

        float[] boxes = new float[MAX_RESULTS * 6];
        String[] labels = new String[MAX_RESULTS];
        long runT0 = System.nanoTime();
        int n = ViroONNXCore.nativeDetect(modelPath, nchwData, inputSize, confThreshold, boxes, labels);
        if (DEBUG) {
            long runMs = (System.nanoTime() - runT0) / 1_000_000L;
            Log.i(TAG, "infer run=" + runMs + "ms");
        }
        if (n < 0) {
            Log.e(TAG, "ORT inference error: " + ViroONNXCore.nativeLastError());
            return results;
        }
        for (int i = 0; i < n; i++) {
            Map<String, Object> bbox = new HashMap<>();
            bbox.put("x", boxes[i * 6]);
            bbox.put("y", boxes[i * 6 + 1]);
            bbox.put("width", boxes[i * 6 + 2]);
            bbox.put("height", boxes[i * 6 + 3]);

            Map<String, Object> det = new HashMap<>();
            det.put("label", labels[i] != null ? labels[i] : String.valueOf((int) boxes[i * 6 + 5]));
            det.put("confidence", boxes[i * 6 + 4]);
            det.put("boundingBox", bbox);
            results.add(det);
        }
        return results;
    }

    // ── Version ───────────────────────────────────────────────────────────────

    @ReactMethod(isBlockingSynchronousMethod = true)
    public String getVersion() {
        return ViroONNXCore.nativeOrtVersion();
    }
}
