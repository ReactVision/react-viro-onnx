// viro_onnx: the YOLOE detection core shared by the iOS and Android bridges.
// Written in Eskiu (core/src/viro_onnx.esk) over ONNX Runtime's C API.
// Every function is thread-safe.

#ifndef VIRO_ONNX_H
#define VIRO_ONNX_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// One detection. The box is normalized to [0, 1]. label is the class name from the
// model's "names" metadata, NULL when the model has none for class_index; it stays
// valid for the life of the process.
typedef struct ViroDetection {
    float x;
    float y;
    float width;
    float height;
    float confidence;
    int32_t class_index;
    const char *label;
} ViroDetection;

// Hardware acceleration for viro_onnx_load_*.
enum {
    VIRO_ONNX_CPU = 0,
    VIRO_ONNX_NNAPI_FP16 = 1  // Android NNAPI with FP16, falling back to the CPU
};

// Loads a model under `key` once; later calls with the same key do nothing.
// 1 on success (or already loaded), 0 on failure (see viro_onnx_last_error).
int viro_onnx_load_file(const char *key, const char *path, int accel);
int viro_onnx_load_bytes(const char *key, const uint8_t *data, uint64_t len, int accel);
int viro_onnx_is_loaded(const char *key);

// Runs the model loaded under `key` on a 1x3xNxN NCHW float image and writes up to
// max_out detections, sorted by confidence, after a 0.45 IoU NMS (at most 50).
// Returns the count, or -1 when the model is not loaded or inference fails.
int viro_onnx_detect(const char *key, const float *nchw, int input_size,
                     float conf_threshold, ViroDetection *out, int max_out);

// Releases every session. A detection in flight keeps its session until it returns.
void viro_onnx_release_all(void);

// The ONNX Runtime version string, e.g. "1.22.0".
const char *viro_onnx_ort_version(void);

// The last error of the calling thread's most recent failed call.
const char *viro_onnx_last_error(void);

#ifdef __cplusplus
}
#endif

#endif
