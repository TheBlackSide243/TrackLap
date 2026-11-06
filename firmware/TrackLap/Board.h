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
#elif CONFIG_IDF_TARGET_ESP32C6 && defined(TRACKLAP_LCD147T)
// Waveshare ESP32-C6-Touch-LCD-1.47: the screen on GPIO 1, 2, 14, 15, 22 (backlight 23) and a
// QMI8658 accelerometer on I2C 18/19, shared with the touch panel; the GPS goes on the header pins
// marked RX (17) and TX (16), as on the board without touch.
#define CHIP_NAME "ESP32-C6"
#define BOARD_NAME "Waveshare ESP32-C6-Touch-LCD-1.47"
#define GPS_RX_DEFAULT 17
#define GPS_TX_DEFAULT 16
#define TRACKLAP_IMU_SDA 18
#define TRACKLAP_IMU_SCL 19
#elif CONFIG_IDF_TARGET_ESP32C6 && defined(TRACKLAP_LCD147)
// Waveshare ESP32-C6-LCD-1.47: GPIO 4 and 5 go to the microSD slot, so the GPS takes the header
// pins marked RX (17) and TX (16).
#define CHIP_NAME "ESP32-C6"
#define BOARD_NAME "Waveshare ESP32-C6-LCD-1.47"
#define GPS_RX_DEFAULT 17
#define GPS_TX_DEFAULT 16
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

#ifndef BOARD_NAME
#define BOARD_NAME CHIP_NAME
#endif

// The two Waveshare 1.47" boards have the same dashboard.
#if defined(TRACKLAP_LCD147) || defined(TRACKLAP_LCD147T)
#define TRACKLAP_DISPLAY
#endif
