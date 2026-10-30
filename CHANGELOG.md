# Changelog

English first, Italian below each version. / Prima in inglese, sotto ogni versione in italiano.

## 0.4.0 (2026-10-30)

Every ESP32, not just the C6, and the first firmware. / Tutti gli ESP32, non solo il C6, e il primo firmware.

### English

**New**
- ESP32 firmware 0.1.0 in `firmware/TrackLap`, for every ESP32 with Bluetooth LE: ESP32, S3, C3,
  C5, C6 and H2, one ready-made `.bin` per chip built by GitHub Actions.
- Any GPS: u-blox modules (M7, M8 like the BN-220, M9, M10) are set to 115200 baud and 10 Hz by
  themselves, any other module is read as NMEA. It can be plugged in after the board is on.
- The ESP32 times laps and sectors by itself on the track the app sends, with the delta against the
  best lap at every line; the track and the best lap are kept until a different track arrives.
- Dashboard on the Waveshare ESP32-C6-LCD-1.47 screen: the lap time in big digits; the delta at
  each sector line for 4 seconds, purple when it is the fastest ever there, green ahead of the
  previous lap, red behind; the lap time at the finish for 5 seconds with the gap, purple for a best
  lap, green faster than the session's average, red slower; the speed when standing still.
- Device → ESP32 shows the chip, the GPS module and its pins, warns when no GPS answers, and
  "Change pins" moves the GPS to other GPIOs for boards that use the default ones.
- Status LED on boards that have one: red without GPS, yellow waiting for a fix, green with a fix.

### Italiano

**Novità**
- Firmware ESP32 0.1.0 in `firmware/TrackLap`, per tutti gli ESP32 con Bluetooth LE: ESP32, S3,
  C3, C5, C6 e H2, con un `.bin` pronto per ogni chip compilato da GitHub Actions.
- Qualsiasi GPS: i moduli u-blox (M7, M8 come il BN-220, M9, M10) vengono impostati da soli a
  115200 baud e 10 Hz, gli altri vengono letti in NMEA. Si può collegare anche a scheda accesa.
- L'ESP32 cronometra giri e intermedi da solo sulla pista inviata dall'app, con il delta sul giro
  migliore a ogni linea; pista e giro migliore restano finché non arriva una pista diversa.
- Cruscotto sullo schermo della Waveshare ESP32-C6-LCD-1.47: tempo del giro a cifre grandi; delta a
  ogni intermedio per 4 secondi, viola se lì sei il più veloce di sempre, verde davanti al giro
  precedente, rosso dietro; tempo del giro al traguardo per 5 secondi con il distacco, viola se è il
  migliore, verde più veloce della media della sessione, rosso più lento; velocità da fermo.
- Dispositivo → ESP32 mostra chip, modulo GPS e pin, avvisa se nessun GPS risponde, e "Cambia pin"
  sposta il GPS su altri GPIO per le schede che usano quelli predefiniti.
- LED di stato sulle schede che lo hanno: rosso senza GPS, giallo in attesa del fix, verde con il fix.

## 0.3.0 (2026-10-30)

Lap analysis with ideas from RaceChrono. / Analisi dei giri con idee prese da RaceChrono.

### English

**New**
- Lap comparison: any lap against another lap of the session or the best lap of an earlier
  session on the same track (long-press a lap: "Use as reference"). Laps are matched by the
  share of the lap driven, so a different line does not pile up as delta.
- A cursor shared by the map, the speed and delta charts and a slider under the map, with
  distance, time, both speeds, delta and g at that point.
- Map coloured by speed with the minimum speed of every corner, or by where you gain (green)
  and lose (red) against the reference, with the reference line dashed.
- Sector-by-sector comparison with the reference.
- Friction circle: lateral and longitudinal g of the lap, worked out from GPS, with peak
  lateral, braking and acceleration.
- Live delta against the track record from earlier sessions (Device → Timer), so it works
  from the first lap; "track record" banner when you beat it, badge in the session.
- Voice announcement of the lap time and gap at the end of each lap, turning the music down
  (can be switched off).
- CSV export (speed and g for every point) next to GPX.

### Italiano

**Novità**
- Confronto giri: qualsiasi giro contro un altro giro della sessione o il best di una sessione
  precedente sulla stessa pista (tieni premuto un giro: "Usa come riferimento"). I giri sono
  allineati per percentuale di giro, così una traiettoria diversa non si accumula nel delta.
- Cursore unico per mappa, grafici di velocità e delta e una barra sotto la mappa, con distanza,
  tempo, le due velocità, delta e g in quel punto.
- Mappa colorata per velocità con la velocità minima di ogni curva, oppure per dove guadagni
  (verde) e perdi (rosso) sul riferimento, con la linea del riferimento tratteggiata.
