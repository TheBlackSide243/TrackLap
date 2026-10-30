# TrackLap

[Italiano](README.md) · **English**

Track lap timer for iPhone: lap times, sectors and live delta computed from GPS, with an
ESP32 and a GPS connected over Bluetooth (any ESP32 with Bluetooth will do: ESP32, S3, C3, C5, C6,
H2), the iPhone's own GPS, or a simulated car.

## What it does

- **Live**: current lap time, delta to the best lap (green/red bar), predicted lap,
  coloured sectors (purple = best, green = better than the previous lap, yellow = slower),
  last lap, best, speed and a mini map with your position. Lap alert with vibration and the
  time and gap read out loud. The delta can compare with the track record from earlier
  sessions, so it works from the first lap.
  Screen kept on during the session; landscape for a dashboard mount.
- **Tracks**: search as you type, worldwide (Photon on OpenStreetMap, under a second),
  "tracks near me" or near a town, a catalog of 60+ famous circuits with checked positions,
  "create here" on the spot. The layout comes from Overpass or, when it is slow, from the
  OpenStreetMap API. Satellite map editor: tap the track and the start line sets itself
  across it; up to 4 sectors; "mark here" puts the line where you are.
- **Sessions**: every lap is saved straight away. Best, ideal lap (sum of the best sectors),
  average, top speed, lap-time chart, GPX and CSV export.
- **Analysis** (ideas from RaceChrono): compare a lap with another lap of the session or the best
  of an earlier session on the same track; one cursor for the map, the speed and delta charts and
  a slider; map coloured by speed with the minimum speed of each corner, or by where time is
  gained and lost; sector comparison; friction circle (lateral and longitudinal g from GPS).
- **Device**: GPS source (ESP32, iPhone, Demo), BLE scan and connection with automatic
  reconnection, sending the track to the ESP32, chip and GPS pins (changeable from the app),
  timer settings.

- **Languages**: English, Italian, Spanish, French, German and Portuguese (follows the iPhone
  language, change it in Settings → TrackLap). Units km/h or mph.

Timing interpolates the line crossing between two GPS fixes: at 10 Hz the error is a few
hundredths of a second. The delta compares the elapsed time with the best lap's time at the
same distance travelled.

## Build and install

No Mac needed: on every push to `main` GitHub Actions (`.github/workflows/ipa.yml`) generates the
project with XcodeGen, builds it unsigned and publishes the `tracklap-ipa` artifact with
`TrackLap-<version>-unsigned.ipa`. Install it with Sideloadly, AltStore or Feather, which sign
it with your own Apple ID.

Each version is on the repo's Releases page and in the Feather source
`https://raw.githubusercontent.com/TheBlackSide243/feather-repo/main/apps.json`; what changed is in
[CHANGELOG.md](CHANGELOG.md), in English and Italian.

New version: bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in `project.yml`.

Translations: the Italian text is the key in the code (`Text("…")`, `L("…")`); the table with the
other languages is in `tools/l10n.mjs`, which regenerates `Resources/<language>.lproj` with
`node tools/l10n.mjs`.

## ESP32 firmware

The firmware in `firmware/TrackLap` (Arduino, NimBLE) runs on every ESP32 with Bluetooth LE:
ESP32, ESP32-S3, ESP32-C3, ESP32-C5, ESP32-C6 and ESP32-H2. The ESP32-S2 and ESP32-P4 have no
Bluetooth and will not do.

- **GPS**: a u-blox (M7, M8 like the BN-220, M9, M10) is switched by itself to 115200 baud, 10 Hz
  and UBX NAV-PVT, with the automotive dynamic model; any other GPS is read as NMEA at whatever
  speed it talks. It can be plugged in after the board is on.
- **Laps**: with the track sent by the app the ESP32 times laps and sectors by itself (LAP packet),
  with the delta against the best lap at every line. The track and the best lap stay when it is
  switched off; the best lap is cleared when a different track arrives.
- **Display**: on the Waveshare ESP32-C6-LCD-1.47 (file `…-esp32c6-lcd147.bin`) the screen is a
  dashboard. During the lap it shows the time in big digits. At each sector line the delta against
  the best lap comes up for 4 seconds: purple when you are the fastest ever at that point, green when
  ahead of the previous lap, red when behind. At the finish the lap time comes up for 5 seconds with
  the gap: purple for a best lap, green when faster than the session's average, red when slower. Standing still it shows the speed;
  at the top the lap, satellites, rate and a green dot while the app is connected.
- **LED**: on boards with an RGB LED it is red without GPS, yellow while waiting for a fix and green
  with a fix; it blinks until the app connects.

