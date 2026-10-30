#pragma once
#include <Arduino.h>
#include "Gps.h"

/// What goes into a LAP packet.
struct LapEvent {
  uint8_t type;    // 1 = lap, 2 = sector
  uint16_t lap;    // the lap that ended, or the one the sector belongs to
  uint32_t ms;     // the lap's or the sector's own time
  uint8_t sector;  // the sector that ended, from 0
};

/// Lap and sector times from the start line and sector lines the app sends (TRACK packet), so the
/// ESP32 times laps by itself. The crossing time is interpolated between the two fixes around it.
class Laps {
 public:
  static const uint8_t kMaxLines = 8;

  /// False when the packet is not a valid TRACK packet; the old track stays.
  bool setTrack(const uint8_t* data, size_t len);
  void reset();
  /// The events this fix triggers (crossing the start line ends both the last sector and the lap).
  uint8_t feed(const Fix& f, LapEvent out[2]);
  uint8_t lines() const { return count_; }

 private:
  struct Line {
    double ax, ay, bx, by;  // longitude and latitude in 1e-7 degrees
  };

  Line lines_[kMaxLines];
  uint8_t count_ = 0;
  Fix prev_;
  bool havePrev_ = false;
  double t_ = 0;  // seconds since the first fix
  bool running_ = false;
  double lapStart_ = 0;
  double lineTime_ = 0;
  uint8_t next_ = 1;  // the sector line expected next
  uint16_t lap_ = 0;
};
