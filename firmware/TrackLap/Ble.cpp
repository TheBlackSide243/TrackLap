#include "Ble.h"
#include <NimBLEDevice.h>

namespace {

const char* kService = "7A1C0000-3F4B-4C8E-9D2A-6B1E5F0A9C10";
const char* kFix = "7A1C0001-3F4B-4C8E-9D2A-6B1E5F0A9C10";
const char* kLap = "7A1C0002-3F4B-4C8E-9D2A-6B1E5F0A9C10";
const char* kTrack = "7A1C0003-3F4B-4C8E-9D2A-6B1E5F0A9C10";
const char* kControl = "7A1C0004-3F4B-4C8E-9D2A-6B1E5F0A9C10";
const char* kInfo = "7A1C0005-3F4B-4C8E-9D2A-6B1E5F0A9C10";

NimBLEServer* server = nullptr;
NimBLECharacteristic* fixChr = nullptr;
NimBLECharacteristic* lapChr = nullptr;
NimBLECharacteristic* trackChr = nullptr;
NimBLECharacteristic* controlChr = nullptr;
NimBLECharacteristic* infoChr = nullptr;

// The writes waiting for the main loop, oldest first: only the newest TRACK counts, while the last
// few CONTROL commands all do (the app sends the friend's lap and the group place one after the other).
struct Packet {
  uint8_t data[200];
  size_t len = 0;
};
struct Inbox {
  static const uint8_t kSize = 4;
  Packet slots[kSize];
  uint8_t head = 0, count = 0, capacity = kSize;
};
Inbox trackBox, controlBox;
portMUX_TYPE lock = portMUX_INITIALIZER_UNLOCKED;

void put(Inbox& box, const NimBLEAttValue& v) {
  portENTER_CRITICAL(&lock);
  if (box.count == box.capacity) {  // full: the oldest goes
    box.head = (box.head + 1) % Inbox::kSize;
    box.count--;
  }
  Packet& p = box.slots[(box.head + box.count) % Inbox::kSize];
  p.len = v.size() < sizeof p.data ? v.size() : sizeof p.data;
  memcpy(p.data, v.data(), p.len);
  box.count++;
  portEXIT_CRITICAL(&lock);
}

bool take(Inbox& box, uint8_t* buf, size_t& len) {
  bool got = false;
  portENTER_CRITICAL(&lock);
  if (box.count) {
    const Packet& p = box.slots[box.head];
    memcpy(buf, p.data, p.len);
    len = p.len;
    box.head = (box.head + 1) % Inbox::kSize;
    box.count--;
    got = true;
  }
  portEXIT_CRITICAL(&lock);
  return got;
}

void put16(uint8_t* p, uint16_t v) {
  p[0] = v;
  p[1] = v >> 8;
}

void put32(uint8_t* p, uint32_t v) {
  put16(p, v);
  put16(p + 2, v >> 16);
}

class WriteCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo& info) override {
    put(c == trackChr ? trackBox : controlBox, c->getValue());
  }
};

class ServerCallbacks : public NimBLEServerCallbacks {
  void onDisconnect(NimBLEServer* s, NimBLEConnInfo& info, int reason) override {
    NimBLEDevice::startAdvertising();
  }
};

}  // namespace

void Ble::begin(const char* name) {
  trackBox.capacity = 1;
  NimBLEDevice::init(name);
  server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  NimBLEService* service = server->createService(kService);
  fixChr = service->createCharacteristic(kFix, NIMBLE_PROPERTY::NOTIFY);
  lapChr = service->createCharacteristic(kLap, NIMBLE_PROPERTY::NOTIFY);
  trackChr = service->createCharacteristic(kTrack, NIMBLE_PROPERTY::WRITE);
  controlChr = service->createCharacteristic(kControl, NIMBLE_PROPERTY::WRITE);
  infoChr = service->createCharacteristic(kInfo, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  auto* writes = new WriteCallbacks();
  trackChr->setCallbacks(writes);
  controlChr->setCallbacks(writes);

  // The service in the advertisement, since the app scans for it; the name in the scan response.
  NimBLEAdvertisementData ad, scan;
  ad.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
  ad.addServiceUUID(NimBLEUUID(kService));
  scan.setName(name);
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->setAdvertisementData(ad);
  adv->setScanResponseData(scan);
  adv->start();
}

bool Ble::connected() { return server && server->getConnectedCount() > 0; }

// 24 bytes: version, flags, satellites, rate Hz, iTOW ms, latitude, longitude, speed cm/s, heading
// 0.01°, altitude mm. The first 20 are version 1's: with the smallest MTU only they get through.
void Ble::sendFix(const Fix& f, uint8_t rate) {
  if (!connected()) return;
  uint8_t p[24];
  p[0] = 2;
  p[1] = (f.valid ? 1 : 0) | (f.fix3d ? 2 : 0);
  p[2] = f.sats;
  p[3] = rate;
  put32(p + 4, f.itow);
  put32(p + 8, (uint32_t)f.lat);
  put32(p + 12, (uint32_t)f.lon);
  put16(p + 16, f.speed > 65535 ? 65535 : f.speed);
  put16(p + 18, f.heading % 36000);
  put32(p + 20, (uint32_t)f.alt);
  fixChr->setValue(p, sizeof p);
  fixChr->notify();
}

// 14 bytes: version, type, lap number, time ms, sector, delta ms (i32), flags (bit0 best lap,
// bits 1-2 the grade: 0 none, 1 fastest, 2 better, 3 worse).
void Ble::sendLap(const LapEvent& e) {
  if (!connected()) return;
  uint8_t p[14];
  p[0] = 1;
  p[1] = e.type;
  put16(p + 2, e.lap);
  put32(p + 4, e.ms);
  p[8] = e.sector;
  put32(p + 9, (uint32_t)e.delta);
  p[13] = (e.best ? 1 : 0) | (uint8_t)e.grade << 1;
  lapChr->setValue(p, sizeof p);
  lapChr->notify();
}

void Ble::setInfo(const char* json) {
  infoChr->setValue((const uint8_t*)json, strlen(json));
  if (connected()) infoChr->notify();
}

bool Ble::takeTrack(uint8_t* buf, size_t& len) { return take(trackBox, buf, len); }

bool Ble::takeControl(uint8_t* buf, size_t& len) { return take(controlBox, buf, len); }
