# Changelog

English first, Italian below each version. / Prima in inglese, sotto ogni versione in italiano.

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
