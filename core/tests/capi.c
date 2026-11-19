// The C API from include/viro_onnx.h, linked against a built library (the xcframework
// slice or a .so). capi MODEL INPUT.bin [CONF] [ACCEL] prints the detections in the
// format of tests/reference.py, and the provider the session runs on to stderr.

#include <stdio.h>
#include <stdlib.h>

#include "viro_onnx.h"

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc < 3) return 2;
    FILE *f = fopen(argv[2], "rb");
    if (!f) return 1;
    static float x[3 * 640 * 640];
    if (fread(x, sizeof x, 1, f) != 1) return 1;
    fclose(f);
    float conf = argc > 3 ? (float)atof(argv[3]) : 0.25f;
    int accel = argc > 4 ? atoi(argv[4]) : VIRO_ONNX_CPU;
    if (!viro_onnx_load_file(argv[1], argv[1], accel)) {
        fprintf(stderr, "%s\n", viro_onnx_last_error());
        return 1;
    }
    fprintf(stderr, "provider %s\n", viro_onnx_provider(argv[1]));
    ViroDetection d[50];
    int n = viro_onnx_detect(argv[1], x, 640, conf, d, 50);
    if (n < 0) {
        fprintf(stderr, "%s\n", viro_onnx_last_error());
        return 1;
    }
    for (int i = 0; i < n; i++)
        printf("%.4f %.4f %.4f %.4f %.4f %d %s\n", d[i].x, d[i].y, d[i].width, d[i].height,
               d[i].confidence, d[i].class_index, d[i].label ? d[i].label : "?");
    viro_onnx_release_all();
    return viro_onnx_is_loaded(argv[1]) ? 1 : 0;
}
