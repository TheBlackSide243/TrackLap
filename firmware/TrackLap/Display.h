#pragma once
#include <Arduino.h>
#include "Board.h"
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
/// Waveshare ESP32-C6-LCD-1.47, TRACKLAP_LCD147T for the Touch version, TRACKLAP_LCD169 for the
/// ESP32-C6-LCD-1.69): the lap time, the delta at each sector line, the lap time at the
/// finish, the place in the app's live group; or, while the app's Drag tab is open, the speed with
/// the drag timer's state and results. Elsewhere these do nothing.
namespace Display {
#ifdef TRACKLAP_DISPLAY
void begin();
void show(const DashState& s);
void event(const LapEvent& e);
/// The place in the live group (position 0 = not in one) and the gap in ms to the driver just ahead,
/// negative when first (the margin over the second), kNoDelta for none.
void group(uint8_t position, uint8_t count, int32_t gap);
/// The drag dashboard: `on` false puts the lap one back; state 0 waiting for a stop, 1 ready, 2 a run
/// `elapsed` ms old.
void drag(bool on, uint8_t state, uint32_t elapsed);
/// A drag result for 5 s: a time in ms, or a distance in cm; purple for a best.
void dragResult(const char* label, uint32_t value, bool distance, bool best);
#else
inline void begin() {}
inline void show(const DashState&) {}
inline void event(const LapEvent&) {}
inline void group(uint8_t, uint8_t, int32_t) {}
inline void drag(bool, uint8_t, uint32_t) {}
inline void dragResult(const char*, uint32_t, bool, bool) {}
#endif
}  // namespace Display
