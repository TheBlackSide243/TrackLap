#pragma once
#include <Arduino.h>

// The chip's name and its default GPS pins, for every ESP32 with Bluetooth LE. The defaults are
// free GPIOs on the usual dev boards; when a board uses them for something else, change them from
// the app (Device → ESP32) or over USB serial with "pins <rx> <tx>".
#if CONFIG_IDF_TARGET_ESP32
#define CHIP_NAME "ESP32"
#define GPS_RX_DEFAULT 16
#define GPS_TX_DEFAULT 17
#elif CONFIG_IDF_TARGET_ESP32S3
#define CHIP_NAME "ESP32-S3"
#define GPS_RX_DEFAULT 18
#define GPS_TX_DEFAULT 17
#elif CONFIG_IDF_TARGET_ESP32C3
#define CHIP_NAME "ESP32-C3"
#define GPS_RX_DEFAULT 4
#define GPS_TX_DEFAULT 5
#elif CONFIG_IDF_TARGET_ESP32C5
#define CHIP_NAME "ESP32-C5"
#define GPS_RX_DEFAULT 4
#define GPS_TX_DEFAULT 5
#elif CONFIG_IDF_TARGET_ESP32C6
#define CHIP_NAME "ESP32-C6"
#define GPS_RX_DEFAULT 4
#define GPS_TX_DEFAULT 5
#elif CONFIG_IDF_TARGET_ESP32H2
#define CHIP_NAME "ESP32-H2"
#define GPS_RX_DEFAULT 4
#define GPS_TX_DEFAULT 5
#else
#error "TrackLap needs Bluetooth LE, which the ESP32-S2 and ESP32-P4 do not have."
#endif
