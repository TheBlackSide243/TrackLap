// TrackLap firmware: reads a GPS module and sends every fix to the TrackLap app over Bluetooth LE
// (protocol v1, see README), and times laps itself on the track the app sends, with the delta
// against the best lap at every line. Runs on every ESP32 with Bluetooth LE: ESP32, ESP32-S3, C3,
// C5, C6 and H2; on the Waveshare ESP32-C6-LCD-1.47 it also drives the screen as a dashboard.
//
// USB serial at 115200: "pins <rx> <tx>" moves the GPS to other pins, "pins default" puts them
// back, "info" prints the state.

#include <Preferences.h>
#include <driver/gpio.h>
#include <esp_mac.h>
#include "Board.h"
#include "Ble.h"
#include "Display.h"
#include "Gps.h"
#include "Laps.h"

#define FW_VERSION "0.1.0"

static Preferences prefs;
static Gps gps;
static Laps laps;
static char deviceName[16];
static int gpsRx = GPS_RX_DEFAULT;
static int gpsTx = GPS_TX_DEFAULT;
static Fix lastFix;
static uint32_t lastFixAt = 0;
static uint32_t lastBeat = 0;
static const char* infoModel = nullptr;
static uint8_t infoRate = 0;

static bool validPins(int rx, int tx) {
  return rx != tx && GPIO_IS_VALID_GPIO(rx) && GPIO_IS_VALID_OUTPUT_GPIO(tx);
}

// Saved in flash, then a restart: the UART and the GPS search start again on the new pins.
static void setPins(int rx, int tx) {
  if (!validPins(rx, tx)) {
    Serial.printf("GPIO %d/%d cannot be used for the GPS on the %s\n", rx, tx, CHIP_NAME);
    return;
  }
  prefs.putChar("rx", rx);
  prefs.putChar("tx", tx);
  Serial.printf("GPS on RX %d, TX %d: restarting\n", rx, tx);
  delay(200);
  ESP.restart();
}

static void publishInfo() {
  infoModel = gps.model();
  infoRate = gps.rate();
  char json[224];
  snprintf(json, sizeof json,
           "{\"fw\":\"%s\",\"chip\":\"%s\",\"board\":\"%s\",\"gps\":\"%s\",\"hz\":%u,\"rx\":%d,\"tx\":%d,"
           "\"lines\":%u,\"name\":\"%s\"}",
           FW_VERSION, CHIP_NAME, BOARD_NAME, infoModel, infoRate, gpsRx, gpsTx, laps.lines(), deviceName);
  Ble::setInfo(json);
  Serial.println(json);
}

// The app sends the track at every connection: the same one again changes nothing, so a lap in
// progress goes on after a reconnect. A new one forgets the best lap, which was for the old one.
static void setTrack(const uint8_t* buf, size_t len) {
  uint8_t old[200];
  bool same = prefs.isKey("track") && prefs.getBytes("track", old, sizeof old) == len && !memcmp(old, buf, len);
  if (same && laps.lines()) return;
  if (!laps.setTrack(buf, len)) return;
  prefs.putBytes("track", buf, len);
  laps.setBest(Laps::Best());
  prefs.remove("best");
  Serial.printf("New track with %u lines\n", laps.lines());
  publishInfo();
}

// CONTROL: 0x01 resets the session; 0x02 rx tx moves the GPS (0xFF 0xFF = the chip's defaults).
static void handleControl(const uint8_t* b, size_t len) {
  if (len >= 1 && b[0] == 0x01) {
    laps.reset();
    Serial.println("Session reset");
  } else if (len >= 3 && b[0] == 0x02) {
    if (b[1] == 0xFF && b[2] == 0xFF) setPins(GPS_RX_DEFAULT, GPS_TX_DEFAULT);
    else setPins(b[1], b[2]);
  }
}

static void readSerial() {
  static char line[32];
  static uint8_t pos = 0;
  while (Serial.available()) {
    char c = Serial.read();
    if (c != '\n' && c != '\r') {
      if (pos < sizeof line - 1) line[pos++] = c;
      continue;
    }
    line[pos] = 0;
    pos = 0;
    int rx, tx;
    if (sscanf(line, "pins %d %d", &rx, &tx) == 2) setPins(rx, tx);
    else if (!strcmp(line, "pins default")) setPins(GPS_RX_DEFAULT, GPS_TX_DEFAULT);
    else if (line[0]) {
      publishInfo();
      Serial.println("Commands: pins <rx> <tx> | pins default | info");
    }
  }
}