**Wiring**: power the GPS from 3.3 V or 5 V as its module says, common GND, then

| Board | GPS TX → GPIO | GPS RX ← GPIO |
|---|---|---|
| ESP32 | 16 | 17 |
| ESP32-S3 | 18 | 17 |
| ESP32-C3, C5, C6, H2 | 4 | 5 |
| Waveshare ESP32-C6-LCD-1.47 | 17 (RX pin) | 16 (TX pin) |

On the Waveshare GPIO 4 and 5 go to the microSD slot, so the GPS takes the header's RX and TX pins.
When the board uses those pins for something else (display, LED, the PSRAM of ESP32-WROVER modules
on 16 and 17), change them from the app (Device → ESP32 → Change pins) or from the USB serial
monitor at 115200 baud with `pins <rx> <tx>`; `pins default` goes back to the defaults, `info`
shows the state.

**Install**: on every change in `firmware/` GitHub Actions (`.github/workflows/firmware.yml`) builds
one file per board listed in `firmware/build.txt`, `TrackLap-fw-<version>-<board>.bin`, in the
`tracklap-firmware` artifact. Write it
from the browser (Chrome, Edge or Brave) with Espressif's ESP Tool,
https://espressif.github.io/esptool-js/: Connect, pick the board's port, address `0x0`, the file for
your chip, Program. If the board does not connect, hold BOOT while plugging it in.

## BLE protocol v1 (for the ESP32 firmware)

Service `7A1C0000-3F4B-4C8E-9D2A-6B1E5F0A9C10`, advertised name `TrackLap-XXXX`.
All numbers are little-endian.

| Characteristic | UUID | Properties | Content |
|---|---|---|---|
| FIX | `7A1C0001-…` | notify | one packet per GPS fix |
| LAP | `7A1C0002-…` | notify | lap timed by the ESP32 (optional) |
| TRACK | `7A1C0003-…` | write (with response) | start line and sectors |
| CONTROL | `7A1C0004-…` | write (with response) | commands |
| INFO | `7A1C0005-…` | read, notify | the ESP32's state as JSON |

**FIX**, 20 bytes (fits the minimum MTU):

| Offset | Type | Field |
|---|---|---|
| 0 | u8 | version = 1 |
| 1 | u8 | flags: bit0 valid fix, bit1 3D fix |
| 2 | u8 | satellites |
| 3 | u8 | GPS rate in Hz |
| 4 | u32 | iTOW in ms (GPS time of week, from NAV-PVT) |
| 8 | i32 | latitude × 1e7 |
| 12 | i32 | longitude × 1e7 |
| 16 | u16 | speed in cm/s |
| 18 | u16 | heading in hundredths of a degree |

Without GPS the ESP32 sends an empty FIX (not valid, 0 satellites) every second.

**TRACK**: `u8 version = 1`, `u8 number of lines`, then for each line `i32 latA, i32 lonA,
i32 latB, i32 lonB` (× 1e7). The first line is the start, the others are the sectors.
The ESP32 stores it in flash and uses it to time laps by itself.

**LAP**, 14 bytes: `u8 version = 1`, `u8 type` (1 = lap, 2 = sector), `u16 lap number` (the one
that ended, or the one in progress for a sector), `u32 time in ms` (of the lap, or of the sector
alone), `u8 sector index` (from 0), `i32 delta in ms` against the best lap at the same line
(`0x7FFFFFFF` while there is none), `u8 flags`: bit0 new best lap, bits 1-2 the colour (0 none,
1 purple = the fastest ever, 2 green = better than the previous lap at a sector line or the average at
the finish, 3 red = worse).

**CONTROL**: `0x01` resets the ESP32 session; `0x02 rx tx` moves the GPS to other GPIOs, saves
them and restarts (`0x02 0xFF 0xFF` = the chip's default pins).

**INFO**, for example
`{"fw":"0.1.0","chip":"ESP32-C6","board":"Waveshare ESP32-C6-LCD-1.47","gps":"u-blox M8","hz":10,"rx":17,"tx":16,"lines":3,"name":"TrackLap-1A2B"}`.
`gps` is empty while no GPS answers; a notification comes when the module, the rate or the track
changes.

## Next steps

1. The RaceChrono DIY service alongside, so the same device also works with RaceChrono; more
   boards with a display.
2. Multiplayer: server on the homelab (WebSocket/MQTT), sessions shared with a code or QR,
   live leaderboard and map, delta to a friend's best.

Maps and layouts © OpenStreetMap contributors.
