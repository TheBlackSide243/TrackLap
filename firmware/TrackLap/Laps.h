#pragma once
#include <Arduino.h>
#include "Gps.h"

/// What goes into a LAP packet and onto the screen.
struct LapEvent {
  uint8_t type;    // 1 = lap, 2 = sector
  uint16_t lap;    // the lap that ended, or the one the sector belongs to
  uint32_t ms;     // the lap's or the sector's own time
  uint8_t sector;  // the sector that ended, from 0
  int32_t delta;   // ms against the best lap at the same line, kNoDelta without one
  bool best;       // a lap faster than the best one
};

const int32_t kNoDelta = INT32_MAX;

/// Lap and sector times from the start line and sector lines the app sends (TRACK packet), so the
/// ESP32 times laps by itself. The crossing time is interpolated between the two fixes around it.
/// Each line also gets the delta against the best lap, which is kept until the track changes.
class Laps {
 public:
  static const uint8_t kMaxLines = 8;

  /// The best lap: its time and when it crossed each sector line, in ms from the start line.
  struct Best {
    uint32_t lap = 0;  // 0 = no best lap yet
    uint32_t split[kMaxLines] = {};
  };

  /// False when the packet is not a valid TRACK packet; the old track stays.
  bool setTrack(const uint8_t* data, size_t len);
  void reset();
  /// The events this fix triggers (crossing the start line ends both the last sector and the lap).
  uint8_t feed(const Fix& f, LapEvent out[2]);

  uint8_t lines() const { return count_; }
  bool running() const { return running_; }
  /// The lap in progress, from 1.
  uint16_t lap() const { return lap_ + 1; }
  /// Seconds from the start of the lap in progress to the last fix.
  double sinceStart() const { return t_ - lapStart_; }
  uint32_t lastLap() const { return last_; }
  const Best& best() const { return best_; }
  void setBest(const Best& b) { best_ = b; }
  /// True once after a new best lap, so it can be saved.
  bool takeNewBest();

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
  uint32_t split_[kMaxLines] = {};  // this lap's crossings, in ms from the start line
  uint32_t last_ = 0;
  Best best_;
  bool newBest_ = false;
};
