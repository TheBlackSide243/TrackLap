#include "Gps.h"

namespace {

const uint32_t kBauds[] = {9600, 38400, 57600, 115200, 230400};

// CFG-PRT: UART1 at 115200 baud 8N1, UBX and NMEA in, UBX out.
const uint8_t kCfgPrt[] = {
    1, 0, 0, 0,
    0xD0, 0x08, 0, 0,
    0x00, 0xC2, 0x01, 0x00,
    0x03, 0x00,
    0x01, 0x00,
    0, 0, 0, 0,
};

// CFG-VALSET items (key, value) for M10 and later, which dropped the messages above.
const uint8_t kValsetBaud[] = {
    0x01, 0x00, 0x52, 0x40, 0x00, 0xC2, 0x01, 0x00,  // CFG-UART1-BAUDRATE = 115200
};
const uint8_t kValsetConfig[] = {
    0x01, 0x00, 0x21, 0x30, 100, 0,  // CFG-RATE-MEAS = 100 ms
    0x07, 0x00, 0x91, 0x20, 1,       // CFG-MSGOUT-UBX_NAV_PVT_UART1 = every fix
    0x02, 0x00, 0x74, 0x10, 0,       // CFG-UART1OUTPROT-NMEA = off
    0x21, 0x00, 0x11, 0x20, 4,       // CFG-NAVSPG-DYNMODEL = automotive
};

uint16_t u16(const uint8_t* p) { return p[0] | (uint16_t)p[1] << 8; }
uint32_t u32(const uint8_t* p) { return u16(p) | (uint32_t)u16(p + 2) << 16; }

int32_t nmeaCoord(const char* s, bool negative) {
  if (!*s) return 0;
  double v = atof(s);  // ddmm.mmmm or dddmm.mmmm
  int deg = (int)(v / 100);
  double d = deg + (v - deg * 100) / 60.0;
  return (int32_t)lround((negative ? -d : d) * 1e7);
}

int digits(const char* s) { return (s[0] - '0') * 10 + (s[1] - '0'); }

// GPS time of week in ms from the UTC time and date of an RMC sentence; GPS time runs 18 s ahead.
uint32_t nmeaTow(const char* time, const char* date) {
  if (strlen(time) < 6 || strlen(date) < 6) return 0;
  int day = digits(date), month = digits(date + 2), year = 2000 + digits(date + 4);
  if (month < 1 || month > 12) return 0;
  static const int k[] = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4};
  int y = year - (month < 3);
  int weekday = (y + y / 4 - y / 100 + y / 400 + k[month - 1] + day) % 7;  // 0 = Sunday
  double s = weekday * 86400.0 + digits(time) * 3600 + digits(time + 2) * 60 + atof(time + 4) + 18;
  return (uint32_t)lround(fmod(s, 604800.0) * 1000);
}

}  // namespace

void Gps::begin(int rx, int tx) {
  serial_.setRxBufferSize(2048);
  serial_.begin(9600, SERIAL_8N1, rx, tx);
  queue_ = xQueueCreate(8, sizeof(Fix));
  xTaskCreate(task, "gps", 4096, this, 2, nullptr);
}

bool Gps::poll(Fix& out) { return queue_ && xQueueReceive(queue_, &out, 0) == pdTRUE; }

const char* Gps::model() const {
  static const char* names[] = {"", "NMEA", "u-blox", "u-blox M7", "u-blox M8", "u-blox M9", "u-blox M10"};
  return names[model_];
}

void Gps::task(void* self) {
  for (;;) static_cast<Gps*>(self)->run();
}

void Gps::run() {
  Model found = detect();
  if (found == None) return;
  model_ = found;
  Fix fix;
  uint32_t last = millis(), second = millis();
  uint8_t count = 0;
  while (millis() - last < 3000) {
    while (serial_.available()) {
      last = millis();
      if (feed(serial_.read(), fix)) {
        xQueueSend(queue_, &fix, 0);
        count++;
      }
    }
    if (millis() - second >= 1000) {
      rate_ = count;
      count = 0;
      second += 1000;
    }
    vTaskDelay(pdMS_TO_TICKS(5));
  }
  model_ = None;
  rate_ = 0;
}

