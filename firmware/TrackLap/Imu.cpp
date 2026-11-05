#include "Imu.h"

#ifdef TRACKLAP_IMU_SDA
#include <Preferences.h>
#include <Wire.h>
#include <math.h>

namespace {

// QMI8658 registers.
const uint8_t kWhoAmI = 0x00;  // reads 0x05
const uint8_t kCtrl1 = 0x02;   // 0x40: register address auto-increment, little-endian
const uint8_t kCtrl2 = 0x03;   // accelerometer range and rate
const uint8_t kCtrl5 = 0x06;   // low-pass filters
const uint8_t kCtrl7 = 0x08;   // which sensors run
const uint8_t kAccelX = 0x35;  // X, Y, Z as i16, low byte first
const uint8_t kReset = 0x60;   // 0xB0 = soft reset
const float kPerG = 4096.0f;   // ±8 g

struct Vec {
  float x = 0, y = 0, z = 0;
  Vec operator+(const Vec& o) const { return {x + o.x, y + o.y, z + o.z}; }
  Vec operator-(const Vec& o) const { return {x - o.x, y - o.y, z - o.z}; }
  Vec operator*(float k) const { return {x * k, y * k, z * k}; }
  float dot(const Vec& o) const { return x * o.x + y * o.y + z * o.z; }
  Vec cross(const Vec& o) const { return {y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x}; }
  float length() const { return sqrtf(dot(*this)); }
  Vec unit() const {
    float l = length();
    return l > 1e-6f ? *this * (1 / l) : Vec();
  }
};

uint8_t address = 0;
uint32_t lastRead = 0;
Vec sum;
uint16_t count = 0;

// The mounting: gravity as the chip reads it standing still (it points up, about 1 g), and the
// evidence for forward, the sum of the horizontal g times the GPS's own longitudinal g.
Preferences store;
bool hasUp = false;
Vec up;
Vec evidence;
float weight = 0;
bool checkedUp = false;  // the saved mounting compared with the board as it sits now
uint32_t savedAt = 0;
Vec savedUp, savedForward;

// The previous fix, for the GPS's longitudinal g and turn rate.
bool hasPrev = false;
uint32_t prevItow = 0;
float prevSpeed = 0, prevHeading = 0;
float stillFor = 0;

const float kNeeded = 0.4f;  // weight of evidence before forward counts (about 40 fixes at 0.1 g)

bool write(uint8_t reg, uint8_t value) {
  Wire.beginTransmission(address);
  Wire.write(reg);
  Wire.write(value);
  return Wire.endTransmission() == 0;
}

bool read(uint8_t reg, uint8_t* out, uint8_t n) {
  Wire.beginTransmission(address);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom(address, n) != n) return false;
  for (uint8_t i = 0; i < n; i++) out[i] = Wire.read();
  return true;
}

bool forwardKnown() { return weight >= kNeeded && evidence.length() > 0.2f * weight; }

Vec forward() {
  // In the horizontal plane, whatever tilt the evidence picked up.
  Vec u = up.unit();
  return (evidence - u * evidence.dot(u)).unit();
}

float degreesBetween(const Vec& a, const Vec& b) {
  float c = a.unit().dot(b.unit());
  return acosf(c > 1 ? 1 : c < -1 ? -1 : c) * 57.2958f;
}

void load() {
  store.begin("imu", false);
  float v[6];
  if (store.getBytes("mount", v, sizeof v) != sizeof v) return;
  up = {v[0], v[1], v[2]};
  hasUp = up.length() > 0.5f;
  Vec f = {v[3], v[4], v[5]};
  if (f.length() > 0.5f) {
    evidence = f * kNeeded;
    weight = kNeeded;
  }
  savedUp = up;
  savedForward = f;
}

// Into flash at most once a minute, and only when the mounting has moved by a few degrees.
void save(uint32_t now) {
  if (now - savedAt < 60000 && savedAt) return;
  Vec f = forwardKnown() ? forward() : Vec();
  bool upMoved = savedUp.length() < 0.5f || degreesBetween(savedUp, up) > 2;
  bool forwardMoved = f.length() > 0.5f && (savedForward.length() < 0.5f || degreesBetween(savedForward, f) > 3);
  if (!upMoved && !forwardMoved) return;
  float v[6] = {up.x, up.y, up.z, f.x, f.y, f.z};
  store.putBytes("mount", v, sizeof v);
  savedUp = up;
  savedForward = f;
  savedAt = now;
}

}  // namespace

