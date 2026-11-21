#include "Screen.h"

#ifdef TRACKLAP_DISPLAY
#include <Preferences.h>
#include <math.h>
#include "Display.h"
#include "Imu.h"

namespace {

const uint8_t kButton = 9;         // BOOT, on every ESP32-C6 board
const float kAlong = 0.35f;        // g along the screen before its direction counts: 20° from flat
const float kClear = 0.7f;         // within 45° of the right way up, or of upside down
const uint32_t kLearnAfter = 2000;  // ms at rest before the first position is taken as the right one
const uint32_t kTurnAfter = 400;    // ms the other way up before the picture turns
const uint32_t kTeachFor = 15000;   // ms after a flip by hand in which the next rest teaches

Preferences store;
bool flipped = false;
// Where gravity pulls along the screen while the picture as built reads right: a unit vector in
// the chip's own axes, 0, 0 until it is learnt.
float downX = 0, downY = 0;
uint32_t teachUntil = 0;  // after a flip by hand: the next rest says that picture is the right one
uint32_t since = 0;       // since when the board has been in a position that asks for a change

bool learnt() { return downX != 0 || downY != 0; }

void save() {
  store.putBool("flip", flipped);
  float d[2] = {downX, downY};
  store.putBytes("down", d, sizeof d);
}

void set(bool on, const char* why) {
  flipped = on;
  Display::flip(on);
  save();
  Serial.printf("Screen %s (%s)\n", on ? "upside down" : "as built", why);
}

// Where gravity pulls along the screen, as a unit vector: false lying flat, on the move, shaken or
// without an accelerometer.
bool down(const Fix& last, bool fresh, float& x, float& y) {
  float z;
  if (!Imu::atRest(x, y, z)) return false;
  if (fresh && last.valid && last.speed > 100) return false;
  float l = sqrtf(x * x + y * y);
  if (l < kAlong) return false;
  x /= l;
  y /= l;
  return true;
}

// The picture as it is now reads right with gravity this way.
void learn(float x, float y) {
  downX = flipped ? -x : x;
  downY = flipped ? -y : y;
  save();
  Serial.println("Screen: right way up learnt");
}

}  // namespace

void Screen::begin() {
  pinMode(kButton, INPUT_PULLUP);
  store.begin("screen", false);
  flipped = store.isKey("flip") && store.getBool("flip", false);
  float d[2];
  if (store.isKey("down") && store.getBytes("down", d, sizeof d) == sizeof d) {
    float l = sqrtf(d[0] * d[0] + d[1] * d[1]);
    if (l > 0.5f && l < 1.5f) {
      downX = d[0] / l;
      downY = d[1] / l;
    }
  }
  Display::begin(flipped);
}

void Screen::flip() {
  set(!flipped, "by hand");
  teachUntil = millis() + kTeachFor;
  since = 0;
}

void Screen::poll(const Fix& last, bool fresh) {
  static uint32_t checked = 0, changedAt = 0;
  static bool pressed = false;
  uint32_t now = millis();
  if (now - checked < 50) return;
  checked = now;

  bool low = digitalRead(kButton) == LOW;
  if (low != pressed && now - changedAt > 60) {
    pressed = low;
    changedAt = now;
    if (low) flip();
  }

  float x, y;
  if (!down(last, fresh, x, y)) {
    since = 0;
    return;
  }
  if (teachUntil) {
    bool inTime = (int32_t)(teachUntil - now) > 0;
    teachUntil = 0;
    if (inTime) {
      learn(x, y);
      return;
    }
  }
  if (!learnt()) {
    if (!since) since = now;
    if (now - since >= kLearnAfter) {
      learn(x, y);
      since = 0;
    }
    return;
  }
  float d = x * downX + y * downY;  // 1 the right way up for the picture as built, -1 upside down
  bool want = d < -kClear ? true : d > kClear ? false : flipped;
  if (want == flipped) {
    since = 0;
    return;
  }
  if (!since) since = now;
  if (now - since < kTurnAfter) return;
  since = 0;
  set(want, "by itself");
}

void Screen::describe(char* out, size_t n) {
  const char* how = !Imu::model()[0] ? "BOOT turns it" : learnt() ? "right way up learnt" : "learning the right way up";
  snprintf(out, n, "%s, %s", flipped ? "upside down" : "as built", how);
}

#endif
