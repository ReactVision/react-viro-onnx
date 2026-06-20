# @reactvision/react-viro-onnx

ONNX Runtime inference provider for [`ViroObjectDetector`](../viro/docs/ViroObjectDetector.md). This package supplies the on-device YOLOE inference (ONNX Runtime, NMS, class-name decoding) that powers object detection in ViroReact. `ViroObjectDetector` itself only handles the camera and plumbing — without this provider, detection returns empty.

## How it works

- **iOS:** a vendored, dynamically-linked `onnxruntime.xcframework`. The `ViroONNX` Objective-C++ class registers an inference block into `VRTObjectDetectorView` automatically via `+load` when the framework is loaded — no manual call needed.
- **Android:** the `onnxruntime-android` AAR. `ViroONNXModule` registers the provider through React Native module init, and creates the ORT session with the **NNAPI execution provider** (`USE_FP16`) so inference can run on the device GPU/NPU/DSP, falling back to CPU if NNAPI is unavailable or can't compile the graph.

Both sides: run the model, apply confidence threshold + greedy NMS (IoU 0.45), sort by confidence, decode class indices to names from the model's `names` metadata, and return up to 50 detections (the view trims further to its `maxDetections` prop).

## Install

```bash
npm install @reactvision/react-viro-onnx
```

Add **both** plugins to your `app.json` (this one *after* `@reactvision/react-viro`):

```json
{
  "expo": {
    "plugins": [
      "@reactvision/react-viro",
      "@reactvision/react-viro-onnx"
    ]
  }
}
```

The config plugin:
- **iOS:** inserts `pod 'ViroReactONNX'` into the Podfile (after the `ViroKit` pod). On first `pod install` it downloads `onnxruntime.xcframework` (~60 MB, cached, not committed).
- **Android:** adds `implementation 'com.microsoft.onnxruntime:onnxruntime-android:1.20.0'` to the app `build.gradle`.

Then rebuild the native app (`npx expo run:ios` / `run:android`). On iOS, confirm in the logs that no `[ViroONNX] … not found` error appears — the provider registers silently on success.

> `ViroONNX.install()` exists for backwards-compatibility but is a **no-op**; registration is automatic.

> **Bundle your model too** — the detector loads `.onnx` by name from the **native** bundle, not Metro. See [Bundle a model](#bundle-a-model). A missing model surfaces as `model not found` at runtime.

### Local development (consuming this package from source)

If the app installs this package from a **packed tarball** (e.g. `"@reactvision/react-viro-onnx": "file:../path/react-viro-onnx-1.0.0.tgz"`), then `node_modules` holds a *snapshot* — editing the source here does **not** reach the app until you re-pack and reinstall:

```bash
# in this package (after editing native/JS or the config plugin):
npm run build        # only if you changed TS (dist/ + plugin/build/)
npm pack             # regenerates react-viro-onnx-1.0.0.tgz

# in the app:
rm -rf node_modules/@reactvision/react-viro-onnx
npm install <path-to>/react-viro-onnx-1.0.0.tgz
```

Symptoms of a stale tarball: a config-plugin resolution error during `expo prebuild` (no `app.plugin.js` in `node_modules`), or native changes (e.g. NNAPI) never taking effect / no `ViroONNX` log lines. To skip re-packing during active dev, point the dep at the **folder** (`file:../path/react-viro-onnx`) instead of the tarball.

## Bundle a model

Ship an `.onnx` next to your app and reference it by name via the `model` prop. See [model bundling](../viro/docs/ViroObjectDetector.md#model-bundling). The prompt-free `yoloe-26n` model carries 4,585 classes; its label names are read from the ONNX `names` metadata at load time.

## Exporting a text-prompt model

The stock prompt-free model has poor recall on specific common classes (it rarely emits "cup", "keyboard", etc. confidently). For high-recall detection of **your** classes, export a **text-prompt (RepRTA)** model that bakes your class list into the detection head via CLIP text embeddings.

`scripts/export_text_model.py` does this:

```bash
# In a Python env with torch (e.g. a venv):
pip install ultralytics
python scripts/export_text_model.py
# → yoloe-26n-seg.onnx with your CLASSES baked in (downloads weights + mobileclip text encoder on first run)
```

Edit the `CLASSES` list in the script to your target classes, re-run, then bundle the resulting `.onnx` (rename as you like, e.g. `yoloe-26n-text.onnx`) and point the `model` prop at it.

The export keeps the same output format as the prompt-free model (`output0 [1,300,38]`, end2end NMS, segment task) and writes your class list into the `names` metadata, so **no native changes are needed** — the provider reads the new names automatically.

Because the head is reparametrized to your classes, the model emits only those classes. You usually just run it in `prompt-free` mode:

```tsx
<ViroObjectDetector model="yoloe-26n-text" mode="prompt-free" />
```

`mode="text"` is **not** what bakes in your classes — that happens here, at export time. `text` mode is only a runtime label post-filter; add it (with `categories`) on top of the exported model when you want to narrow the output to a subset of the baked classes:

```tsx
<ViroObjectDetector
  model="yoloe-26n-text"
  mode="text"
  categories={["cup", "laptop", "keyboard"]}  // a subset of the exported CLASSES
/>
```

> Static, not dynamic: the class set is fixed at export time. Changing classes means re-exporting. Fully dynamic runtime text prompts would require bundling the CLIP text encoder + a model that accepts embedding inputs (not currently implemented).

## API

```ts
import { ViroONNX } from "@reactvision/react-viro-onnx";

ViroONNX.install();        // no-op (registration is automatic)
ViroONNX.getVersion();     // ONNX Runtime version string, e.g. "1.20.0"
```

## Performance

Inference is the per-frame bottleneck. `maxFPS` throttles how often it runs; the camera keeps rendering at native FPS regardless.

- **Android** creates the session with the **NNAPI EP** (`USE_FP16`). Whether that actually offloads to GPU/NPU depends on the device's NNAPI drivers and how many YOLOE ops they support — unsupported ops (e.g. the end2end NMS) fall back to CPU. Check the logs:
  - `ONNX Runtime inference provider registered.` — module loaded.
  - `ORT session ready (NNAPI=true|false) …` — whether the NNAPI EP was applied.
  - `infer run=<ms>ms` — wall-clock per inference. This is the number to watch.
- If NNAPI doesn't help on a given device, the next levers (largest first): **INT8 quantization** of the model (export-time), then **lower input resolution** (640 → 480/320). Both trade a little accuracy for 2–4×.
- The model is `yoloe-26n` (nano); larger variants are slower.

## Platform parity

iOS is the reference implementation. Android has parity for AR-session detection: NMS, class names, `text`-mode filtering, `maxDetections`, center-square crop, and an **aligned `screenBoundingBox`** in dp (the renderer feeds the detector the full uncropped frame + the viewport crop rectangle, the Android equivalent of iOS's `displayTransform`). Remaining gaps:
- `worldPosition` (3D hit-test) is not yet emitted on Android.
- Android AR sees the central ~55–60% of the vertical FOV (center-square crop of a portrait frame) vs iOS cropping a landscape sensor frame.

See the platform table in the [component docs](../viro/docs/ViroObjectDetector.md#platform-support).
