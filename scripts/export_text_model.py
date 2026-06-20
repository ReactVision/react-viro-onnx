"""
Export a YOLOE text-prompt (RepRTA) ONNX with a curated, baked-in class list.

The prompt-free yoloe-26n.onnx has a fixed 4585-class head and rarely surfaces the
common objects we care about. RepRTA reparametrizes the detection head against the
text embeddings of OUR classes, so the model scores boxes specifically for them →
much higher recall on e.g. "cup".

Output format matches the existing prompt-free export (end2end seg, output0 [1,300,38]),
so the native ViroONNX consumer needs no changes — it reads the new class names from
the model metadata.
"""
import sys

# Curated class list — common indoor / desk / household objects.
CLASSES = [
    "person", "chair", "table", "desk", "couch", "bed",
    "tv", "monitor", "laptop", "keyboard", "mouse", "cell phone", "tablet",
    "remote", "headphones", "camera", "book", "pen", "scissors",
    "cup", "mug", "bottle", "wine glass", "bowl", "plate",
    "fork", "knife", "spoon", "backpack", "handbag", "bag",
    "potted plant", "lamp", "clock", "vase", "keys", "wallet",
    "ball", "box", "can",
]

def main():
    from ultralytics import YOLOE
    weights = sys.argv[1] if len(sys.argv) > 1 else "yoloe-26n-seg.pt"
    print(f"[export] loading {weights} ({len(CLASSES)} target classes)")
    model = YOLOE(weights)
    # RepRTA: bake the text-prompt embeddings of CLASSES into the detection head.
    model.set_classes(CLASSES, model.get_text_pe(CLASSES))
    # Match the prompt-free export: end2end (NMS baked) so output0 is [1,300,38].
    path = model.export(format="onnx", imgsz=640, nms=True, opset=19, simplify=False)
    print(f"[export] done -> {path}")

if __name__ == "__main__":
    main()
