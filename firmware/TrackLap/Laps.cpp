#include "Laps.h"

namespace {

// A lap shorter than this is GPS noise around the start line.
const double kMinLap = 10;

int32_t i32(const uint8_t* p) {
  return (int32_t)(p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24);
}

uint32_t ms(double s) { return (uint32_t)lround(s * 1000); }

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
        if (count_ > 1 && next_ == count_) out[n++] = {2, (uint16_t)(lap_ + 1), ms(at - lineTime_), (uint8_t)(count_ - 1)};
        lap_++;
        out[n++] = {1, lap_, ms(at - lapStart_), 0};
      }
      running_ = true;
      lapStart_ = lineTime_ = at;
      next_ = 1;
    } else if (running_ && i == next_) {
      out[n++] = {2, (uint16_t)(lap_ + 1), ms(at - lineTime_), (uint8_t)(i - 1)};
      lineTime_ = at;
      next_++;
    }
  }
  return n;
}
