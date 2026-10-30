# TrackLap

**Italiano** · [English](README.en.md)

Cronometro da pista per iPhone: tempi sul giro, intermedi e delta live calcolati dal GPS,
con un ESP32 e un GPS collegati via Bluetooth (va bene qualsiasi ESP32 con Bluetooth: ESP32, S3,
C3, C5, C6, H2), il GPS dell'iPhone o un'auto simulata.

## Cosa fa

- **Live**: tempo del giro in corso, delta sul best (barra verde/rossa), tempo previsto,
  settori colorati (viola = best, verde = meglio del giro prima, giallo = più lento),
  ultimo giro, best, velocità e mini mappa con la posizione. Avviso a fine giro con vibrazione
  e annuncio vocale di tempo e distacco. Il delta può confrontare con il record della pista
  delle sessioni precedenti, così funziona già dal primo giro.
  Schermo sempre acceso durante la sessione; in orizzontale per il supporto sul cruscotto.
- **Piste**: ricerca mentre scrivi in tutto il mondo (Photon su OpenStreetMap, meno di un secondo),
  "piste vicino a me" o vicino a una città, catalogo di oltre 60 circuiti famosi con posizione verificata,
  "crea qui" sul posto. Il tracciato si scarica da Overpass o, se è lento, dall'API di OpenStreetMap. Editor sulla mappa satellitare: tocchi la pista e la linea del via si mette
  di traverso al tracciato da sola; fino a 4 intermedi; "segna qui" mette la linea dove sei.
- **Sessioni**: ogni giro viene salvato subito. Best, giro ideale (somma dei settori migliori),
  media, velocità massima, grafico dei tempi, esportazione GPX e CSV.
- **Analisi** (idee prese da RaceChrono): confronto di un giro con un altro della sessione o con il
  best di una sessione precedente sulla stessa pista; cursore unico per mappa, grafici di velocità
  e delta e barra di scorrimento; mappa colorata per velocità con la velocità minima di ogni curva
  o per dove si guadagna e si perde; confronto per settori; cerchio delle accelerazioni (g laterali
  e longitudinali calcolate dal GPS).
- **Dispositivo**: sorgente GPS (ESP32, iPhone, Demo), ricerca e collegamento BLE con
  ricollegamento automatico, invio della pista all'ESP32, chip e pin del GPS (si cambiano
  dall'app), impostazioni del cronometro.

- **Lingue**: italiano, inglese, spagnolo, francese, tedesco e portoghese (segue la lingua dell'iPhone,
  si cambia in Impostazioni → TrackLap). Unità km/h o mph.

Il cronometraggio interpola il passaggio sulla linea tra due fix GPS: a 10 Hz l'errore è di
pochi centesimi. Il delta confronta il tempo trascorso con quello del giro migliore alla stessa
distanza percorsa.

## Compilare e installare

Non serve un Mac: a ogni push su `main` GitHub Actions (`.github/workflows/ipa.yml`) genera il
progetto con XcodeGen, compila senza firma e pubblica l'artefatto `tracklap-ipa` con
`TrackLap-<versione>-unsigned.ipa`. Si installa con Sideloadly, AltStore o Feather, che lo
firmano con il proprio Apple ID.

Ogni versione è nelle release del repo e nella sorgente Feather
`https://raw.githubusercontent.com/TheBlackSide243/feather-repo/main/apps.json`; le novità sono in
[CHANGELOG.md](CHANGELOG.md), in inglese e in italiano.

Nuova versione: aumentare `MARKETING_VERSION` (e `CURRENT_PROJECT_VERSION`) in `project.yml`.

Traduzioni: il testo italiano è la chiave nel codice (`Text("…")`, `L("…")`); la tabella con le altre
lingue è in `tools/l10n.mjs`, che rigenera `Resources/<lingua>.lproj` con `node tools/l10n.mjs`.

## Firmware ESP32

Il firmware in `firmware/TrackLap` (Arduino, NimBLE) gira su tutti gli ESP32 con Bluetooth LE:
ESP32, ESP32-S3, ESP32-C3, ESP32-C5, ESP32-C6 ed ESP32-H2. L'ESP32-S2 e l'ESP32-P4 non hanno il
Bluetooth e non vanno bene.

