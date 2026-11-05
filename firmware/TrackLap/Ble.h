#pragma once
#include <Arduino.h>
#include "Gps.h"
#include "Laps.h"

/// The TrackLap service of protocol v1 (see README): FIX and LAP notifications, TRACK and CONTROL
/// writes, INFO as JSON.
namespace Ble {

void begin(const char* name);
bool connected();
/// With the board's accelerometer, the g since the previous fix in milli-g (INT16_MIN for none).
void sendFix(const Fix& f, uint8_t rate, int16_t lateral = INT16_MIN, int16_t longitudinal = INT16_MIN);
void sendLap(const LapEvent& e);
void setInfo(const char* json);
/// The last TRACK or CONTROL write, copied out of the Bluetooth task; true once per write.
bool takeTrack(uint8_t* buf, size_t& len);
bool takeControl(uint8_t* buf, size_t& len);

}  // namespace Ble
