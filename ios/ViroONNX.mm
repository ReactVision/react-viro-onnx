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
#include <memory>
#include <string>

// ---------------------------------------------------------------------------
// Constants (must match VRTObjectDetectorView.mm)
// ---------------------------------------------------------------------------

static const int kModelInputSize = 640;
static const int kNumProposals   = 300;
static const int kProposalDim    = 38;
// Internal ceiling on detections returned to the host. The host
// (VRTObjectDetectorView) trims to its `maxDetections` prop, so this only needs to
// be comfortably above any expected prop value. Results are confidence-sorted, so
// the host keeps the top-N.
static const int kMaxDetections  = 50;

// ---------------------------------------------------------------------------
// Block type — must match VRTInferenceBlock in VRTObjectDetectorView.h exactly.
// ---------------------------------------------------------------------------

typedef NSArray<NSDictionary *>*(^VROInferenceBlock)(NSString*, const float*, int, float);

// ---------------------------------------------------------------------------
// ORT environment + session cache (shared_ptr for thread-safe lifetime)
// ---------------------------------------------------------------------------

static Ort::Env *gEnv = nullptr;
// shared_ptr: runInference holds a local copy — session survives even if
// the map is cleared while inference is in flight (no use-after-free).
static std::map<std::string, std::shared_ptr<Ort::Session>> gSessionMap;
// Class names from ONNX model metadata, keyed by model path.
// Access only on gSessionQueue.
static NSMutableDictionary<NSString *, NSArray<NSString *> *> *gClassNamesCache;
static dispatch_queue_t gSessionQueue;

static void ensureEnv() {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gSessionQueue = dispatch_queue_create("com.reactvision.onnx.sessions",
                                              DISPATCH_QUEUE_SERIAL);
        gClassNamesCache = [NSMutableDictionary dictionary];
        if (!Ort::Global<void>::api_) {
            Ort::Global<void>::api_ = OrtGetApiBase()->GetApi(ORT_API_VERSION);
        }
        gEnv = new Ort::Env(ORT_LOGGING_LEVEL_WARNING, "ViroONNX");
    });
}

// ---------------------------------------------------------------------------
// Class name parsing — Ultralytics ONNX metadata: {0: 'name', 1: 'name', ...}
// ---------------------------------------------------------------------------

static NSArray<NSString *> *parseClassNames(const char *raw) {
    if (!raw) return nil;
    NSString *src = [NSString stringWithUTF8String:raw];
    NSError *err  = nil;
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:@"(\\d+):\\s*['\"]([^'\"]*)['\"]"
        options:0 error:&err];
    if (!re || err) return nil;
    NSArray<NSTextCheckingResult *> *hits =
        [re matchesInString:src options:0 range:NSMakeRange(0, src.length)];
    if (!hits.count) return nil;

    NSUInteger maxIdx = 0;
    for (NSTextCheckingResult *h in hits) {
        NSUInteger idx = (NSUInteger)[[src substringWithRange:[h rangeAtIndex:1]] integerValue];
        if (idx > maxIdx) maxIdx = idx;
    }
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:maxIdx + 1];
    for (NSUInteger i = 0; i <= maxIdx; i++) [names addObject:@""];
    for (NSTextCheckingResult *h in hits) {
        NSUInteger idx = (NSUInteger)[[src substringWithRange:[h rangeAtIndex:1]] integerValue];
        if (idx < names.count) names[idx] = [src substringWithRange:[h rangeAtIndex:2]];
    }
    return [names copy];
}

// Call inside dispatch_sync on gSessionQueue.
static void loadClassNamesIfNeeded(NSString *modelPath,
                                   const std::shared_ptr<Ort::Session>& session) {
    if (gClassNamesCache[modelPath]) return;
    try {
        Ort::AllocatorWithDefaultOptions alloc;
        auto meta = session->GetModelMetadata();
        auto ptr  = meta.LookupCustomMetadataMapAllocated("names", alloc);
        if (ptr) {
            NSArray<NSString *> *names = parseClassNames(ptr.get());
            if (names) {
                gClassNamesCache[modelPath] = names;
            }
        }
    } catch (...) {
        NSLog(@"[ViroONNX] could not read class names from model metadata.");
    }
}

// ---------------------------------------------------------------------------
// NMS — greedy IoU suppression; input must be sorted by confidence descending
// ---------------------------------------------------------------------------

