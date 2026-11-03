#include "Display.h"

#ifdef TRACKLAP_LCD147
#pragma message "TrackLap: dashboard for the Waveshare ESP32-C6-LCD-1.47"
#include <Arduino_GFX_Library.h>

namespace {

// Waveshare ESP32-C6-LCD-1.47: ST7789 IPS panel, 172 × 320, used in landscape.
const int8_t kDC = 15, kCS = 14, kSCK = 7, kMOSI = 6, kRST = 21, kBacklight = 22;
const int16_t W = 320, H = 172;
const int16_t kTop = 26;       // status bar
const int16_t kMainY = 30;     // lap time or speed
const int16_t kBottomY = 120;  // best and last lap, or the delta just measured

constexpr uint16_t rgb(uint8_t r, uint8_t g, uint8_t b) { return (r & 0xF8) << 8 | (g & 0xFC) << 3 | b >> 3; }

// The app's colours.
const uint16_t kBg = rgb(0, 0, 0);
const uint16_t kPanel = rgb(28, 28, 32);
const uint16_t kText = rgb(242, 242, 246);
const uint16_t kSub = rgb(150, 150, 162);
const uint16_t kAccent = rgb(34, 211, 238);
const uint16_t kGood = rgb(74, 214, 124);
const uint16_t kBad = rgb(240, 96, 80);
const uint16_t kPurple = rgb(176, 102, 255);
const uint16_t kYellow = rgb(250, 204, 21);

Arduino_GFX* gfx = nullptr;

void text(int16_t x, int16_t y, uint8_t size, uint16_t color, uint16_t bg, const char* s) {
  gfx->setTextSize(size);
  gfx->setTextColor(color, bg);
  gfx->setCursor(x, y);
  gfx->print(s);
}

void centered(int16_t y, uint8_t size, uint16_t color, const char* s) {
  text((W - (int16_t)strlen(s) * 6 * size) / 2, y, size, color, kBg, s);
}

// 83456 ms → "1:23.4", or "1:23.45" with hundredths; truncated like a stopwatch.
void formatTime(char* out, size_t n, uint32_t ms, bool hundredths) {
  unsigned long v = ms / (hundredths ? 10 : 100);
  unsigned long frac = v % (hundredths ? 100 : 10), s = v / (hundredths ? 100 : 10);
  if (s >= 60) snprintf(out, n, hundredths ? "%lu:%02lu.%02lu" : "%lu:%02lu.%lu", s / 60, s % 60, frac);
  else snprintf(out, n, hundredths ? "%lu.%02lu" : "%lu.%lu", s, frac);
}

uint16_t gradeColor(Grade g) {
  switch (g) {
    case Grade::Fastest: return kPurple;
    case Grade::Better: return kGood;
    case Grade::Worse: return kBad;
    default: return kText;
  }
}

void formatDelta(char* out, size_t n, int32_t ms) {
  long a = labs(ms) > 99990 ? 99990 : labs(ms);
  snprintf(out, n, "%c%ld.%02ld", ms < 0 ? '-' : '+', a / 1000, a % 1000 / 10);
}

/// A line of seven-segment digits drawn with rectangles: sharp at any size, and a digit that
/// changes is redrawn in place (its unlit segments in the background colour), so nothing flickers.
class SegText {
 public:
  SegText(int16_t y, int16_t h) : y_(y), h_(h) {}

  void reset() {
    prev_[0] = 0;
    drawnW_ = 0;
  }

  void show(const char* s, uint16_t color) {
    size_t n = strlen(s);
    if (n >= sizeof prev_) return;
    bool full = color != color_ || n != strlen(prev_);
    for (size_t i = 0; i < n && !full; i++) full = width(s[i]) != width(prev_[i]);
    if (full) {
      int16_t w = 0;
      for (size_t i = 0; i < n; i++) w += width(s[i]) + (i ? gap() : 0);
      if (drawnW_) gfx->fillRect(x_, y_, drawnW_, h_, kBg);
      x_ = (W - w) / 2;
      drawnW_ = w;
    }
    int16_t x = x_;
    for (size_t i = 0; i < n; i++) {
      if (full || s[i] != prev_[i]) glyph(s[i], x, color);
      x += width(s[i]) + gap();
    }
    strcpy(prev_, s);
    color_ = color;
  }

