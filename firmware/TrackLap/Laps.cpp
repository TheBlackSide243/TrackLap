#include "Laps.h"

namespace {

// A lap shorter than this is GPS noise around the start line.
const double kMinLap = 10;

int32_t i32(const uint8_t* p) {
  return (int32_t)(p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24);
}

uint32_t ms(double s) { return (uint32_t)lround(s * 1000); }

int32_t delta(uint32_t now, uint32_t best) { return best ? (int32_t)now - (int32_t)best : kNoDelta; }

// At a line: purple when it beats the fastest time there, otherwise against the previous lap.
Grade lineGrade(uint32_t now, uint32_t fastest, uint32_t previous) {
  if (fastest && now < fastest) return Grade::Fastest;
  if (!previous) return Grade::None;
  return now < previous ? Grade::Better : Grade::Worse;
}

}  // namespace

bool Laps::setTrack(const uint8_t* data, size_t len) {
  if (len < 2 || data[0] != 1) return false;
  uint8_t n = data[1];
  if (n == 0 || n > kMaxLines || len < 2 + 16u * n) return false;
  for (uint8_t i = 0; i < n; i++) {
    const uint8_t* p = data + 2 + 16 * i;
    lines_[i] = {(double)i32(p + 4), (double)i32(p), (double)i32(p + 12), (double)i32(p + 8)};
  }
  count_ = n;
  reset();
  return true;
}

void Laps::reset() {
  running_ = false;
  lap_ = 0;
  next_ = 1;
  last_ = 0;
  sessionSum_ = 0;
  sessionLaps_ = 0;
  memset(prevSplit_, 0, sizeof prevSplit_);
}

bool Laps::takeChanged() {
  bool c = changed_;
  changed_ = false;
  return c;
}

uint8_t Laps::feed(const Fix& f, LapEvent out[2]) {
  if (!f.valid) return 0;
  if (!havePrev_) {
    prev_ = f;
    havePrev_ = true;
    return 0;
  }
  int32_t dms = (int32_t)(f.itow - prev_.itow);
  if (dms < 0) dms += 604800000;  // a new GPS week
  double dt = dms / 1000.0;
  Fix p = prev_;
  prev_ = f;
  double t0 = t_;
  t_ += dt;
  // No crossing over a gap: the line could have been anywhere in it.
  if (count_ == 0 || dt <= 0 || dt > 2) return 0;

  // Where p→f crosses each line, as a share of the step (affine maps keep it, so degrees do).
  double rx = (double)f.lon - p.lon, ry = (double)f.lat - p.lat;
  uint8_t n = 0;
  for (uint8_t i = 0; i < count_ && n < 2; i++) {
    const Line& l = lines_[i];
    double sx = l.bx - l.ax, sy = l.by - l.ay;
    double den = rx * sy - ry * sx;
    if (den == 0) continue;
    double ux = l.ax - p.lon, uy = l.ay - p.lat;
    double k = (ux * sy - uy * sx) / den;
    double u = (ux * ry - uy * rx) / den;
    if (k < 0 || k > 1 || u < 0 || u > 1) continue;
    double at = t0 + k * dt;

    if (i == 0) {
      if (running_ && at - lapStart_ < kMinLap) continue;
      if (running_) {
        uint32_t lap = ms(at - lapStart_);
        int32_t d = delta(lap, best_.lap);
        bool best = !best_.lap || lap < best_.lap;
        if (count_ > 1 && next_ == count_) {
          out[n++] = {2, (uint16_t)(lap_ + 1), ms(at - lineTime_), (uint8_t)(count_ - 1), d, false,
                      lineGrade(lap, best_.lap, last_)};
        }
        // The finish: purple for a best lap, otherwise against the average of the session so far.
        Grade grade = best ? Grade::Fastest
                      : !sessionLaps_ ? Grade::None
                      : lap < sessionSum_ / sessionLaps_ ? Grade::Better
                                                         : Grade::Worse;
        lap_++;
        last_ = lap;
        sessionSum_ += lap;
        sessionLaps_++;
        out[n++] = {1, lap_, lap, 0, d, best, grade};
        if (best) {
          // Sector lines missed on this lap stay 0: no delta there until a full lap beats it.
          best_.lap = lap;
          memcpy(best_.split, split_, sizeof split_);
          changed_ = true;
        }
        memcpy(prevSplit_, split_, sizeof split_);
      }
      running_ = true;
      lapStart_ = lineTime_ = at;
      next_ = 1;
      memset(split_, 0, sizeof split_);
    } else if (running_ && i == next_) {
      uint32_t now = ms(at - lapStart_);
      split_[i] = now;
      Grade grade = lineGrade(now, best_.fastest[i], prevSplit_[i]);
      out[n++] = {2, (uint16_t)(lap_ + 1), ms(at - lineTime_), (uint8_t)(i - 1), delta(now, best_.split[i]), false, grade};
      if (!best_.fastest[i] || now < best_.fastest[i]) {
        best_.fastest[i] = now;
        changed_ = true;
      }
      lineTime_ = at;
      next_++;
    }
  }
  return n;
}
