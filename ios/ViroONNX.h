//
//  ViroONNX.h
//  ViroReactONNX
//
//  Copyright © 2026 ReactVision. All rights reserved.

#import <React/RCTBridgeModule.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * ViroONNX — native module that installs ONNX Runtime as the inference
 * provider for VRTObjectDetectorView.
 *
 * Call ViroONNX.install() once from JS before mounting any ViroObjectDetector.
 */
@interface ViroONNX : NSObject <RCTBridgeModule>

/** Registers the ORT inference provider with VRTObjectDetectorView (idempotent). */
+ (void)install;

@end

NS_ASSUME_NONNULL_END