 private:
  int16_t thick() const { return max<int16_t>(2, h_ / 9); }
  int16_t gap() const { return thick(); }
  int16_t width(char c) const { return c == ':' || c == '.' ? thick() * 2 : h_ / 2; }

  void glyph(char c, int16_t x, uint16_t color) {
    int16_t t = thick(), w = width(c), h = h_, y = y_;
    if (c == ':' || c == '.') {
      gfx->fillRect(x, y, w, h, kBg);
      int16_t s = t * 3 / 2, dx = x + (w - s) / 2;
      if (c == '.') {
        gfx->fillRect(dx, y + h - s, s, s, color);
      } else {
        gfx->fillRect(dx, y + h * 3 / 10 - s / 2, s, s, color);
        gfx->fillRect(dx, y + h * 7 / 10 - s / 2, s, s, color);
      }
      return;
    }
    static const uint8_t digits[] = {0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F};
    uint8_t m = c >= '0' && c <= '9' ? digits[c - '0'] : c == '-' || c == '+' ? 0x40 : 0;
    int16_t half = (h - 3 * t) / 2, low = y + (h + t) / 2;
    // The upright of a '+', cleared first so a digit's middle segment is drawn over it.
    int16_t barH = w - 2 * t, barX = x + (w - t) / 2, barY = y + (h - barH) / 2;
    gfx->fillRect(barX, barY, t, barH, kBg);
    const int16_t seg[7][4] = {
        {int16_t(x + t), y, int16_t(w - 2 * t), t},                       // a
        {int16_t(x + w - t), int16_t(y + t), t, half},                    // b
        {int16_t(x + w - t), low, t, half},                               // c
        {int16_t(x + t), int16_t(y + h - t), int16_t(w - 2 * t), t},      // d
        {x, low, t, half},                                                // e
        {x, int16_t(y + t), t, half},                                     // f
        {int16_t(x + t), int16_t(y + (h - t) / 2), int16_t(w - 2 * t), t},  // g
    };
    for (int i = 0; i < 7; i++) gfx->fillRect(seg[i][0], seg[i][1], seg[i][2], seg[i][3], (m >> i) & 1 ? color : kBg);
    if (c == '+') gfx->fillRect(barX, barY, t, barH, color);
  }

