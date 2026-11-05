#pragma once
#include <Arduino.h>
#include "Board.h"
#include "Gps.h"

/// The board's accelerometer, where it has one (the QMI8658 of the Waveshare
/// ESP32-C6-Touch-LCD-1.47), for g-forces measured rather than worked out from the GPS. It learns
/// how the board sits in the car by itself: which way is down while the car stands still, and which
/// way is forward from the GPS's speed going up and down on the straights. Both are kept in flash
/// for the next start, and learnt again when the board is moved. Elsewhere these do nothing.
namespace Imu {

/// No value: still learning, or no accelerometer.
const int16_t kNone = INT16_MIN;

#ifdef TRACKLAP_IMU_SDA
/// True when the chip answered.
bool begin();
/// "QMI8658", or empty without one.
const char* model();
/// From the main loop: reads the accelerometer about 200 times a second.
void poll();
/// At each GPS fix: the mean of the g since the previous one in milli-g, lateral (+ turning right)
/// and longitudinal (+ accelerating), kNone while the mounting is not known yet.
void take(const Fix& f, int16_t& lateral, int16_t& longitudinal);
/// "up ok, forward 42%" for the serial "info".
void describe(char* out, size_t n);
#else
inline bool begin() { return false; }
inline const char* model() { return ""; }
inline void poll() {}
inline void take(const Fix&, int16_t& lateral, int16_t& longitudinal) { lateral = longitudinal = kNone; }
inline void describe(char* out, size_t n) { snprintf(out, n, "none"); }
#endif

}  // namespace Imu