Gps::Model Gps::detect() {
  // u-blox: at whatever speed it is, ask it to move to 115200 with UBX output.
  for (uint32_t baud : kBauds) {
    serial_.updateBaudRate(baud);
    sendUbx(0x06, 0x00, kCfgPrt, sizeof kCfgPrt);
    sendValset(kValsetBaud, sizeof kValsetBaud);
    serial_.flush();
    delay(30);
  }
  serial_.updateBaudRate(115200);
  delay(100);
  while (serial_.available()) serial_.read();
  ubloxModel_ = Ublox;
  configureUblox();
  if (listen(1500)) return sawUbx_ ? ubloxModel_ : Nmea;
  // Anything else talks NMEA: find its speed.
  for (uint32_t baud : kBauds) {
    serial_.updateBaudRate(baud);
    if (listen(1200)) return sawUbx_ ? ubloxModel_ : Nmea;
  }
  return None;
}

void Gps::configureUblox() {
  static const uint8_t rate[] = {100, 0, 1, 0, 1, 0};  // CFG-RATE: 100 ms, every cycle, GPS time
  static const uint8_t pvt[] = {0x01, 0x07, 1};        // CFG-MSG: NAV-PVT on every fix
  uint8_t nav5[36] = {0x01, 0x00, 4};                  // CFG-NAV5: dynamic model only, automotive
  sendUbx(0x06, 0x08, rate, sizeof rate);
  sendUbx(0x06, 0x01, pvt, sizeof pvt);
  sendUbx(0x06, 0x24, nav5, sizeof nav5);
  sendValset(kValsetConfig, sizeof kValsetConfig);
  sendUbx(0x0A, 0x04, nullptr, 0);  // MON-VER, to tell an M8 from an M10
  serial_.flush();
}

// Reads for up to `ms`, stopping as soon as the module is identified.
bool Gps::listen(uint32_t ms) {
  sawUbx_ = sawNmea_ = false;
  Fix ignored;
  uint32_t start = millis();
  while (millis() - start < ms) {
    while (serial_.available()) feed(serial_.read(), ignored);
    if (sawNmea_ || (sawUbx_ && ubloxModel_ != Ublox)) return true;
    delay(5);
  }
  return sawUbx_ || sawNmea_;
}

void Gps::sendUbx(uint8_t cls, uint8_t id, const uint8_t* payload, uint16_t len) {
  uint8_t head[6] = {0xB5, 0x62, cls, id, (uint8_t)len, (uint8_t)(len >> 8)};
  uint8_t a = 0, b = 0;
  for (int i = 2; i < 6; i++) {
    a += head[i];
    b += a;
  }
  for (uint16_t i = 0; i < len; i++) {
    a += payload[i];
    b += a;
  }
  serial_.write(head, sizeof head);
  if (len) serial_.write(payload, len);
  serial_.write(a);
  serial_.write(b);
}

void Gps::sendValset(const uint8_t* items, uint16_t len) {
  uint8_t payload[64] = {0, 0x01, 0, 0};  // version 0, RAM layer only: it is sent again at every start
  memcpy(payload + 4, items, len);
  sendUbx(0x06, 0x8A, payload, len + 4);
}

bool Gps::feed(uint8_t c, Fix& out) {
  Fix f;
  if (feedUbx(c, f) && model_ != Nmea) {
    out = f;
    return true;
  }
  if (feedNmea(c, f) && (model_ == None || model_ == Nmea)) {
    out = f;
    return true;
  }
  return false;
}

