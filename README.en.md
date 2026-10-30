<p align="center">
  <img src="docs/readme/banner-en.jpg" alt="TrackLap: track lap timer for iPhone, with an ESP32 and a GPS" width="100%">
</p>

<p align="center">
  <a href="README.md">Italiano</a> · <b>English</b>
</p>

<p align="center">
  <img alt="iPhone, iOS 17 or later" src="https://img.shields.io/badge/iPhone-iOS%2017%2B-22D3EE?style=flat-square&logo=apple&logoColor=white">
  <img alt="ESP32 with Bluetooth LE" src="https://img.shields.io/badge/ESP32-Bluetooth%20LE-22D3EE?style=flat-square&logo=espressif&logoColor=white">
  <img alt="GPS at 10 Hz" src="https://img.shields.io/badge/GPS-10%20Hz-22D3EE?style=flat-square">
  <img alt="6 languages" src="https://img.shields.io/badge/languages-6-22D3EE?style=flat-square">
</p>

**TrackLap** is a track lap timer for iPhone. Lap times, sectors and a live delta worked out from
GPS: with an ESP32 and a 10 Hz GPS over Bluetooth, with the iPhone's own GPS, or with a simulated car
to try everything right away. The line crossing is interpolated between two fixes, so at 10 Hz the
times are right to a few hundredths.

<table>
  <tr>
    <td width="34%"><img src="docs/readme/en-live.webp" alt="The Live screen during a lap"></td>
    <td>
      <h3>Live</h3>
      <p>The running lap time, the <b>delta against the best lap</b> with a green or red bar, the
      predicted time and coloured sectors: purple for the best, green for better than the lap before,
      yellow for slower. Below, the last lap, the best, the speed and the circuit on satellite imagery.</p>
      <p>At the end of a lap a vibration and a <b>voice call-out</b> of the time and the gap. The delta
      can compare with the track record from earlier sessions, so it works from the first lap. The
      screen stays on, also in landscape for a dashboard mount.</p>
    </td>
  </tr>
  <tr>
    <td><img src="docs/readme/en-editor.webp" alt="The track editor on satellite imagery"></td>
    <td>
      <h3>Tracks</h3>
      <p><b>Search as you type</b> worldwide on OpenStreetMap, tracks near you or near a town, a
      catalogue of <b>60+ famous circuits</b> and "create here" on the spot.</p>
      <p>The layout downloads by itself. In the editor on satellite imagery you tap the track and the
      start line lays itself across it; add up to 4 sector lines, or "mark here" puts the line where
      you stand.</p>
    </td>
  </tr>
  <tr>
    <td><img src="docs/readme/en-session.webp" alt="A session summary"></td>
    <td>
      <h3>Sessions</h3>
      <p>Every lap is saved as soon as it ends. For each session the best, the <b>ideal lap</b> (the
      best sectors added up), the average, the top speed and the lap time chart.</p>
      <p>Export to <b>GPX and CSV</b>, with the speed and g of every point, for spreadsheets and
      analysis tools.</p>
    </td>
  </tr>
  <tr>
    <td><img src="docs/readme/en-analysis.webp" alt="Lap analysis with map and comparison"></td>
    <td>
      <h3>Analysis</h3>
      <p>Compare a lap with another lap of the session or with the best lap of an earlier session on
      the same track. One cursor moves both cars on the map and on the speed and delta charts.</p>
      <p>Map coloured by speed with the <b>minimum speed of every corner</b>, or by where you gain and
      lose; sector comparison and a <b>friction circle</b> with lateral and longitudinal g worked out
      from GPS.</p>
    </td>
  </tr>
</table>

In Italian, English, Spanish, French, German and Portuguese, following the iPhone's language; km/h or mph.

## The hardware

<p align="center">
  <img src="docs/readme/how-it-works-en.svg" alt="A GPS wired to the ESP32, which talks to the iPhone over Bluetooth LE" width="100%">
</p>

