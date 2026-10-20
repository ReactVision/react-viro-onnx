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

#include "viro_onnx.h"

// ---------------------------------------------------------------------------
// Block type — must match VRTInferenceBlock in VRTObjectDetectorView.h exactly.
// ---------------------------------------------------------------------------

typedef NSArray<NSDictionary *>*(^VROInferenceBlock)(NSString*, const float*, int, float);

// Internal ceiling on detections returned to the host. The host
// (VRTObjectDetectorView) trims to its `maxDetections` prop, so this only needs to
// be comfortably above any expected prop value. Results are confidence-sorted, so
// the host keeps the top-N.
static const int kMaxDetections = 50;

// ---------------------------------------------------------------------------
// Inference
//
// The model, the decoding of its 300 proposals, NMS and the class names live in the
// Eskiu core (core/, ViroONNXCore.xcframework), shared with Android. A session is
// opened once per model path; ONNX Runtime is touched only then, after its static
// initializers have run.
// ---------------------------------------------------------------------------

static NSArray<NSDictionary *> *runInference(
    NSString *modelPath,
    const float *nchwData,
    int inputSize,
    float confThreshold)
{
    const char *path = modelPath.UTF8String;
    // CoreML only as an ML Program, which needs iOS 15; below it the CPU.
    int accel = VIRO_ONNX_CPU;
    if (@available(iOS 15.0, *)) accel = VIRO_ONNX_COREML;
    if (!viro_onnx_load_file(path, path, accel)) {
        NSLog(@"[ViroONNX] failed to load model '%@': %s", modelPath, viro_onnx_last_error());
        return @[];
    }
    ViroDetection dets[kMaxDetections];
    int n = viro_onnx_detect(path, nchwData, inputSize, confThreshold, dets, kMaxDetections);
    if (n < 0) {
        NSLog(@"[ViroONNX] inference error: %s", viro_onnx_last_error());
        return @[];
    }
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:n];
    for (int i = 0; i < n; i++) {
        const ViroDetection *d = &dets[i];
        NSString *label = d->label ? [NSString stringWithUTF8String:d->label]
                                   : [NSString stringWithFormat:@"%d", d->class_index];
        [result addObject:@{
            @"label":       label,
            @"confidence":  @(d->confidence),
            @"boundingBox": @{@"x": @(d->x), @"y": @(d->y), @"width": @(d->width), @"height": @(d->height)}
        }];
    }
    return result;
}

// ---------------------------------------------------------------------------
// ViroONNX
// ---------------------------------------------------------------------------

@implementation ViroONNX

+ (void)install {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Do NOT touch ORT here — +load fires before ORT's xcframework C++ static
        // initializers run.
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

        // VRTObjectDetectorView posts this when it stops. A detection still in
        // flight keeps its session until it returns, so there is no use-after-free.
        [[NSNotificationCenter defaultCenter]
            addObserverForName:@"VRODetectorSessionReleased"
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *) {
            viro_onnx_release_all();
        }];
    });
}

+ (NSString *)ortVersion {
    return [NSString stringWithUTF8String:viro_onnx_ort_version()];
}

// +load fires when the dynamic framework is embedded and loaded by iOS, before main().
// +install only registers the inference block — it does NOT touch ORT. The core
// initializes ORT lazily on the first inference call, by which time ORT's own C++
// static initializers have already run.
+ (void)load {
    [self install];
}

@end