static float boxIoU(NSDictionary *a, NSDictionary *b) {
    NSDictionary *ba = a[@"boundingBox"], *bb = b[@"boundingBox"];
    float ax1 = [ba[@"x"] floatValue],  ay1 = [ba[@"y"] floatValue];
    float ax2 = ax1 + [ba[@"width"] floatValue], ay2 = ay1 + [ba[@"height"] floatValue];
    float bx1 = [bb[@"x"] floatValue],  by1 = [bb[@"y"] floatValue];
    float bx2 = bx1 + [bb[@"width"] floatValue], by2 = by1 + [bb[@"height"] floatValue];
    float iw  = MAX(0.f, MIN(ax2, bx2) - MAX(ax1, bx1));
    float ih  = MAX(0.f, MIN(ay2, by2) - MAX(ay1, by1));
    float inter = iw * ih;
    if (inter == 0.f) return 0.f;
    float ua = (ax2-ax1)*(ay2-ay1) + (bx2-bx1)*(by2-by1) - inter;
    return ua > 0.f ? inter / ua : 0.f;
}

static NSArray<NSDictionary *> *applyNMS(NSMutableArray<NSDictionary *> *dets,
                                         float iouThreshold) {
    NSMutableArray *keep = [NSMutableArray arrayWithCapacity:dets.count];
    NSMutableIndexSet *suppressed = [NSMutableIndexSet indexSet];
    for (NSUInteger i = 0; i < dets.count; i++) {
        if ([suppressed containsIndex:i]) continue;
        [keep addObject:dets[i]];
        for (NSUInteger j = i + 1; j < dets.count; j++) {
            if (![suppressed containsIndex:j] && boxIoU(dets[i], dets[j]) > iouThreshold)
                [suppressed addIndex:j];
        }
    }
    return keep;
}

// Returns a shared_ptr — caller holds a strong reference for the duration of inference.
static std::shared_ptr<Ort::Session> sessionForModelPath(NSString *modelPath) {
    ensureEnv();
    __block std::shared_ptr<Ort::Session> session;
    dispatch_sync(gSessionQueue, ^{
        auto it = gSessionMap.find(modelPath.UTF8String);
        if (it != gSessionMap.end()) {
            session = it->second; // copy: bumps ref count
            return;
        }
        try {
            Ort::SessionOptions opts;
            auto s = std::make_shared<Ort::Session>(*gEnv, modelPath.UTF8String, opts);
            gSessionMap[modelPath.UTF8String] = s;
            session = s;
            loadClassNamesIfNeeded(modelPath, s);  // reads metadata once per model
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
    NSString *modelPath,
    const float *nchwData,
    int inputSize,
    float confThreshold)
{
    // Local shared_ptr: session stays alive for the entire function even if
    // gSessionMap is cleared concurrently (e.g. detector unmounting).
    std::shared_ptr<Ort::Session> session = sessionForModelPath(modelPath);
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

        // Retrieve class names cached for this model (nil if metadata unavailable).
        __block NSArray<NSString *> *classNames = nil;
        dispatch_sync(gSessionQueue, ^{ classNames = gClassNamesCache[modelPath]; });

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

            int clsIdx = (int)p[5];
            NSString *label = (classNames && clsIdx >= 0 && clsIdx < (int)classNames.count)
                ? classNames[clsIdx]
                : [NSString stringWithFormat:@"%d", clsIdx];

            [dets addObject:@{
                @"label":       label,
                @"confidence":  @(conf),
                @"boundingBox": @{@"x": @(x1), @"y": @(y1), @"width": @(w), @"height": @(h)}
            }];
        }

        // Sort descending by confidence → required by greedy NMS.
        [dets sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            float ca = [a[@"confidence"] floatValue];
            float cb = [b[@"confidence"] floatValue];
            return ca > cb ? NSOrderedAscending : NSOrderedDescending;
        }];

        // NMS: suppress overlapping boxes (IoU > 0.45).
        NSArray *afterNMS = applyNMS(dets, 0.45f);

        // Cap at kMaxDetections (already sorted by confidence).
        NSArray *result = afterNMS.count > kMaxDetections
            ? [afterNMS subarrayWithRange:NSMakeRange(0, kMaxDetections)]
            : afterNMS;

        return result;

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

        // VRTObjectDetectorView posts this when it stops.
        // Clearing the map releases the shared_ptrs. If runInference is still
        // holding a local copy, the session stays alive until that copy drops —
        // no use-after-free possible.
        [[NSNotificationCenter defaultCenter]
            addObserverForName:@"VRODetectorSessionReleased"
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *) {
            dispatch_sync(gSessionQueue, ^{
                gSessionMap.clear(); // shared_ptrs released; actual delete deferred
            });
        }];
    });
}

+ (NSString *)ortVersion {
    return [NSString stringWithUTF8String:OrtGetApiBase()->GetVersionString()];
}

// +load fires when the dynamic framework is embedded and loaded by iOS, before main().
// +install only registers the inference block — it does NOT touch ORT (no ensureEnv()).
// ORT is initialized lazily in sessionForModelPath on the first actual inference call,
// by which time ORT's own C++ static initializers have already run.
+ (void)load {
    [self install];
}

@end