bool Imu::begin() {
  Wire.begin(TRACKLAP_IMU_SDA, TRACKLAP_IMU_SCL, 400000);
  for (uint8_t a : {0x6B, 0x6A}) {
    address = a;
    uint8_t id = 0;
    if (read(kWhoAmI, &id, 1) && id == 0x05) break;
    address = 0;
  }
  if (!address) return false;
  write(kReset, 0xB0);
  delay(20);
  write(kCtrl1, 0x40);
  write(kCtrl2, 0x25);  // ±8 g, 250 Hz
  write(kCtrl5, 0x01);  // the accelerometer's low-pass filter on
  write(kCtrl7, 0x01);  // the accelerometer only
  load();
  return true;
}

const char* Imu::model() { return address ? "QMI8658" : ""; }

void Imu::poll() {
  if (!address) return;
  uint32_t now = millis();
  if (now - lastRead < 5) return;
  lastRead = now;
  uint8_t b[6];
  if (!read(kAccelX, b, sizeof b)) return;
  Vec a = {(int16_t)(b[0] | b[1] << 8) / kPerG, (int16_t)(b[2] | b[3] << 8) / kPerG, (int16_t)(b[4] | b[5] << 8) / kPerG};
  sum = sum + a;
  if (count < 60000) count++;
}

void Imu::take(const Fix& f, int16_t& lateral, int16_t& longitudinal) {
  lateral = longitudinal = kNone;
  if (!address || !count) return;
  Vec m = sum * (1.0f / count);
  sum = Vec();
  count = 0;

  // The GPS's own view since the previous fix.
  float speed = f.speed / 100.0f;
  float heading = f.heading / 100.0f;
  float dt = hasPrev ? (f.itow - prevItow) / 1000.0f : 0;
  bool step = f.valid && hasPrev && dt > 0.02f && dt < 0.6f;
  float gpsG = step ? (speed - prevSpeed) / dt / 9.81f : 0;
  float turn = 0;
  if (step) {
    float dh = heading - prevHeading;
    if (dh > 180) dh -= 360;
    if (dh < -180) dh += 360;
    turn = dh / dt;
  }
  hasPrev = f.valid;
  prevItow = f.itow;
  prevSpeed = speed;
  prevHeading = heading;

  // Standing still for a second and a half: that is down (the chip reads it as 1 g up).
  stillFor = f.valid && speed < 0.3f && fabsf(m.length() - 1) < 0.15f ? stillFor + (step ? dt : 0) : 0;
  if (stillFor > 1.5f) {
    if (!checkedUp && hasUp && degreesBetween(up, m) > 10) {
      // The board was moved since the mounting was saved: forward has to be learnt again.
      evidence = Vec();
      weight = 0;
      hasUp = false;
    }
    checkedUp = true;
    up = hasUp ? up * 0.9f + m * 0.1f : m;
    hasUp = true;
    save(millis());
  }
  if (!hasUp) return;

  Vec u = up.unit();
  Vec a = m - up;                // the car's acceleration, in g
  Vec h = a - u * a.dot(u);      // in the horizontal plane

  // On a straight, speeding up or braking: the horizontal g lines up with forward.
  if (step && speed > 3 && fabsf(gpsG) > 0.1f && fabsf(turn) < 3) {
    evidence = evidence * 0.998f + h * gpsG;
    weight = weight * 0.998f + gpsG * gpsG;
    save(millis());
  }
  if (!forwardKnown()) return;

  Vec fw = forward();
  Vec right = fw.cross(u);
  float lat = h.dot(right), lon = h.dot(fw);
  auto mg = [](float g) -> int16_t { return (int16_t)lroundf((g > 3 ? 3 : g < -3 ? -3 : g) * 1000); };
  lateral = mg(lat);
  longitudinal = mg(lon);
}

void Imu::describe(char* out, size_t n) {
  if (!address) {
    snprintf(out, n, "none");
    return;
  }
  int pct = weight >= kNeeded ? 100 : (int)(weight / kNeeded * 100);
  snprintf(out, n, "QMI8658 at 0x%02X, down %s, forward %s (%d%%)", address, hasUp ? "known" : "learning",
           forwardKnown() ? "known" : "learning", pct);
}

#endif
