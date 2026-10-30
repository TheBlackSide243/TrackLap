#pragma once
#include <Arduino.h>
#include "Laps.h"

/// What the screen shows, filled in by the main loop.
struct DashState {
  bool gpsData = false;  // something arrived from the GPS in the last 1.5 s
  bool fix = false;
  uint8_t sats = 0;
  uint8_t rate = 0;
  uint32_t speed = 0;  // cm/s
  bool connected = false;
  bool hasTrack = false;
  bool running = false;
  double elapsed = 0;  // seconds into the lap in progress
  uint16_t lap = 0;    // the lap in progress
  uint32_t best = 0;   // ms, 0 = none
  uint32_t last = 0;
  int gpsRx = 0;
  int gpsTx = 0;
};

/// The dashboard on the board's screen, for boards that have one (built with TRACKLAP_LCD147 for the
/// Waveshare ESP32-C6-LCD-1.47): the lap time, the delta at each sector line, the lap time at the
/// finish, the place in the app's live group. Elsewhere these do nothing.
namespace Display {
#ifdef TRACKLAP_LCD147
void begin();
void show(const DashState& s);
void event(const LapEvent& e);
/// The place in the live group (position 0 = not in one) and the gap in ms to the driver just ahead,
/// negative when first (the margin over the second), kNoDelta for none.
void group(uint8_t position, uint8_t count, int32_t gap);
#else
inline void begin() {}
inline void show(const DashState&) {}
inline void event(const LapEvent&) {}
inline void group(uint8_t, uint8_t, int32_t) {}
#endif
}  // namespace Display
