# @reactvision/react-viro-onnx

ONNX Runtime inference provider for [`ViroObjectDetector`](../viro/docs/ViroObjectDetector.md). This package supplies the on-device YOLOE inference (ONNX Runtime, NMS, class-name decoding) that powers object detection in ViroReact. `ViroObjectDetector` itself only handles the camera and plumbing — without this provider, detection returns empty.

## How it works

- **iOS:** a vendored, dynamically-linked `onnxruntime.xcframework`. The `ViroONNX` Objective-C++ class registers an inference block into `VRTObjectDetectorView` automatically via `+load` when the framework is loaded — no manual call needed.
- **Android:** the `onnxruntime-android` AAR. `ViroONNXModule` registers the provider; registration is wired through React Native module init.

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

```tsx
<ViroObjectDetector
  model="yoloe-26n-text"
  mode="text"
  categories={["cup", "laptop", "keyboard", "mouse", "monitor", "book", "bottle"]}
/>
```

> Static, not dynamic: the class set is fixed at export time. Changing classes means re-exporting. Fully dynamic runtime text prompts would require bundling the CLIP text encoder + a model that accepts embedding inputs (not currently implemented).

## API

```ts
import { ViroONNX } from "@reactvision/react-viro-onnx";

ViroONNX.install();        // no-op (registration is automatic)
ViroONNX.getVersion();     // ONNX Runtime version string, e.g. "1.20.0"
```

## Platform parity

iOS is the reference implementation. Android has parity for standalone + AR-session detection (NMS, class names, `text`-mode filtering, `maxDetections`, center-square crop, and `screenBoundingBox` via the shared `ViroViewARCore` feed). Remaining gap: `worldPosition` (3D hit-test) is not yet emitted on Android, and `screenBoundingBox` orientation may need on-device calibration. See the platform table in the [component docs](../viro/docs/ViroObjectDetector.md#platform-support).
