#pragma once
#include <Arduino.h>
#include "Board.h"
#include "Gps.h"

/// The picture the right way up, however the board is mounted. The BOOT button turns it over, and so
/// does "flip" over USB serial. A board with an accelerometer then does it by itself when it is put
/// the other way up. How the chip sits behind each screen is written nowhere, so the board learns
/// it: where gravity pulls along the screen while the picture reads right. That is the first
/// position it rests in standing up, and from then on whatever a press of BOOT says. Lying flat,
/// or on the move, the picture stays as it is. Elsewhere these do nothing.
namespace Screen {
#ifdef TRACKLAP_DISPLAY
/// Starts the display the way it was left.
void begin();
/// From the main loop, with the last fix and whether it is fresh: reads BOOT and, with the board
/// at rest, its accelerometer.
void poll(const Fix& last, bool fresh);
/// Turns the picture over, as BOOT does.
void flip();
/// "upside down, right way up learnt" for the serial "info".
void describe(char* out, size_t n);
#else
inline void begin() {}
inline void poll(const Fix&, bool) {}
inline void flip() {}
inline void describe(char* out, size_t n) { snprintf(out, n, "none"); }
#endif
}  // namespace Screen
