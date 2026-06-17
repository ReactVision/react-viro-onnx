//
//  ViroONNX.mm
//  ViroReactONNX
//
//  Copyright © 2026 ReactVision. All rights reserved.
//
//  Plain iOS framework — no React Native module registration.
//  +load fires when the dynamic framework is embedded and loaded by iOS,
//  which installs the ORT inference provider into VRTObjectDetectorView
//  before any camera frames are processed.

#import "ViroONNX.h"
#import <objc/message.h>

#import <onnxruntime/onnxruntime_cxx_api.h>

#include <map>
#include <string>

// ---------------------------------------------------------------------------
// Constants (must match VRTObjectDetectorView.mm)
// ---------------------------------------------------------------------------

static const int kModelInputSize = 640;
static const int kNumProposals   = 300;
static const int kProposalDim    = 38;

// ---------------------------------------------------------------------------
// Block type — must match VRTInferenceBlock in VRTObjectDetectorView.h exactly.
// Declared locally: no ViroReact import needed.
// ---------------------------------------------------------------------------

typedef NSArray<NSDictionary *>*(^VROInferenceBlock)(NSString*, const float*, int, float);

// ---------------------------------------------------------------------------
// ORT environment + session cache
// ---------------------------------------------------------------------------

static Ort::Env  *gEnv = nullptr;
static std::map<std::string, Ort::Session *> gSessionMap;
static dispatch_queue_t gSessionQueue;

static void ensureEnv() {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gSessionQueue = dispatch_queue_create("com.reactvision.onnx.sessions",
                                              DISPATCH_QUEUE_SERIAL);
        // Set the C++ API pointer before any Ort:: class usage.
        // Equivalent to Ort::InitApi() which doesn't exist in onnxruntime-c headers.
        if (!Ort::Global<void>::api_) {
            Ort::Global<void>::api_ = OrtGetApiBase()->GetApi(ORT_API_VERSION);
        }
        gEnv = new Ort::Env(ORT_LOGGING_LEVEL_WARNING, "ViroONNX");
    });
}

static Ort::Session * _Nullable sessionForModelPath(NSString *modelPath) {
    ensureEnv();
    __block Ort::Session *session = nullptr;
    dispatch_sync(gSessionQueue, ^{
        auto it = gSessionMap.find(modelPath.UTF8String);
        if (it != gSessionMap.end()) { session = it->second; return; }
        try {
            Ort::SessionOptions opts;
            Ort::Session *s = new Ort::Session(*gEnv, modelPath.UTF8String, opts);
            gSessionMap[modelPath.UTF8String] = s;
            session = s;
            NSLog(@"[ViroONNX] model loaded: %@", modelPath);
        } catch (const Ort::Exception &e) {
            NSLog(@"[ViroONNX] failed to load model '%@': %s", modelPath, e.what());
        }
    });
    return session;
}

// ---------------------------------------------------------------------------
// Inference
// ---------------------------------------------------------------------------

static NSArray<NSDictionary *> *runInference(
    NSString *modelPath, const float *nchwData, int inputSize, float confThreshold)
{
    Ort::Session *session = sessionForModelPath(modelPath);
    if (!session) return @[];
    try {
        Ort::MemoryInfo memInfo =
            Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);

        int64_t shape[] = {1, 3, (int64_t)inputSize, (int64_t)inputSize};
        size_t  count   = (size_t)(3 * inputSize * inputSize);

        Ort::Value inputTensor = Ort::Value::CreateTensor<float>(
            memInfo, const_cast<float *>(nchwData), count, shape, 4);

        const char *inNames[]  = {"images"};
        const char *outNames[] = {"output0"};

        auto outputs = session->Run(
            Ort::RunOptions{nullptr}, inNames, &inputTensor, 1, outNames, 1);

        if (outputs.empty()) return @[];

        const float *ptr     = outputs[0].GetTensorData<float>();
        int64_t      numElem = (int64_t)outputs[0]
                                    .GetTensorTypeAndShapeInfo().GetElementCount();
        if (numElem < kNumProposals * kProposalDim) return @[];

        const float scale = 1.0f / (float)inputSize;
        NSMutableArray *dets = [NSMutableArray array];

        for (int i = 0; i < kNumProposals; i++) {
            const float *p = ptr + i * kProposalDim;
            float conf = p[4];
            if (conf < confThreshold) continue;

            float x1 = MAX(0.f, MIN(1.f, p[0] * scale));
            float y1 = MAX(0.f, MIN(1.f, p[1] * scale));
            float x2 = MAX(0.f, MIN(1.f, p[2] * scale));
            float y2 = MAX(0.f, MIN(1.f, p[3] * scale));
            float w  = x2 - x1, h = y2 - y1;
            if (w <= 0.f || h <= 0.f) continue;

            [dets addObject:@{
                @"label":       [NSString stringWithFormat:@"%d", (int)p[5]],
                @"confidence":  @(conf),
                @"boundingBox": @{@"x": @(x1), @"y": @(y1),
                                  @"width": @(w), @"height": @(h)}
            }];
        }
        NSLog(@"[ViroONNX] inference: %d detections (conf≥%.2f)",
              (int)dets.count, confThreshold);
        return [dets copy];
    } catch (const Ort::Exception &e) {
        NSLog(@"[ViroONNX] inference error: %s", e.what());
        return @[];
    }
}

// ---------------------------------------------------------------------------
// ViroONNX
// ---------------------------------------------------------------------------

@implementation ViroONNX

+ (void)install {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Do NOT call ensureEnv() here — +load fires before ORT's xcframework
        // C++ static initializers run, so Ort::Global<void>::api_ is still NULL.
        // ORT is initialized lazily on the first inference call via sessionForModelPath().
        Class cls = NSClassFromString(@"VRTObjectDetectorView");
        if (!cls) {
            NSLog(@"[ViroONNX] VRTObjectDetectorView not found — ViroReact linked?");
            return;
        }
        SEL sel = NSSelectorFromString(@"registerInferenceProvider:");
        if (![cls respondsToSelector:sel]) {
            NSLog(@"[ViroONNX] registerInferenceProvider: not found");
            return;
        }
        VROInferenceBlock block =
            ^NSArray<NSDictionary *>*(NSString *mp, const float *d, int sz, float conf) {
                return runInference(mp, d, sz, conf);
            };
        void (*fn)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
        fn(cls, sel, block);
        NSLog(@"[ViroONNX] inference provider registered.");
    });
}

+ (NSString *)ortVersion {
    return [NSString stringWithUTF8String:OrtGetApiBase()->GetVersionString()];
}

// +load fires when the dynamic framework is loaded by iOS at app launch —
// before main(), before any React Native initialization.
+ (void)load {
    NSLog(@"[ViroONNX] +load — registering ORT provider.");
    [self install];
}

@end
