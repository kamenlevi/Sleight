#ifndef CMULTITOUCH_H
#define CMULTITOUCH_H

#include <stdint.h>

// Touch structures for Apple's private MultitouchSupport.framework.
// This is the long-established layout used by the multitouch reverse-
// engineering community (BetterTouchTool, OpenMultitouchSupport, etc.).
// Declared in C so the memory layout is guaranteed when the framework
// hands us frames of touches.

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;  // normalized 0..1, origin bottom-left
    MTPoint velocity;
} MTVector;

typedef struct {
    int32_t frame;
    double timestamp;
    int32_t pathIndex;   // stable id for one finger's touch path
    int32_t state;       // 1 hover .. 4 touching .. 7 leaving
    int32_t fingerID;
    int32_t handID;
    MTVector normalized;
    float total;         // touch intensity / size
    int32_t pressure;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolute;   // millimeters
    int32_t field14;
    int32_t field15;
    float density;
} MTTouch;

#endif
