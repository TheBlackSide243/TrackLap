#pragma once
#include <Arduino.h>

/// One GPS fix, in the units of the BLE FIX packet.
struct Fix {
  bool valid = false;    // 2D or 3D fix
  bool fix3d = false;
  uint8_t sats = 0;
  uint32_t itow = 0;     // ms since the start of the GPS week
  int32_t lat = 0;       // 1e-7 degrees
  int32_t lon = 0;
  uint32_t speed = 0;    // cm/s
  uint32_t heading = 0;  // 0.01 degrees
  int32_t alt = INT32_MIN;  // mm above sea level, INT32_MIN without a 3D fix
};

/// A GPS module on a UART, read by a task of its own. u-blox modules (M7, M8, M9, M10…) are
/// switched to 115200 baud, 10 Hz and UBX NAV-PVT; any other module is read as NMEA at whatever
/// speed it talks. After 3 s of silence it looks for the module again, so it can be plugged in later.
class Gps {
 public:
  void begin(int rx, int tx);
  /// The next fix that has arrived, if any.
  bool poll(Fix& out);
  /// "u-blox M8", "NMEA"…, empty while no module answers.
  const char* model() const;
  /// Fixes in the last second.
  uint8_t rate() const { return rate_; }

 private:
  enum Model : uint8_t { None, Nmea, Ublox, UbloxM7, UbloxM8, UbloxM9, UbloxM10 };

  static void task(void* self);
  void run();
  Model detect();
  void configureUblox();
  bool listen(uint32_t ms);
  void sendUbx(uint8_t cls, uint8_t id, const uint8_t* payload, uint16_t len);
  void sendValset(const uint8_t* items, uint16_t len);
  bool feed(uint8_t c, Fix& out);
  bool feedUbx(uint8_t c, Fix& out);
  bool feedNmea(uint8_t c, Fix& out);
  bool parseNmea(Fix& out);

  HardwareSerial& serial_ = Serial1;
  QueueHandle_t queue_ = nullptr;
  volatile Model model_ = None;
  volatile uint8_t rate_ = 0;
  Model ubloxModel_ = Ublox;
  bool sawUbx_ = false;
  bool sawNmea_ = false;

  uint8_t ubxState_ = 0;
  uint8_t ubxClass_ = 0;
  uint8_t ubxId_ = 0;
  uint16_t ubxLen_ = 0;
  uint16_t ubxPos_ = 0;
  uint8_t ubxCheckA_ = 0;
  uint8_t ubx_[256];

  char line_[100];
  uint8_t linePos_ = 0;
  uint8_t nmeaSats_ = 0;
  bool nmea3d_ = false;
  int32_t nmeaAlt_ = INT32_MIN;
};
