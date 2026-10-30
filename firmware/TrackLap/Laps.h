#pragma once
#include <Arduino.h>
#include "Gps.h"

/// How a time compares, which is its colour on the screen: Fastest (purple) is the fastest of all;
/// Better (green) and Worse (red) are against the previous lap at a sector line and against the
/// session's average at the finish; None when there is nothing to compare with yet.
enum class Grade : uint8_t { None, Fastest, Better, Worse };

/// What goes into a LAP packet and onto the screen.
struct LapEvent {
  uint8_t type;    // 1 = lap, 2 = sector
  uint16_t lap;    // the lap that ended, or the one the sector belongs to
  uint32_t ms;     // the lap's or the sector's own time
  uint8_t sector;  // the sector that ended, from 0
  int32_t delta;   // ms against the best lap at the same line, kNoDelta without one
  bool best;       // a lap faster than the best one
  Grade grade;
};

const int32_t kNoDelta = INT32_MAX;

/// Lap and sector times from the start line and sector lines the app sends (TRACK packet), so the
/// ESP32 times laps by itself. The crossing time is interpolated between the two fixes around it.
/// Each line also gets the delta against the best lap, which is kept until the track changes.
class Laps {
 public:
  static const uint8_t kMaxLines = 8;

  /// What is kept for the track, in ms from the start line: the best lap and when it crossed each
  /// sector line, and the fastest time ever at each sector line, whatever the lap.
  struct Best {
    uint32_t lap = 0;  // 0 = no best lap yet
    uint32_t split[kMaxLines] = {};
    uint32_t fastest[kMaxLines] = {};
  };

  /// False when the packet is not a valid TRACK packet; the old track stays.
  bool setTrack(const uint8_t* data, size_t len);
  /// A new session: the lap count, the previous lap and the average start again; the best stays.
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
  /// True once after the best lap or a fastest sector time changed, so it can be saved.
  bool takeChanged();

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
  uint32_t split_[kMaxLines] = {};      // this lap's crossings, in ms from the start line
  uint32_t prevSplit_[kMaxLines] = {};  // the previous lap's
  uint32_t last_ = 0;
  uint64_t sessionSum_ = 0;
  uint16_t sessionLaps_ = 0;
  Best best_;
  bool changed_ = false;
};