  int16_t y_, h_;
  int16_t x_ = 0, drawnW_ = 0;
  uint16_t color_ = 0;
  char prev_[12] = "";
};

enum Mode : uint8_t { None, Message, Speed, Time };

SegText big(kMainY + 6, 76);
SegText small(kBottomY + 6, 42);
Mode mainMode = None;
char mainKey[48] = "";
bool bottomEvent = false;
char infoKey[32] = "";
char topLeft[12] = "", topRight[16] = "";
int8_t topLink = -1;
uint32_t eventUntil = 0, lapUntil = 0, lastDraw = 0;
char lapText[12] = "";
uint16_t lapColor = 0;
uint16_t shownLap = 0;
// The place in the live group, in the status bar; a new one also takes the bottom line for 4 s,
// once the lap or sector shown there is done.
uint8_t groupPos = 0, groupCount = 0;
int32_t groupGap = kNoDelta;
bool groupPending = false;
char topGroup[8] = "-";
// The drag dashboard: the speed always, and at the bottom what the app's drag timer waits for, the
// time of the run in progress, or a result for 5 s.
bool dragMode = false;
uint8_t dragState = 0;
uint32_t dragStart = 0;
char dragKey[16] = "";

void clearMain() { gfx->fillRect(0, kMainY, W, kBottomY - kMainY, kBg); }
void clearBottom() { gfx->fillRect(0, kBottomY, W, H - kBottomY, kBg); }

void setMain(Mode m) {
  if (m == mainMode) return;
  clearMain();
  big.reset();
  mainKey[0] = 0;
  mainMode = m;
  if (m == Speed) text(W - 64, kMainY + 66, 2, kSub, kBg, "km/h");
}

void message(const char* title, const char* sub, uint16_t color) {
  setMain(Message);
  char key[sizeof mainKey];
  snprintf(key, sizeof key, "%s|%s", title, sub);
  if (!strcmp(key, mainKey)) return;
  strcpy(mainKey, key);
  clearMain();
  centered(kMainY + 14, 5, color, title);
  centered(kMainY + 66, 2, kSub, sub);
}

void topBar(const DashState& s, uint32_t now) {
  char left[sizeof topLeft], right[sizeof topRight];
  uint16_t lap = now < lapUntil ? shownLap : s.running ? s.lap : 0;
  if (dragMode) strcpy(left, "DRAG   ");
  else if (lap) snprintf(left, sizeof left, "LAP %-3u", lap);
  else strcpy(left, "LAP -  ");
  snprintf(right, sizeof right, "%2u SAT %2uHz", s.sats, s.rate);
  if (strcmp(left, topLeft)) text(10, 5, 2, kText, kPanel, strcpy(topLeft, left));
  if (strcmp(right, topRight)) text(W - 24 - 11 * 12, 5, 2, kSub, kPanel, strcpy(topRight, right));
  char place[sizeof topGroup];
  if (groupPos && !dragMode) snprintf(place, sizeof place, "P%u/%-2u", groupPos, groupCount);
  else strcpy(place, "      ");
  if (strcmp(place, topGroup)) text(100, 5, 2, kYellow, kPanel, strcpy(topGroup, place));
  if (topLink != s.connected) {
    topLink = s.connected;
    gfx->fillCircle(W - 12, kTop / 2, 5, s.connected ? kGood : kSub);
  }
}

void info(const DashState& s) {
  char best[12] = "--", last[12] = "--", key[sizeof infoKey];
  if (s.best) formatTime(best, sizeof best, s.best, true);
  if (s.last) formatTime(last, sizeof last, s.last, true);
  if (s.hasTrack) snprintf(key, sizeof key, "%s|%s", best, last);
  else strcpy(key, "-");
  if (!bottomEvent && !strcmp(key, infoKey)) return;
  bottomEvent = false;
  strcpy(infoKey, key);
  clearBottom();
  small.reset();
  if (!s.hasTrack) {
    centered(kBottomY + 18, 2, kSub, "SEND TRACK FROM THE APP");
    return;
  }
  text(12, kBottomY + 4, 2, kSub, kBg, "BEST");
  text(12, kBottomY + 24, 3, kPurple, kBg, best);
  text(172, kBottomY + 4, 2, kSub, kBg, "LAST");
  text(172, kBottomY + 24, 3, kText, kBg, last);
}

// "P2" and the gap to the driver ahead in red; when first, "P1" and the margin over the second in green.
void showGroup(uint32_t now) {
  clearBottom();
  small.reset();
  bottomEvent = true;
  eventUntil = now + 4000;
  char buf[12];
  snprintf(buf, sizeof buf, "P%u", groupPos);
  text(12, kBottomY + 14, 3, kYellow, kBg, buf);
  if (groupGap == kNoDelta) return;
  formatDelta(buf, sizeof buf, groupGap);
  small.show(buf, groupPos == 1 ? kGood : kBad);
}

// "STOP TO START", "READY" in green, or "GO" with the time since the launch.
void dragBottom(uint32_t now) {
  char key[sizeof dragKey], buf[12] = "";
  if (dragState == 2) {
    formatTime(buf, sizeof buf, now - dragStart, false);
    snprintf(key, sizeof key, "R%s", buf);
  } else {
    snprintf(key, sizeof key, "S%u", dragState);
  }
  if (!bottomEvent && !strcmp(key, dragKey)) return;
  bool redraw = bottomEvent || key[0] != dragKey[0] || dragState != 2;
  bottomEvent = false;
  strcpy(dragKey, key);
  if (redraw) {
    clearBottom();
    small.reset();
  }
  if (dragState == 2) {
    if (redraw) text(12, kBottomY + 14, 3, kAccent, kBg, "GO");
    small.show(buf, kText);
  } else if (dragState == 1) {
    centered(kBottomY + 14, 3, kGood, "READY");
  } else {
    centered(kBottomY + 18, 2, kSub, "STOP TO START");
  }
}

}  // namespace

void Display::drag(bool on, uint8_t state, uint32_t elapsed) {
  if (on != dragMode) {
    dragMode = on;
    // The whole bottom line, and the main one, are drawn again for the other dashboard.
    dragKey[0] = 0;
    infoKey[0] = 0;
    bottomEvent = true;
    eventUntil = lapUntil = 0;
  }
  dragState = state;
  dragStart = millis() - elapsed;
}

