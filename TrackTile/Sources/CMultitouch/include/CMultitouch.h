#ifndef CMULTITOUCH_H
#define CMULTITOUCH_H

#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>
#include <stdint.h>

// Minimal declarations for the private MultitouchSupport.framework.
// The layout of MTTouch must match the framework exactly; it has been stable
// since macOS 10.5.

typedef const void *MTDeviceRef;

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;
    MTPoint velocity;
} MTVector;

typedef enum : int32_t {
    MTTouchStateNotTracking = 0,
    MTTouchStateStartInRange = 1,
    MTTouchStateHoverInRange = 2,
    MTTouchStateMakeTouch = 3,
    MTTouchStateTouching = 4,
    MTTouchStateBreakTouch = 5,
    MTTouchStateLingerInRange = 6,
    MTTouchStateOutOfRange = 7,
} MTTouchState;

typedef struct {
    int32_t frame;
    double timestamp;
    int32_t identifier;
    MTTouchState state;
    int32_t fingerId;
    int32_t handId;
    MTVector normalized;
    float size;
    int32_t zero1;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolute;
    int32_t zero2;
    int32_t zero3;
    float density;
} MTTouch;

typedef int (*CMTContactCallback)(MTDeviceRef _Nonnull device, const MTTouch *_Nullable touches, int32_t count, double timestamp, int32_t frame);

/// Loads MultitouchSupport.framework with dlopen. Safe to call repeatedly.
bool CMTLoad(void);

/// Returns a retained array of MTDeviceRef, or NULL.
CFArrayRef _Nullable CMTDeviceCreateList(void) CF_RETURNS_RETAINED;

void CMTRegisterContactFrameCallback(MTDeviceRef _Nonnull device, CMTContactCallback _Nonnull callback);
void CMTUnregisterContactFrameCallback(MTDeviceRef _Nonnull device, CMTContactCallback _Nonnull callback);
void CMTDeviceStart(MTDeviceRef _Nonnull device);
void CMTDeviceStop(MTDeviceRef _Nonnull device);
bool CMTDeviceIsBuiltIn(MTDeviceRef _Nonnull device);

#endif
