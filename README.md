# TrackLap

Cronometro da pista per iPhone: tempi sul giro, intermedi e delta live calcolati dal GPS,
con un ESP32-C6 + GPS u-blox collegato via Bluetooth, il GPS dell'iPhone o un'auto simulata.

## Cosa fa

- **Live**: tempo del giro in corso, delta sul best (barra verde/rossa), tempo previsto,
  settori colorati (viola = best, verde = meglio del giro prima, giallo = più lento),
  ultimo giro, best, velocità e mini mappa con la posizione. Avviso a fine giro con vibrazione.
  Schermo sempre acceso durante la sessione; in orizzontale per il supporto sul cruscotto.
- **Piste**: ricerca su OpenStreetMap per nome o "vicino a me", circuiti italiani già pronti,
  "crea qui" sul posto. Editor sulla mappa satellitare: tocchi la pista e la linea del via si mette
  di traverso al tracciato da sola; fino a 4 intermedi; "segna qui" mette la linea dove sei.
- **Sessioni**: ogni giro viene salvato subito. Best, giro ideale (somma dei settori migliori),
  media, velocità massima, grafico dei tempi, mappa del giro colorata per velocità,
  velocità e delta sulla distanza rispetto al best, esportazione GPX.
- **Dispositivo**: sorgente GPS (ESP32, iPhone, Demo), ricerca e collegamento BLE con
  ricollegamento automatico, invio della pista all'ESP32, impostazioni del cronometro.

Il cronometraggio interpola il passaggio sulla linea tra due fix GPS: a 10 Hz l'errore è di
pochi centesimi. Il delta confronta il tempo trascorso con quello del giro migliore alla stessa
distanza percorsa.

## Compilare e installare

Non serve un Mac: a ogni push su `main` GitHub Actions (`.github/workflows/ipa.yml`) genera il
progetto con XcodeGen, compila senza firma e pubblica l'artefatto `tracklap-ipa` con
`TrackLap-<versione>-unsigned.ipa`. Si installa con Sideloadly, AltStore o Feather, che lo
firmano con il proprio Apple ID.

Nuova versione: aumentare `MARKETING_VERSION` (e `CURRENT_PROJECT_VERSION`) in `project.yml`.

## Protocollo BLE v1 (per il firmware ESP32)

Servizio `7A1C0000-3F4B-4C8E-9D2A-6B1E5F0A9C10`, nome pubblicizzato `TrackLap-XXXX`.
Tutti i numeri sono little-endian.

| Caratteristica | UUID | Proprietà | Contenuto |
|---|---|---|---|
| FIX | `7A1C0001-…` | notify | un pacchetto per ogni fix GPS |
| LAP | `7A1C0002-…` | notify | giro cronometrato dall'ESP32 (facoltativo) |
| TRACK | `7A1C0003-…` | write (con risposta) | linea del via e intermedi |
| CONTROL | `7A1C0004-…` | write (con risposta) | comandi |
| INFO | `7A1C0005-…` | read | JSON `{"fw":"0.1.0","gps":"BN-220","hz":10,"name":"TrackLap-1A2B"}` |

**FIX**, 20 byte (entra nell'MTU minimo):

| Offset | Tipo | Campo |
|---|---|---|
| 0 | u8 | versione = 1 |
| 1 | u8 | flag: bit0 fix valido, bit1 fix 3D |
| 2 | u8 | satelliti |
| 3 | u8 | frequenza GPS in Hz |
| 4 | u32 | iTOW in ms (tempo GPS della settimana, da NAV-PVT) |
| 8 | i32 | latitudine × 1e7 |
| 12 | i32 | longitudine × 1e7 |
| 16 | u16 | velocità in cm/s |
| 18 | u16 | direzione in centesimi di grado |

**TRACK**: `u8 versione = 1`, `u8 numero di linee`, poi per ogni linea `i32 latA, i32 lonA,
i32 latB, i32 lonB` (× 1e7). La prima linea è il via, le altre sono gli intermedi.
L'ESP32 la salva in flash e la usa per i tempi sul display.

**LAP**: `u8 versione`, `u8 tipo` (1 = giro, 2 = intermedio), `u16 numero giro`,
`u32 tempo in ms`, `u8 indice dell'intermedio`.

**CONTROL**: `0x01` azzera la sessione dell'ESP32.

Il firmware può esporre in parallelo anche il servizio RaceChrono DIY, così lo stesso
dispositivo funziona con entrambe le app.

## Prossimi passi

1. Firmware ESP32-C6 + BN-220 (10 Hz, UBX NAV-PVT, display, protocollo qui sopra).
2. Multiplayer: server sull'homelab (WebSocket/MQTT), sessioni condivise con codice o QR,
   classifica e mappa live, delta sul best di un amico.

Mappe e tracciati © OpenStreetMap contributors.
