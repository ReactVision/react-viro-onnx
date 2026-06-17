//
//  ViroONNX.h
//  ViroReactONNX
//
//  Copyright © 2026 ReactVision. All rights reserved.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * ViroONNX — registers ONNX Runtime (C++ API) as the inference provider
 * for VRTObjectDetectorView. Registration happens automatically via +load
 * when the ViroReactONNX framework is embedded in the app. No JS call needed.
 */
@interface ViroONNX : NSObject

/** Registers the ORT inference provider with VRTObjectDetectorView (idempotent). */
+ (void)install;

/** Returns the linked ONNX Runtime version string, e.g. "1.20.0". */
+ (NSString *)ortVersion;

@end

NS_ASSUME_NONNULL_END
