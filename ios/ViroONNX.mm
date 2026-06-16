//
//  ViroONNX.mm
//  ViroReactONNX
//
//  Copyright © 2026 ReactVision. All rights reserved.
//
//  Registers ONNX Runtime as the inference provider for VRTObjectDetectorView.
//  The actual ORT session is created lazily on first inference call per model path.

#import "ViroONNX.h"
#import <React/RCTLog.h>
#import <Accelerate/Accelerate.h>

// Import VRTObjectDetectorView from the ViroReact pod.
// The header is available because ViroReact is a dependency.
#import <ViroReact/VRTObjectDetectorView.h>

#import <onnxruntime/ort_session.h>
#import <onnxruntime/ort_env.h>
#import <onnxruntime/ort_value.h>

// ---------------------------------------------------------------------------
// Constants (must match VRTObjectDetectorView.mm)
// ---------------------------------------------------------------------------

static const int kModelInputSize = 640;
static const int kNumProposals   = 300;
static const int kProposalDim    = 38;

// ---------------------------------------------------------------------------
// ORT session cache
// ---------------------------------------------------------------------------

// One environment shared across all sessions.
static ORTEnv *gOrtEnv = nil;

// Model path → ORTSession cache (one session per model).
static NSMutableDictionary<NSString *, ORTSession *> *gSessions = nil;
static dispatch_queue_t gSessionQueue;

static void ensureEnv() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSessions    = [NSMutableDictionary dictionary];
        gSessionQueue = dispatch_queue_create("com.reactvision.onnx.sessions", DISPATCH_QUEUE_SERIAL);
        NSError *err = nil;
        gOrtEnv = [[ORTEnv alloc] initWithLoggingLevel:ORTLoggingLevelWarning error:&err];
        if (err) RCTLogError(@"ViroONNX: failed to create ORT env: %@", err);
    });
}

static ORTSession * _Nullable sessionForModelPath(NSString *modelPath) {
    ensureEnv();
    __block ORTSession *session = nil;
    dispatch_sync(gSessionQueue, ^{
        session = gSessions[modelPath];
        if (!session) {
            NSError *err = nil;
            ORTSessionOptions *opts = [[ORTSessionOptions alloc] initWithError:&err];
            if (err) { RCTLogError(@"ViroONNX: session options error: %@", err); return; }

            session = [[ORTSession alloc] initWithEnv:gOrtEnv
                                            modelPath:modelPath
                                       sessionOptions:opts
                                                error:&err];
            if (err || !session) {
                RCTLogError(@"ViroONNX: failed to load model %@: %@", modelPath, err);
                return;
            }
            gSessions[modelPath] = session;
            RCTLogInfo(@"ViroONNX: loaded model %@", modelPath);
        }
    });
    return session;
}

// ---------------------------------------------------------------------------
// Inference block
// ---------------------------------------------------------------------------

static NSArray<NSDictionary *> *runInference(
    NSString *modelPath,
    const float *nchwData,
    int inputSize,
    float confThreshold)
{
    ORTSession *session = sessionForModelPath(modelPath);
    if (!session) return @[];

    NSError *err = nil;

    // Wrap input data (no copy).
    NSData *inputNSData = [NSData dataWithBytesNoCopy:(void *)nchwData
                                               length:sizeof(float) * 3 * inputSize * inputSize
                                         freeWhenDone:NO];
    ORTValue *inputTensor = [ORTValue tensorWithData:inputNSData
                                        elementType:ORTTensorElementDataTypeFloat
                                              shape:@[@1, @3, @(inputSize), @(inputSize)]
                                              error:&err];
    if (!inputTensor || err) return @[];

    NSDictionary *outputs = [session runWithInputs:@{@"images": inputTensor}
                                       outputNames:[NSSet setWithObject:@"output0"]
                                       runOptions:nil
                                             error:&err];
    if (!outputs || err) return @[];

    NSData *outData = [outputs[@"output0"] tensorDataWithError:&err];
    if (!outData || err) return @[];

    const float *ptr   = (const float *)outData.bytes;
    const float scale  = 1.0f / (float)inputSize;
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
            @"boundingBox": @{@"x": @(x1), @"y": @(y1), @"width": @(w), @"height": @(h)}
        }];
    }
    return [dets copy];
}

// ---------------------------------------------------------------------------
// ViroONNX native module
// ---------------------------------------------------------------------------

@implementation ViroONNX

RCT_EXPORT_MODULE()

+ (void)install {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ensureEnv();
        [VRTObjectDetectorView registerInferenceProvider:^NSArray<NSDictionary *> *(
            NSString *modelPath,
            const float *nchwData,
            int inputSize,
            float confThreshold)
        {
            return runInference(modelPath, nchwData, inputSize, confThreshold);
        }];
        RCTLogInfo(@"ViroONNX: inference provider registered.");
    });
}

RCT_EXPORT_METHOD(install) {
    [[self class] install];
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(getVersion) {
    // ORTVersion() returns a char* like "1.20.0"
    return [NSString stringWithUTF8String:OrtGetApiBase()->GetVersionString()];
}

+ (BOOL)requiresMainQueueSetup { return NO; }

@end