// The dev board's RGB LED, where it has one: red no GPS, amber no fix, green fix; blinking until
// the app connects.
static void showStatus() {
#ifdef RGB_BUILTIN
  static uint32_t last = 0;
  uint32_t now = millis();
  if (now - last < 100) return;
  last = now;
  bool data = now - lastFixAt < 1500;
  bool fix = data && lastFix.valid;
  bool on = Ble::connected() || (now / 500) % 2;
  uint8_t r = fix ? 0 : 24, g = fix ? 24 : data ? 8 : 0;
  rgbLedWrite(RGB_BUILTIN, on ? r : 0, on ? g : 0, 0);
#endif
}

static void showDashboard(uint32_t now) {
  DashState d;
  d.gpsData = now - lastFixAt < 1500;
  d.fix = d.gpsData && lastFix.valid;
  d.sats = lastFix.sats;
  d.rate = gps.rate();
  d.speed = lastFix.speed;
  d.connected = Ble::connected();
  d.hasTrack = laps.lines() > 0;
  d.running = laps.running();
  // Between fixes the clock runs on from the last one, for a second at most.
  uint32_t since = now - lastFixAt;
  d.elapsed = laps.sinceStart() + (since < 1000 ? since : 1000) / 1000.0;
  d.lap = laps.lap();
  d.best = laps.best().lap;
  d.last = laps.lastLap();
  d.gpsRx = gpsRx;
  d.gpsTx = gpsTx;
  Display::show(d);
}

void setup() {
  Serial.begin(115200);
  prefs.begin("tracklap", false);
  int rx = prefs.getChar("rx", GPS_RX_DEFAULT);
  int tx = prefs.getChar("tx", GPS_TX_DEFAULT);
  if (validPins(rx, tx)) {
    gpsRx = rx;
    gpsTx = tx;
  }
  if (prefs.isKey("track")) {
    uint8_t buf[200];
    size_t len = prefs.getBytes("track", buf, sizeof buf);
    laps.setTrack(buf, len);
  }
  Laps::Best best;
  if (prefs.isKey("best") && prefs.getBytes("best", &best, sizeof best) == sizeof best) laps.setBest(best);

  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_BT);
  snprintf(deviceName, sizeof deviceName, "TrackLap-%02X%02X", mac[4], mac[5]);
  Display::begin();
  Ble::begin(deviceName);
  gps.begin(gpsRx, gpsTx);
  Serial.printf("%s %s on %s, GPS on RX %d, TX %d\n", deviceName, FW_VERSION, BOARD_NAME, gpsRx, gpsTx);
  publishInfo();
}

void loop() {
  Fix f;
  while (gps.poll(f)) {
    lastFix = f;
    lastFixAt = millis();
    Ble::sendFix(f, gps.rate());
    LapEvent events[2];
    uint8_t n = laps.feed(f, events);
    for (uint8_t i = 0; i < n; i++) {
      const LapEvent& e = events[i];
      Ble::sendLap(e);
      Display::event(e);
      Serial.printf("%s %u: %lu ms", e.type == 1 ? "Lap" : "Sector", e.type == 1 ? e.lap : e.sector + 1, (unsigned long)e.ms);
      if (e.delta != kNoDelta) Serial.printf(", %+ld ms", (long)e.delta);
      Serial.println(e.best ? ", best lap" : "");
    }
    if (laps.takeNewBest()) prefs.putBytes("best", &laps.best(), sizeof(Laps::Best));
  }

  // Nothing from the GPS: an empty fix every second, so the app shows it as missing.
  uint32_t now = millis();
  if (now - lastFixAt > 1500 && now - lastBeat >= 1000) {
    Ble::sendFix(Fix(), 0);
    lastBeat = now;
  }

  uint8_t buf[200];
  size_t len;
  if (Ble::takeTrack(buf, len)) setTrack(buf, len);
  if (Ble::takeControl(buf, len)) handleControl(buf, len);
  if (gps.model() != infoModel || abs((int)gps.rate() - (int)infoRate) >= 2) publishInfo();

  readSerial();
  showStatus();
  showDashboard(now);
  delay(2);
}
