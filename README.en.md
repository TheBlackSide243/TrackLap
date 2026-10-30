# TrackLap

[Italiano](README.md) · **English**

Track lap timer for iPhone: lap times, sectors and live delta computed from GPS, with an
ESP32-C6 + u-blox GPS connected over Bluetooth, the iPhone's own GPS, or a simulated car.

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
  reconnection, sending the track to the ESP32, timer settings.

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

## BLE protocol v1 (for the ESP32 firmware)

Service `7A1C0000-3F4B-4C8E-9D2A-6B1E5F0A9C10`, advertised name `TrackLap-XXXX`.
All numbers are little-endian.

| Characteristic | UUID | Properties | Content |
|---|---|---|---|
| FIX | `7A1C0001-…` | notify | one packet per GPS fix |
| LAP | `7A1C0002-…` | notify | lap timed by the ESP32 (optional) |
| TRACK | `7A1C0003-…` | write (with response) | start line and sectors |
| CONTROL | `7A1C0004-…` | write (with response) | commands |
| INFO | `7A1C0005-…` | read | JSON `{"fw":"0.1.0","gps":"BN-220","hz":10,"name":"TrackLap-1A2B"}` |

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

**TRACK**: `u8 version = 1`, `u8 number of lines`, then for each line `i32 latA, i32 lonA,
i32 latB, i32 lonB` (× 1e7). The first line is the start, the others are the sectors.
The ESP32 stores it in flash and uses it for the times on its display.

**LAP**: `u8 version`, `u8 type` (1 = lap, 2 = sector), `u16 lap number`,
`u32 time in ms`, `u8 sector index`.

**CONTROL**: `0x01` resets the ESP32 session.

The firmware can also expose the RaceChrono DIY service alongside, so the same device works
with both apps.

## Next steps

1. ESP32-C6 + BN-220 firmware (10 Hz, UBX NAV-PVT, display, the protocol above).
2. Multiplayer: server on the homelab (WebSocket/MQTT), sessions shared with a code or QR,
   live leaderboard and map, delta to a friend's best.

Maps and layouts © OpenStreetMap contributors.