// UBX frame: B5 62, class, id, length (u16), payload, two checksum bytes. True on a NAV-PVT.
bool Gps::feedUbx(uint8_t c, Fix& out) {
  switch (ubxState_) {
    case 0:
      if (c == 0xB5) ubxState_ = 1;
      return false;
    case 1:
      ubxState_ = c == 0x62 ? 2 : 0;
      return false;
    case 2:
      ubxClass_ = c;
      ubxState_ = 3;
      return false;
    case 3:
      ubxId_ = c;
      ubxState_ = 4;
      return false;
    case 4:
      ubxLen_ = c;
      ubxState_ = 5;
      return false;
    case 5:
      ubxLen_ |= (uint16_t)c << 8;
      ubxPos_ = 0;
      ubxState_ = ubxLen_ > sizeof ubx_ ? 0 : ubxLen_ ? 6 : 7;
      return false;
    case 6:
      ubx_[ubxPos_++] = c;
      if (ubxPos_ == ubxLen_) ubxState_ = 7;
      return false;
    case 7:
      ubxCheckA_ = c;
      ubxState_ = 8;
      return false;
  }
  ubxState_ = 0;
  uint8_t head[4] = {ubxClass_, ubxId_, (uint8_t)ubxLen_, (uint8_t)(ubxLen_ >> 8)};
  uint8_t a = 0, b = 0;
  for (uint8_t h : head) {
    a += h;
    b += a;
  }
  for (uint16_t i = 0; i < ubxLen_; i++) {
    a += ubx_[i];
    b += a;
  }
  if (a != ubxCheckA_ || b != c) return false;
  sawUbx_ = true;

  if (ubxClass_ == 0x0A && ubxId_ == 0x04 && ubxLen_ >= 40) {
    // MON-VER: the hardware version is 10 characters after the 30 of the software version.
    const char* hw = (const char*)ubx_ + 30;
    if (!strncmp(hw, "00070000", 8)) ubloxModel_ = UbloxM7;
    else if (!strncmp(hw, "00080000", 8)) ubloxModel_ = UbloxM8;
    else if (!strncmp(hw, "00190000", 8)) ubloxModel_ = UbloxM9;
    else if (!strncmp(hw, "000A0000", 8)) ubloxModel_ = UbloxM10;
    if (model_ == Ublox) model_ = ubloxModel_;
    return false;
  }
  if (ubxClass_ != 0x01 || ubxId_ != 0x07 || ubxLen_ < 92) return false;

  // NAV-PVT
  const uint8_t* p = ubx_;
  uint8_t fixType = p[20];
  out = Fix();
  out.valid = (p[21] & 1) && fixType >= 2 && fixType <= 4;
  out.fix3d = out.valid && fixType != 2;
  out.sats = p[23];
  out.itow = u32(p);
  out.lon = (int32_t)u32(p + 24);
  out.lat = (int32_t)u32(p + 28);
  int32_t speed = (int32_t)u32(p + 60);  // mm/s
  int32_t heading = (int32_t)u32(p + 64);  // 1e-5 degrees
  out.speed = speed > 0 ? speed / 10 : 0;
  out.heading = heading > 0 ? heading / 1000 : 0;
  if (out.fix3d) out.alt = (int32_t)u32(p + 36);  // hMSL, mm
  return true;
}

bool Gps::feedNmea(uint8_t c, Fix& out) {
  if (c == '$') {
    linePos_ = 0;
    line_[linePos_++] = c;
    return false;
  }
  if (linePos_ == 0) return false;
  if (c == '\r' || c == '\n') {
    line_[linePos_] = 0;
    bool fix = linePos_ > 6 && parseNmea(out);
    linePos_ = 0;
    return fix;
  }
  if (linePos_ < sizeof line_ - 1) line_[linePos_++] = c;
  else linePos_ = 0;
  return false;
}

// True on an RMC sentence; GGA and GSA only fill in the satellites, the altitude and the 3D flag.
bool Gps::parseNmea(Fix& out) {
  char* star = strchr(line_, '*');
  if (!star || strlen(star) < 3) return false;
  uint8_t sum = 0;
  for (char* p = line_ + 1; p < star; p++) sum ^= (uint8_t)*p;
  if (sum != strtoul(star + 1, nullptr, 16)) return false;
  *star = 0;
  sawNmea_ = true;

  char* f[20];
  int n = 0;
  for (char* p = line_ + 1; n < 20;) {
    f[n++] = p;
    p = strchr(p, ',');
    if (!p) break;
    *p++ = 0;
  }
  if (strlen(f[0]) != 5) return false;
  const char* type = f[0] + 2;  // after the talker: GPRMC, GNRMC…
  if (!strcmp(type, "GGA") && n > 7) {
    nmeaSats_ = atoi(f[7]);
    nmeaAlt_ = n > 9 && f[9][0] ? (int32_t)lround(atof(f[9]) * 1000) : INT32_MIN;
    return false;
  }
  if (!strcmp(type, "GSA") && n > 2) {
    nmea3d_ = f[2][0] == '3';
    return false;
  }
  if (strcmp(type, "RMC") || n < 10) return false;
  out = Fix();
  out.valid = f[2][0] == 'A';
  out.fix3d = out.valid && nmea3d_;
  out.sats = nmeaSats_;
  if (out.fix3d) out.alt = nmeaAlt_;
  out.lat = nmeaCoord(f[3], f[4][0] == 'S');
  out.lon = nmeaCoord(f[5], f[6][0] == 'W');
  out.speed = (uint32_t)(atof(f[7]) * 51.4444 + 0.5);  // knots
  out.heading = (uint32_t)(atof(f[8]) * 100 + 0.5);
  out.itow = nmeaTow(f[1], f[9]);
  return true;
}