- **GPS**: un u-blox (M7, M8 come il BN-220, M9, M10) viene portato da solo a 115200 baud, 10 Hz e
  UBX NAV-PVT, con il modello dinamico per auto; qualsiasi altro GPS viene letto in NMEA alla velocità
  a cui parla. Si può collegare anche a scheda già accesa.
- **Giri**: con la pista inviata dall'app l'ESP32 cronometra giri e intermedi da solo (pacchetto LAP)
  e se la ricorda anche da spento.
- **LED**: sulle schede con il LED RGB è rosso senza GPS, giallo in attesa del fix e verde con il fix;
  lampeggia finché l'app non si collega.

**Collegamento**: GPS alimentato a 3,3 V o 5 V come indicato sul modulo, GND in comune, poi

| Chip | TX del GPS → GPIO | RX del GPS ← GPIO |
|---|---|---|
| ESP32 | 16 | 17 |
| ESP32-S3 | 18 | 17 |
| ESP32-C3, C5, C6, H2 | 4 | 5 |

Se la scheda usa quei pin per altro (display, LED, la PSRAM dei moduli ESP32-WROVER su 16 e 17), si cambiano dall'app (Dispositivo → ESP32 →
Cambia pin) oppure dal monitor seriale USB a 115200 baud con `pins <rx> <tx>`; `pins default`
torna ai predefiniti, `info` mostra lo stato.

**Installazione**: a ogni modifica in `firmware/` GitHub Actions (`.github/workflows/firmware.yml`)
compila un file per ogni chip, `TrackLap-fw-<versione>-<chip>.bin`, nell'artefatto
`tracklap-firmware`. Si scrive dal browser (Chrome, Edge o Brave) con ESP Tool di Espressif,
https://espressif.github.io/esptool-js/: Connect, scegli la porta della scheda, indirizzo `0x0`,
il file del tuo chip, Program. Se la scheda non si collega, tieni premuto BOOT mentre la colleghi.

## Protocollo BLE v1 (per il firmware ESP32)

Servizio `7A1C0000-3F4B-4C8E-9D2A-6B1E5F0A9C10`, nome pubblicizzato `TrackLap-XXXX`.
Tutti i numeri sono little-endian.

| Caratteristica | UUID | Proprietà | Contenuto |
|---|---|---|---|
| FIX | `7A1C0001-…` | notify | un pacchetto per ogni fix GPS |
| LAP | `7A1C0002-…` | notify | giro cronometrato dall'ESP32 (facoltativo) |
| TRACK | `7A1C0003-…` | write (con risposta) | linea del via e intermedi |
| CONTROL | `7A1C0004-…` | write (con risposta) | comandi |
| INFO | `7A1C0005-…` | read, notify | stato dell'ESP32 in JSON |

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

Senza GPS l'ESP32 manda un FIX vuoto (non valido, 0 satelliti) ogni secondo.

**TRACK**: `u8 versione = 1`, `u8 numero di linee`, poi per ogni linea `i32 latA, i32 lonA,
i32 latB, i32 lonB` (× 1e7). La prima linea è il via, le altre sono gli intermedi.
L'ESP32 la salva in flash e la usa per cronometrare da solo.

**LAP**, 9 byte: `u8 versione = 1`, `u8 tipo` (1 = giro, 2 = intermedio), `u16 numero del giro`
(quello finito, o quello in corso per un intermedio), `u32 tempo in ms` (del giro, o del solo
intermedio), `u8 indice dell'intermedio` (da 0).

**CONTROL**: `0x01` azzera la sessione dell'ESP32; `0x02 rx tx` sposta il GPS su altri GPIO, li
salva e riavvia (`0x02 0xFF 0xFF` = pin predefiniti del chip).

**INFO**, per esempio
`{"fw":"0.1.0","chip":"ESP32-C6","gps":"u-blox M8","hz":10,"rx":4,"tx":5,"lines":3,"name":"TrackLap-1A2B"}`.
`gps` è vuoto finché nessun GPS risponde; arriva una notifica quando cambiano il modulo, la
frequenza o la pista.

## Prossimi passi

1. Display sulla scheda dell'ESP32 (serve il modello esatto) e servizio RaceChrono DIY in parallelo,
   così lo stesso dispositivo funziona anche con RaceChrono.
2. Multiplayer: server sull'homelab (WebSocket/MQTT), sessioni condivise con codice o QR,
   classifica e mappa live, delta sul best di un amico.

Mappe e tracciati © OpenStreetMap contributors.
