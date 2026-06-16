package com.reactvision.viroonnx;

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

import ai.onnxruntime.OnnxTensor;
import ai.onnxruntime.OrtEnvironment;
import ai.onnxruntime.OrtException;
import ai.onnxruntime.OrtSession;

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

    private static boolean sInstalled = false;

    // Per-model ORT session cache
    private static OrtEnvironment sOrtEnv = null;
    private static final Map<String, OrtSession> sSessions = new HashMap<>();

    public ViroONNXModule(ReactApplicationContext ctx) {
        super(ctx);
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
        } catch (OrtException e) {
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
            OrtSession.SessionOptions opts = new OrtSession.SessionOptions();
            OrtSession session = sOrtEnv.createSession(modelBytes, opts);
            sSessions.put(modelPath, session);
            Log.i(TAG, "Loaded ONNX model: " + modelPath);
            return session;
        } catch (Exception e) {
            Log.e(TAG, "Failed to load model: " + modelPath, e);
            return null;
        }
    }

    private static byte[] readModelBytes(String path) throws Exception {
        // Strip file:// prefix if present
        String filePath = path.startsWith("file://") ? path.substring(7) : path;
        try (InputStream is = new FileInputStream(filePath)) {
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

        try {
            OnnxTensor input = OnnxTensor.createTensor(
                sOrtEnv,
                FloatBuffer.wrap(nchwData),
                new long[]{1, 3, inputSize, inputSize}
            );

            Map<String, OnnxTensor> inputs = new HashMap<>();
            inputs.put("images", input);

            OrtSession.Result ortResult = session.run(inputs);
            float[][][] output0 = (float[][][]) ortResult.get("output0").get().getValue();
            // output0[batch][det_idx][dim]

            float scale = 1.0f / inputSize;
            float[][] dets = output0[0];

            for (int i = 0; i < NUM_DETS; i++) {
                float conf = dets[i][4];
                if (conf < confThreshold) continue;

                float x1 = Math.max(0f, Math.min(1f, dets[i][0] * scale));
                float y1 = Math.max(0f, Math.min(1f, dets[i][1] * scale));
                float x2 = Math.max(0f, Math.min(1f, dets[i][2] * scale));
                float y2 = Math.max(0f, Math.min(1f, dets[i][3] * scale));
                float w = x2 - x1, h = y2 - y1;
                if (w <= 0 || h <= 0) continue;

                Map<String, Object> bbox = new HashMap<>();
                bbox.put("x", x1); bbox.put("y", y1);
                bbox.put("width", w); bbox.put("height", h);

                Map<String, Object> det = new HashMap<>();
                det.put("label", String.valueOf((int) dets[i][5]));
                det.put("confidence", conf);
                det.put("boundingBox", bbox);
                results.add(det);
            }

            input.close();
            ortResult.close();

        } catch (OrtException e) {
            Log.e(TAG, "ORT inference error", e);
        }

        return results;
    }

    // ── Version ───────────────────────────────────────────────────────────────

    @ReactMethod(isBlockingSynchronousMethod = true)
    public String getVersion() {
        return ai.onnxruntime.OrtEnvironment.getVersion();
    }
}
