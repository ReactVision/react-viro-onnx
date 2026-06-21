package com.reactvision.viroonnx;

import android.content.Context;
import android.graphics.Bitmap;
import android.util.Log;

import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.viromedia.bridge.component.VRTObjectDetectorView;

import java.io.FileInputStream;
import java.io.InputStream;
import java.nio.FloatBuffer;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import java.util.EnumSet;

import ai.onnxruntime.OnnxTensor;
import ai.onnxruntime.OrtEnvironment;
import ai.onnxruntime.OrtException;
import ai.onnxruntime.OrtSession;
import ai.onnxruntime.providers.NNAPIFlags;

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

    // YOLOE output: [1, 300, 38]
    private static final int MODEL_INPUT = 640;
    private static final int NUM_DETS    = 300;
    private static final int DET_DIM     = 38;
    // NMS IoU threshold (matches iOS) and an internal ceiling on returned detections;
    // the host view trims further to its maxDetections prop.
    private static final float NMS_IOU   = 0.45f;
    private static final int MAX_RESULTS = 50;
    // Per-inference timing log. Keep false in shipping builds (fires every frame).
    private static final boolean DEBUG = false;

    private static boolean sInstalled = false;

    // Per-model ORT session cache
    private static OrtEnvironment sOrtEnv = null;
    private static final Map<String, OrtSession> sSessions = new HashMap<>();
    // Per-model class names parsed from the model's "names" metadata (Ultralytics export).
    private static final Map<String, String[]> sClassNames = new HashMap<>();
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
            sOrtEnv = OrtEnvironment.getEnvironment();
        } catch (RuntimeException e) {
            Log.e(TAG, "Failed to create ORT environment", e);
            return;
        }

        VRTObjectDetectorView.registerInferenceProvider(
            (modelPath, floatData, inputSize, confThreshold) ->
                runInference(modelPath, floatData, inputSize, confThreshold)
        );

        Log.i(TAG, "ONNX Runtime inference provider registered.");
    }

    // ── ORT session management ────────────────────────────────────────────────

    private static synchronized OrtSession sessionForPath(String modelPath) {
        if (sSessions.containsKey(modelPath)) return sSessions.get(modelPath);
        try {
            byte[] modelBytes = readModelBytes(modelPath);

            // Hardware acceleration: ORT Android has no standalone GPU EP — NNAPI is the
            // path to the device's GPU / NPU(APU) / DSP. NNAPI partitions the graph and
            // runs unsupported ops (e.g. the end2end NMS) on CPU automatically. USE_FP16
            // trades a little precision for speed on the accelerator. If NNAPI init fails
            // (driver/op-support issues), fall back to a plain CPU session.
            OrtSession session = null;
            boolean nnapi = false;
            try {
                OrtSession.SessionOptions opts = new OrtSession.SessionOptions();
                opts.addNnapi(EnumSet.of(NNAPIFlags.USE_FP16));
                session = sOrtEnv.createSession(modelBytes, opts);
                nnapi = true;
            } catch (Throwable t) {
                Log.w(TAG, "NNAPI EP unavailable; falling back to CPU", t);
            }
            if (session == null) {
                OrtSession.SessionOptions opts = new OrtSession.SessionOptions();
                session = sOrtEnv.createSession(modelBytes, opts);
            }

            sSessions.put(modelPath, session);
            loadClassNamesIfNeeded(modelPath, session);
            Log.i(TAG, "ORT session ready (NNAPI=" + nnapi + ") for " + modelPath);
            return session;
        } catch (Exception e) {
            Log.e(TAG, "Failed to load model: " + modelPath, e);
            return null;
        }
    }

    // Reads the Ultralytics "names" metadata ("{0: 'person', 1: 'car', ...}") once per
    // model so detections carry real class names instead of numeric ids.
    private static void loadClassNamesIfNeeded(String modelPath, OrtSession session) {
        if (sClassNames.containsKey(modelPath)) return;
        try {
            Map<String, String> custom = session.getMetadata().getCustomMetadata();
            String raw = custom.get("names");
            String[] names = parseClassNames(raw);
            if (names != null) sClassNames.put(modelPath, names);
        } catch (Exception e) {
            Log.w(TAG, "Could not read class names from model metadata.");
        }
    }

    private static String[] parseClassNames(String raw) {
        if (raw == null) return null;
        java.util.regex.Matcher m = java.util.regex.Pattern
            .compile("(\\d+):\\s*['\"]([^'\"]*)['\"]").matcher(raw);
        java.util.TreeMap<Integer, String> map = new java.util.TreeMap<>();
        int max = -1;
        while (m.find()) {
            int idx = Integer.parseInt(m.group(1));
            map.put(idx, m.group(2));
            if (idx > max) max = idx;
        }
        if (max < 0) return null;
        String[] out = new String[max + 1];
        for (int i = 0; i <= max; i++) out[i] = map.containsKey(i) ? map.get(i) : "";
        return out;
    }

    private static byte[] readModelBytes(String path) throws Exception {
        // Absolute path or file:// URL → read from the filesystem.
        if (path.startsWith("/") || path.startsWith("file://")) {
            String filePath = path.startsWith("file://") ? path.substring(7) : path;
            try (InputStream is = new FileInputStream(filePath)) {
                return is.readAllBytes();
            }
        }
        // Otherwise treat it as a bundled asset name: assets/models/<name>.onnx
        // (matches the iOS bundle-resource lookup by name).
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
        OrtSession session = sessionForPath(modelPath);
        if (session == null) return results;

        String[] classNames = sClassNames.get(modelPath);

        try {
            OnnxTensor input = OnnxTensor.createTensor(
                sOrtEnv,
                FloatBuffer.wrap(nchwData),
                new long[]{1, 3, inputSize, inputSize}
            );

            Map<String, OnnxTensor> inputs = new HashMap<>();
            inputs.put("images", input);

            long runT0 = System.nanoTime();
            OrtSession.Result ortResult = session.run(inputs);
            if (DEBUG) {
                long runMs = (System.nanoTime() - runT0) / 1_000_000L;
                Log.i(TAG, "infer run=" + runMs + "ms");
            }

            // Read the output as a flat FloatBuffer view (row-major [1,300,38]) instead of
            // materializing nested float[1][300][38] Java arrays on every inference.
            OnnxTensor outTensor = (OnnxTensor) ortResult.get("output0").get();
            FloatBuffer out = outTensor.getFloatBuffer();

            float scale = 1.0f / inputSize;

            for (int i = 0; i < NUM_DETS; i++) {
                int base = i * DET_DIM;
                float conf = out.get(base + 4);
                if (conf < confThreshold) continue;

                float x1 = Math.max(0f, Math.min(1f, out.get(base)     * scale));
                float y1 = Math.max(0f, Math.min(1f, out.get(base + 1) * scale));
                float x2 = Math.max(0f, Math.min(1f, out.get(base + 2) * scale));
                float y2 = Math.max(0f, Math.min(1f, out.get(base + 3) * scale));
                float w = x2 - x1, h = y2 - y1;
                if (w <= 0 || h <= 0) continue;

                int clsIdx = (int) out.get(base + 5);
                String label = (classNames != null && clsIdx >= 0 && clsIdx < classNames.length)
                    ? classNames[clsIdx]
                    : String.valueOf(clsIdx);

                Map<String, Object> bbox = new HashMap<>();
                bbox.put("x", x1); bbox.put("y", y1);
                bbox.put("width", w); bbox.put("height", h);

                Map<String, Object> det = new HashMap<>();
                det.put("label", label);
                det.put("confidence", conf);
                det.put("boundingBox", bbox);
                results.add(det);
            }

            input.close();
            ortResult.close();

        } catch (OrtException e) {
            Log.e(TAG, "ORT inference error", e);
            return results;
        }

        // Sort by confidence desc (required by greedy NMS), suppress overlaps, cap.
        results.sort((a, b) -> Float.compare(
            (Float) b.get("confidence"), (Float) a.get("confidence")));
        List<Map<String, Object>> kept = applyNMS(results, NMS_IOU);
        if (kept.size() > MAX_RESULTS) kept = new ArrayList<>(kept.subList(0, MAX_RESULTS));
        return kept;
    }

    // ── NMS ───────────────────────────────────────────────────────────────────

    private static float boxIoU(Map<String, Object> a, Map<String, Object> b) {
        @SuppressWarnings("unchecked") Map<String, Object> ba = (Map<String, Object>) a.get("boundingBox");
        @SuppressWarnings("unchecked") Map<String, Object> bb = (Map<String, Object>) b.get("boundingBox");
        float ax1 = (Float) ba.get("x"),  ay1 = (Float) ba.get("y");
        float ax2 = ax1 + (Float) ba.get("width"), ay2 = ay1 + (Float) ba.get("height");
        float bx1 = (Float) bb.get("x"),  by1 = (Float) bb.get("y");
        float bx2 = bx1 + (Float) bb.get("width"), by2 = by1 + (Float) bb.get("height");
        float iw = Math.max(0f, Math.min(ax2, bx2) - Math.max(ax1, bx1));
        float ih = Math.max(0f, Math.min(ay2, by2) - Math.max(ay1, by1));
        float inter = iw * ih;
        if (inter <= 0f) return 0f;
        float ua = (ax2 - ax1) * (ay2 - ay1) + (bx2 - bx1) * (by2 - by1) - inter;
        return ua > 0f ? inter / ua : 0f;
    }

    // Greedy IoU suppression; input must be sorted by confidence descending.
    private static List<Map<String, Object>> applyNMS(List<Map<String, Object>> dets, float iouThreshold) {
        List<Map<String, Object>> keep = new ArrayList<>();
        boolean[] suppressed = new boolean[dets.size()];
        for (int i = 0; i < dets.size(); i++) {
            if (suppressed[i]) continue;
            keep.add(dets.get(i));
            for (int j = i + 1; j < dets.size(); j++) {
                if (!suppressed[j] && boxIoU(dets.get(i), dets.get(j)) > iouThreshold) {
                    suppressed[j] = true;
                }
            }
        }
        return keep;
    }

    // ── Version ───────────────────────────────────────────────────────────────

    @ReactMethod(isBlockingSynchronousMethod = true)
    public String getVersion() {
        return OrtEnvironment.getEnvironment().getVersion();
    }
}
