#include "CMultitouch.h"

#include <dlfcn.h>

static const char *kFrameworkPath =
    "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport";

static void *handle;
static CFMutableArrayRef (*pDeviceCreateList)(void);
static void (*pRegister)(MTDeviceRef, CMTContactCallback);
static void (*pUnregister)(MTDeviceRef, CMTContactCallback);
static void (*pStart)(MTDeviceRef, int);
static void (*pStop)(MTDeviceRef);
static bool (*pIsBuiltIn)(MTDeviceRef);

bool CMTLoad(void) {
    if (handle != NULL) {
        return true;
    }
    void *h = dlopen(kFrameworkPath, RTLD_LAZY);
    if (h == NULL) {
        return false;
    }
    pDeviceCreateList = dlsym(h, "MTDeviceCreateList");
    pRegister = dlsym(h, "MTRegisterContactFrameCallback");
    pUnregister = dlsym(h, "MTUnregisterContactFrameCallback");
    pStart = dlsym(h, "MTDeviceStart");
    pStop = dlsym(h, "MTDeviceStop");
    pIsBuiltIn = dlsym(h, "MTDeviceIsBuiltIn");
    if (!pDeviceCreateList || !pRegister || !pUnregister || !pStart || !pStop) {
        dlclose(h);
        return false;
    }
    handle = h;
    return true;
}

CFArrayRef CMTDeviceCreateList(void) {
    if (!CMTLoad()) {
        return NULL;
    }
    return pDeviceCreateList();
}

void CMTRegisterContactFrameCallback(MTDeviceRef device, CMTContactCallback callback) {
    if (CMTLoad()) {
        pRegister(device, callback);
    }
}

void CMTUnregisterContactFrameCallback(MTDeviceRef device, CMTContactCallback callback) {
    if (CMTLoad()) {
        pUnregister(device, callback);
    }
}

void CMTDeviceStart(MTDeviceRef device) {
    if (CMTLoad()) {
        pStart(device, 0);
    }
}

void CMTDeviceStop(MTDeviceRef device) {
    if (CMTLoad()) {
        pStop(device);
    }
}

bool CMTDeviceIsBuiltIn(MTDeviceRef device) {
    if (CMTLoad() && pIsBuiltIn) {
        return pIsBuiltIn(device);
    }
    return false;
}