- Confronto settore per settore con il riferimento.
- Cerchio delle accelerazioni: g laterali e longitudinali del giro calcolate dal GPS, con i
  massimi in curva, in frenata e in accelerazione.
- Delta live sul record della pista delle sessioni precedenti (Dispositivo → Cronometro), così
  funziona dal primo giro; banner "record pista" quando lo batti e badge nella sessione.
- Annuncio vocale di tempo e distacco a fine giro, abbassando la musica (si può spegnere).
- Export CSV (velocità e g per ogni punto) accanto al GPX.

## 0.2.0 (2026-10-30)

### English

**Fixed**
- Track search no longer hangs on "Searching…": searching by name across all of Italy made the
  OpenStreetMap servers time out (over 60 seconds). It now answers in under a second.
- Some of the ready-made circuits in 0.1.0 were in the wrong place (South Garda Karting was about
  2 km off). Every position now comes from OpenStreetMap.

**New**
- Search as you type, worldwide (Photon on OpenStreetMap), with no blocking screen; "Tracks near…"
  a town.
- Catalog of 60+ famous circuits with position and area checked on OpenStreetMap; your country first.
- "Tracks near me": quick results straight away, fuller ones added when Overpass answers.
- Layout download asks Overpass and the OpenStreetMap API at once; a track without a layout still opens.
- Six languages: English, Italian, Spanish, French, German, Portuguese (permission prompts included).
- km/h or mph; dates in the local format.

### Italiano

**Sistemato**
- La ricerca piste non resta più bloccata su "Cerco…": la ricerca per nome su tutta Italia faceva
  scadere i server di OpenStreetMap (oltre 60 secondi). Ora risponde in meno di un secondo.
- Alcuni circuiti pronti della 0.1.0 erano nel posto sbagliato (South Garda Karting era spostato di
  circa 2 km). Ora tutte le posizioni vengono da OpenStreetMap.

**Novità**
- Ricerca mentre scrivi in tutto il mondo (Photon su OpenStreetMap), senza schermata bloccante;
  "Piste vicino a…" una città.
- Catalogo di oltre 60 circuiti famosi con posizione e area verificate su OpenStreetMap; prima il tuo paese.
- "Piste vicino a me": risultati veloci subito, quelli più completi quando risponde Overpass.
- Il tracciato si chiede insieme a Overpass e all'API di OpenStreetMap; una pista senza tracciato si apre lo stesso.
- Sei lingue: italiano, inglese, spagnolo, francese, tedesco, portoghese (anche le richieste di permesso).
- km/h o mph; date nel formato locale.

## 0.1.0 (2026-10-30)

### English

First release of the iPhone track lap timer.
- **Live**: big, smooth lap time, delta to your best lap with a green/red bar, predicted lap, coloured
  sectors (purple = best, green = better than the previous lap, yellow = slower), last lap, best, speed
  and a mini map. Vibration at the end of each lap, screen kept on, landscape layout for a car mount.
- **Tracks**: OpenStreetMap search by name or near you, 13 Italian circuits ready to use, "Create here".
  Satellite editor: tap the track and the start line sets itself across it, up to 4 sectors, "Mark here".
- **Sessions**: every lap saved straight away; best, ideal lap, average, top speed, lap-time chart,
  lap map coloured by speed, speed and delta against the best, GPX export.
- **Device**: GPS from the ESP32-C6 over Bluetooth (protocol v1, reconnects by itself), the iPhone GPS,
  or Demo with a simulated car at 10 Hz. App in Italian only.

### Italiano

Prima versione del cronometro da pista per iPhone.
- **Live**: tempo del giro grande e fluido, delta sul giro migliore con barra verde/rossa, tempo previsto,
  settori colorati (viola = migliore, verde = meglio del giro prima, giallo = più lento), ultimo giro, best,
  velocità e mini mappa. Vibrazione a fine giro, schermo sempre acceso, layout orizzontale per il supporto in auto.
- **Piste**: ricerca su OpenStreetMap per nome o vicino a te, 13 circuiti italiani pronti, "Crea qui".
  Editor satellitare: tocchi la pista e la linea del via si mette di traverso da sola, fino a 4 intermedi, "Segna qui".
- **Sessioni**: ogni giro salvato subito; best, giro ideale, media, velocità massima, grafico dei tempi,
  mappa del giro colorata per velocità, velocità e delta rispetto al best, esportazione GPX.
- **Dispositivo**: GPS dall'ESP32-C6 via Bluetooth (protocollo v1, si ricollega da solo), GPS dell'iPhone
  o Demo con un'auto simulata a 10 Hz. App solo in italiano.
