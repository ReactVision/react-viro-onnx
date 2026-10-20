// A fake JNIEnv for the JNI entry points of src/android.esk: strings are C strings,
// arrays are {length, data}. jni_fake MODEL INPUT.bin [CONF] prints the detections in
// the format of tests/reference.py.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { int len; void *data; } Arr;

static void *table[229];
static void *tablep = table;
static void *env = &tablep;
static int deleted, created;

static const char *get_chars(void *e, void *s, uint8_t *copy) { return (const char *)s; }
static void rel_chars(void *e, void *s, const char *c) {}
static int arr_len(void *e, void *a) { return ((Arr *)a)->len; }
static void *elems(void *e, void *a, uint8_t *copy) { return ((Arr *)a)->data; }
static void rel_elems(void *e, void *a, void *p, int mode) {}
static void *new_str(void *e, const char *s) { created++; return strdup(s); }
static void set_obj(void *e, void *a, int i, void *v) { ((void **)((Arr *)a)->data)[i] = v; }
static void del_ref(void *e, void *o) { deleted++; }

uint8_t Java_com_reactvision_viroonnx_ViroONNXCore_nativeLoad(void *, void *, void *, void *, uint8_t);
uint8_t Java_com_reactvision_viroonnx_ViroONNXCore_nativeIsLoaded(void *, void *, void *);
int Java_com_reactvision_viroonnx_ViroONNXCore_nativeDetect(void *, void *, void *, void *, int, float, void *, void *);
void Java_com_reactvision_viroonnx_ViroONNXCore_nativeReleaseAll(void *, void *);
void *Java_com_reactvision_viroonnx_ViroONNXCore_nativeOrtVersion(void *, void *);

static Arr slurp(const char *path) {
    Arr a = {0, NULL};
    FILE *f = fopen(path, "rb");
    if (!f) return a;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    a.data = malloc(n);
    a.len = (int)fread(a.data, 1, n, f);
    fclose(f);
    return a;
}

int main(int argc, char **argv) {
    if (argc < 3) return 2;
    table[23] = del_ref;
    table[167] = new_str;
    table[169] = get_chars;
    table[170] = rel_chars;
    table[171] = arr_len;
    table[174] = set_obj;
    table[184] = elems;
    table[189] = elems;
    table[192] = rel_elems;
    table[197] = rel_elems;
    Arr model = slurp(argv[1]);
    Arr in = slurp(argv[2]);
    if (!model.data || in.len != 3 * 640 * 640 * 4) return 1;
    in.len /= 4;
    float conf = argc > 3 ? (float)atof(argv[3]) : 0.25f;
    if (!Java_com_reactvision_viroonnx_ViroONNXCore_nativeLoad(env, NULL, "m", &model, 0)) return 1;
    if (!Java_com_reactvision_viroonnx_ViroONNXCore_nativeIsLoaded(env, NULL, "m")) return 1;
    float boxes[50 * 6];
    void *labels[50];
    Arr b = {50 * 6, boxes}, l = {50, labels};
    int n = Java_com_reactvision_viroonnx_ViroONNXCore_nativeDetect(env, NULL, "m", &in, 640, conf, &b, &l);
    if (n < 0) return 1;
    for (int i = 0; i < n; i++) {
        float *d = boxes + i * 6;
        printf("%.4f %.4f %.4f %.4f %.4f %d %s\n", d[0], d[1], d[2], d[3], d[4], (int)d[5],
               labels[i] ? (char *)labels[i] : "?");
    }
    Java_com_reactvision_viroonnx_ViroONNXCore_nativeReleaseAll(env, NULL);
    if (Java_com_reactvision_viroonnx_ViroONNXCore_nativeIsLoaded(env, NULL, "m")) return 1;
    if (deleted != created || !Java_com_reactvision_viroonnx_ViroONNXCore_nativeOrtVersion(env, NULL)) return 1;
    return 0;
}
