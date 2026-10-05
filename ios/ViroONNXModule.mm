//
//  ViroONNXModule.mm
//  ViroReactONNX
//
//  Copyright © 2026 ReactVision. All rights reserved.
//
//  The React Native half of the package. ViroONNX itself stays a plain framework whose +load
//  installs the ORT inference provider, because that path must not depend on the bridge being up.
//  This module exists only so JS can reach +[ViroONNX ortVersion].
//
//  Without it, NativeModules.ViroONNX was undefined and ViroONNX.getVersion() in JS fell through
//  to its `?? 'unavailable'` on every iOS device, while the same call on Android returned the real
//  version. The version was always there — nothing exposed it.

#import <React/RCTBridgeModule.h>

#import "ViroONNX.h"

@interface ViroONNXModule : NSObject <RCTBridgeModule>
@end

@implementation ViroONNXModule

RCT_EXPORT_MODULE(ViroONNX)

/*
 Synchronous to match the Android module, whose getVersion() is a blocking synchronous method, and
 the JS surface, a plain `getVersion(): string`. The linked runtime cannot change at runtime.
 */
RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(getVersion)
{
  return [ViroONNX ortVersion];
}

/* The provider is installed from +load; nothing here touches the UI. */
+ (BOOL)requiresMainQueueSetup
{
  return NO;
}

@end