**Any ESP32 with Bluetooth** does (ESP32-WROOM-32, S3, C3, C5, C6, H2) plus a GPS, for example the
Beitian BN-220: the ESP32 sets the GPS to 10 Hz, times laps and sectors by itself and sends it all
to the app. Install the firmware from the browser at **[esp32.tbsgaming.win](https://esp32.tbsgaming.win)**;
the [wiring](#esp32-firmware) is below, with a diagram for every board.

On the **Waveshare ESP32-C6-LCD-1.47** the screen is a dashboard:

<p align="center">
  <img src="docs/readme/dashboard.svg" alt="The dashboard on the Waveshare ESP32-C6-LCD-1.47 screen" width="100%">
</p>

At each sector line the delta against the best lap: purple when you are the fastest ever there,
green when ahead of the previous lap, red when behind. At the finish the lap time: purple for a best
lap, green when faster than the session's average, red when slower.

## Install

- **iPhone**: add the source
  `https://raw.githubusercontent.com/TheBlackSide243/feather-repo/main/apps.json` to
  [Feather](https://github.com/khcrysalis/Feather) and install TrackLap, or download
  `TrackLap-<version>-unsigned.ipa` from the [releases](https://github.com/TheBlackSide243/TrackLap/releases)
  and install it with Sideloadly or AltStore. To try it without hardware, pick **Demo** in Device.
- **ESP32**: open [esp32.tbsgaming.win](https://esp32.tbsgaming.win) in Chrome, Edge or Brave on a
  computer, plug the board in over USB and press Install. Then in the app: Device → ESP32.

## Building

No Mac needed: on every push to `main` GitHub Actions (`.github/workflows/ipa.yml`) generates the
project with XcodeGen, builds it unsigned and publishes the `tracklap-ipa` artifact with
`TrackLap-<version>-unsigned.ipa`. Install it with Sideloadly, AltStore or Feather, which sign
it with your own Apple ID.

Each version is on the repo's Releases page and in the Feather source
`https://raw.githubusercontent.com/TheBlackSide243/feather-repo/main/apps.json`; what changed is in
[CHANGELOG.md](CHANGELOG.md), in English and Italian.

New version: bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in `project.yml` and
`FW_VERSION` in `firmware/TrackLap/TrackLap.ino`: the app and the firmware always share the number.

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
| ESP32-WROOM-32 (DevKit: RX2, TX2) | 16 | 17 |
| ESP32-S3 | 18 | 17 |
| ESP32-C3, C5, C6, H2 | 4 | 5 |
| Waveshare ESP32-C6-LCD-1.47 | 17 (RX pin) | 16 (TX pin) |

In the diagrams the arrows show where the data goes: the GPS TX goes to the pin that receives,
its RX to the one that transmits. VCC goes to 3V3, or to 5V if the module asks for it.

<p>
  <img src="docs/wiring/esp32.svg" width="300" alt="GPS wired to ESP32-WROOM-32">
  <img src="docs/wiring/esp32s3.svg" width="300" alt="GPS wired to ESP32-S3">
</p>
<p>
  <img src="docs/wiring/esp32c.svg" width="300" alt="GPS wired to ESP32-C3, C5, C6, H2">
  <img src="docs/wiring/lcd147.svg" width="300" alt="GPS wired to Waveshare ESP32-C6-LCD-1.47">
</p>

On the Waveshare GPIO 4 and 5 go to the microSD slot, so the GPS takes the header's RX and TX pins.
When the board uses those pins for something else (display, LED, the PSRAM of ESP32-WROVER modules
on 16 and 17), change them from the app (Device → ESP32 → Change pins) or from the USB serial
monitor at 115200 baud with `pins <rx> <tx>`; `pins default` goes back to the defaults, `info`
shows the state.

**Install**: open https://esp32.tbsgaming.win in Chrome, Edge or Brave on a computer, plug the
board in over USB and press Install: "Any ESP32 with Bluetooth" detects the chip by itself,
"Waveshare ESP32-C6-LCD-1.47" installs the build with the dashboard. Updates keep the pins and
the best lap. If the board does not connect, hold BOOT while plugging it in.

On every change in `firmware/` GitHub Actions (`.github/workflows/firmware.yml`) builds one file
per board listed in `firmware/build.txt`, `TrackLap-fw-<version>-<board>.bin`, in the
`tracklap-firmware` artifact: a merged image to write at `0x0` (for example with
https://espressif.github.io/esptool-js/), and the one the site publishes for each version.

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
`{"fw":"0.4.0","chip":"ESP32-C6","board":"Waveshare ESP32-C6-LCD-1.47","gps":"u-blox M8","hz":10,"rx":17,"tx":16,"lines":3,"name":"TrackLap-1A2B"}`.
`gps` is empty while no GPS answers; a notification comes when the module, the rate or the track
changes.

## Next steps

1. The RaceChrono DIY service alongside, so the same device also works with RaceChrono; more
   boards with a display.
2. Multiplayer: server on the homelab (WebSocket/MQTT), sessions shared with a code or QR,
   live leaderboard and map, delta to a friend's best.

Maps and layouts © OpenStreetMap contributors.