void Display::dragResult(const char* label, uint32_t value, bool distance, bool best) {
  if (!gfx) return;
  uint32_t now = millis();
  clearBottom();
  small.reset();
  bottomEvent = true;
  eventUntil = now + 5000;
  char buf[12];
  if (distance) snprintf(buf, sizeof buf, "%lu.%lu", (unsigned long)(value / 100), (unsigned long)(value % 100 / 10));
  else formatTime(buf, sizeof buf, value, true);
  text(12, kBottomY + 18, 2, best ? kPurple : kSub, kBg, label);
  small.show(buf, best ? kPurple : kText);
  text(W - 30, kBottomY + 30, 2, kSub, kBg, distance ? "m" : "s");
}

void Display::group(uint8_t position, uint8_t count, int32_t gap) {
  if (position == groupPos && count == groupCount && gap == groupGap) return;
  groupPending = position != 0 && (position != groupPos || gap != groupGap);
  groupPos = position;
  groupCount = count;
  groupGap = gap;
}

void Display::begin() {
  pinMode(kBacklight, OUTPUT);
  digitalWrite(kBacklight, HIGH);
  Arduino_DataBus* bus = new Arduino_HWSPI(kDC, kCS, kSCK, kMOSI);
  gfx = new Arduino_ST7789(bus, kRST, 1, true, 172, 320, 34, 0, 34, 0);
  if (!gfx->begin()) {
    gfx = nullptr;
    return;
  }
  gfx->fillScreen(kBg);
  gfx->fillRect(0, 0, W, kTop, kPanel);
  centered(kMainY + 24, 4, kAccent, "TRACKLAP");
}

void Display::show(const DashState& s) {
  if (!gfx) return;
  uint32_t now = millis();
  if (now - lastDraw < 50) return;
  lastDraw = now;
  topBar(s, now);

  char buf[32];
  if (!s.gpsData) {
    snprintf(buf, sizeof buf, "GPS ON RX %d  TX %d", s.gpsRx, s.gpsTx);
    message("NO GPS", buf, kYellow);
  } else if (!s.fix) {
    snprintf(buf, sizeof buf, "%u SATELLITES", s.sats);
    message("NO FIX", buf, kYellow);
  } else if (!dragMode && now < lapUntil) {
    // The lap just finished stays up for a few seconds.
    setMain(Time);
    big.show(lapText, lapColor);
  } else if (!dragMode && s.running) {
    setMain(Time);
    formatTime(buf, sizeof buf, (uint32_t)(s.elapsed * 1000), false);
    big.show(buf, kText);
  } else {
    setMain(Speed);
    snprintf(buf, sizeof buf, "%lu", (unsigned long)(s.speed * 36 / 1000));
    big.show(buf, kText);
  }
  if (dragMode) {
    if (now >= eventUntil) dragBottom(now);
  } else if (now >= eventUntil && groupPending && groupPos) {
    groupPending = false;
    showGroup(now);
  } else if (now >= eventUntil) {
    info(s);
  }
}

// A sector line: its delta against the best lap for 4 s, or the sector time while there is no best
// lap; purple when it is the fastest ever at that line, green ahead of the previous lap, red behind.
// The finish: the lap time for 5 s with its delta; purple for a best lap, green faster than the
// session's average, red slower.
void Display::event(const LapEvent& e) {
  if (!gfx || dragMode) return;
  uint32_t now = millis();
  clearBottom();
  small.reset();
  bottomEvent = true;
  uint16_t color = gradeColor(e.grade);
  char buf[12];
  if (e.type == 1) {
    formatTime(lapText, sizeof lapText, e.ms, true);
    lapColor = color;
    shownLap = e.lap;
    lapUntil = eventUntil = now + 5000;
    if (e.delta == kNoDelta) {
      centered(kBottomY + 14, 3, kPurple, "BEST LAP");
      return;
    }
    text(12, kBottomY + 14, 3, e.best ? kPurple : kSub, kBg, e.best ? "BEST" : "LAP");
    formatDelta(buf, sizeof buf, e.delta);
    small.show(buf, color);
  } else {
    eventUntil = now + 4000;
    snprintf(buf, sizeof buf, "S%u", e.sector + 1);
    text(12, kBottomY + 14, 3, kSub, kBg, buf);
    if (e.delta == kNoDelta) formatTime(buf, sizeof buf, e.ms, true);
    else formatDelta(buf, sizeof buf, e.delta);
    small.show(buf, color);
  }
}

#endif
