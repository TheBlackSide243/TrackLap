# Changelog

English first, Italian below each version. / Prima in inglese, sotto ogni versione in italiano.

## 0.8.2 (2026-11-04)

Every layout of a track, and TrackLap follows the one you drive. / Tutti i tracciati di una pista, e
TrackLap segue quello su cui giri.

### English

**New**
- **Every layout of a track**: besides the circuits OpenStreetMap maps, TrackLap finds the other
  laps the track allows, up to four, the most different first. Monza gets the full circuit, the
  Junior and the motorcycle chicane; Spa its motorcycle layout; the Red Bull Ring the Südschleife.
- **The layout follows where you drive**: after every lap TrackLap compares it with each layout.
  On another one it takes that layout's lines, files the next laps in a session of their own, and
  compares with that layout's laps and record only. Layouts too alike to tell apart (Monza's two
  chicanes) stay as chosen in the editor. Live shows the layout in use.
- Sessions show their layout, and the analysis compares laps of the same layout only.
- Lines moved by hand stay with their layout.

**Fixed**
- **Track editor**: the back button and the menu float over the map. On the closed iPhone Duo the
  system bar showed the title without them.
- **Downloading a track**: a busy OpenStreetMap server takes longer than before, so TrackLap now
  waits longer. A track saved while it did not answer shows **Download the layout**.

**Firmware 0.8.2**
- Same as 0.7.0, only the version number changes.

### Italiano

**Novità**
- **Tutti i tracciati di una pista**: oltre ai circuiti segnati su OpenStreetMap, TrackLap trova gli
  altri giri che la pista permette, fino a quattro, prima i più diversi. Monza ha il circuito
  completo, il Junior e la chicane delle moto; Spa il tracciato moto; il Red Bull Ring la
  Südschleife.
- **Il tracciato segue dove giri**: dopo ogni giro TrackLap lo confronta con ogni tracciato. Su un
  altro prende le sue linee, mette i giri seguenti in una sessione a parte e confronta solo con i
  giri e il record di quel tracciato. I tracciati troppo simili per distinguerli (le due chicane di
  Monza) restano come scelto nell'editor. Live mostra il tracciato in uso.
- Le sessioni mostrano il loro tracciato, e l'analisi confronta solo giri dello stesso tracciato.
- Le linee spostate a mano restano con il loro tracciato.

**Corretto**
- **Editor della pista**: la freccia indietro e il menu stanno sopra la mappa. Sull'iPhone Duo
  chiuso la barra di sistema mostrava il titolo senza di loro.
- **Download della pista**: un server di OpenStreetMap occupato ci mette più di prima, quindi
  TrackLap ora aspetta di più. Una pista salvata mentre non rispondeva mostra **Scarica il
  tracciato**.

**Firmware 0.8.2**
- Uguale alla 0.7.0, cambia solo il numero di versione.

## 0.8.1 (2026-11-04)

The car of every drag run, and tracks that come with the start line and the sectors. / L'auto di
ogni corsa drag, e piste che arrivano con il via e i settori.

### English

**New**
- **Drag with the car**: every run remembers the car you drive (pick it in the Drag header, as in
  Live). Records are per car, with "All" to see every car together; a run's page opens its car,
  and a car's page lists its best drag measures.
- **Start line and sectors by themselves**: when you pick a track, the start line and two
  intermediates are already there.
  - Where OpenStreetMap has the circuit (most big tracks), the line goes on the finish it marks,
    and the lap is that layout's: the editor lets you switch layout when there are several.
  - Elsewhere the lap is the longest loop of the track, leaving out pit lanes and old banking, and
    the line goes beside the pits, on the straight named for the start, or on the longest
    straight.
  - The three sectors are of the same length, kept off junctions and other parts of the track.
  - The editor says how each line was placed, and **"Place start and sectors automatically"**
    does it for tracks saved before.

**Firmware 0.8.1**
- Same as 0.7.0, only the version number changes.

### Italiano

**Novità**
- **Drag con l'auto**: ogni corsa ricorda l'auto che usi (si sceglie in alto nel Drag, come in
  Live). I record sono per auto, con "Tutte" per vederle insieme; la pagina di una corsa apre la
  sua auto, e la pagina dell'auto mostra i suoi migliori Drag.
- **Via e settori da soli**: quando scegli una pista, la linea del via e due intermedi ci sono
  già.
  - Dove OpenStreetMap ha il circuito (quasi tutte le piste grandi), il via va sul traguardo che
    segna e il giro è quello del tracciato: nell'editor si cambia tracciato quando ce ne sono più
    di uno.
  - Altrove il giro è l'anello più lungo della pista, senza corsia box e vecchie sopraelevate, e il
    via va accanto ai box, sul rettilineo che si chiama di partenza o sul rettilineo più lungo.
  - I tre settori sono lunghi uguali, lontani dagli incroci e dalle altre parti della pista.
  - L'editor dice come è stata messa ogni linea, e **"Via e intermedi automatici"** lo fa anche
    sulle piste salvate prima.

**Firmware 0.8.1**
- Uguale alla 0.7.0, cambia solo il numero di versione.

## 0.8.0 (2026-11-04)

The Garage, accounts, and leaderboards that show the car of every time. / Il Garage, gli account e
le classifiche che mostrano l'auto di ogni tempo.

### English

**New**
- **Garage** tab: the cars you drive on track, each with a photo, the year, the power, the weight
  and every modification, one per line. The car you drive sits on top, the others in a grid.
- **A car's page**: the photo across the top (pull it down, tap it to see it full screen and zoom),
  power, weight, power-to-weight and year, the numbered modifications, the notes and your best
  time with that car on each track.
- **Car editor**: photo from the library (made smaller on the phone), numbers in CV and kg or hp
  and lb as the settings say, and one tap for the usual modifications (exhaust, ECU tune,
  suspension, brakes…).
- **Accounts**: a username and a password, in Device → Account. Change the password, sign out, or
  delete the account together with its garage and its laps.
- **Public garage**: one switch shows it to everyone at a link of its own, which opens without the
  app too and previews the first photo in chats. It updates on its own after every change. Other
  people's garages can be reported or hidden.
- **Live**: pick the car you drive; every session remembers it.
- **Leaderboards**: publishing needs an account, and the name is the account's. Every time says
  whether it came from an external GPS or the iPhone, the board can show both together, and the
  car of a lap opens with a tap.

**Changed**
- Six tabs, so the app draws its own bottom bar (iOS shows five): all of them always in view.

**Firmware 0.8.0**
- Same as 0.7.0, only the version number changes.

### Italiano

**Novità**
- Scheda **Garage**: le auto con cui giri in pista, ognuna con una foto, l'anno, la potenza, il
  peso e tutte le modifiche, una per riga. Quella che usi sta in cima, le altre in una griglia.
- **La pagina dell'auto**: la foto in alto (si allunga tirandola giù, si apre a tutto schermo con lo
  zoom), potenza, peso, rapporto peso/potenza e anno, le modifiche numerate, le note e il tuo
  miglior tempo con quell'auto su ogni pista.
- **Editor dell'auto**: foto dalla libreria (rimpicciolita sul telefono), numeri in CV e kg o in hp
  e lb secondo le impostazioni, e un tocco per le modifiche più comuni (scarico, centralina,
  assetto, freni…).
- **Account**: nome utente e password, in Dispositivo → Account. Si può cambiare la password,
  uscire, o eliminare l'account insieme al garage e ai tempi.
- **Garage pubblico**: con un interruttore lo vedono tutti a un link suo, che si apre anche senza
  l'app e nelle chat mostra la prima foto. Si aggiorna da solo dopo ogni modifica. I garage degli
  altri si possono segnalare o nascondere.
- **Live**: scegli l'auto che usi; ogni sessione se la ricorda.
- **Classifiche**: per pubblicare serve un account, e il nome è quello dell'account. Ogni tempo
  dice se viene da un GPS esterno o dall'iPhone, la classifica può mostrarli insieme e l'auto di un
  giro si apre con un tocco.

**Modificato**
- Sei schede, quindi l'app disegna la sua barra in basso (iOS ne mostra cinque): si vedono sempre
  tutte.

**Firmware 0.8.0**
- Uguale alla 0.7.0, cambia solo il numero di versione.

## 0.7.3 (2026-11-03)

The closed iPhone Duo's tabs at the bottom of the column, clear of the island. / Le schede del Duo
chiuso in fondo alla colonna, lontane dall'isola.

### English

**Changed**
- **iPhone Duo closed**: the tabs stand at the bottom of the right column, like the Home screen's
  dock. When another app shows something in the island (navigation, a timer) the time and the
  battery move down, and iOS does not tell an app: from the bottom the tabs stay clear of them
  whatever the island shows.

**Firmware 0.7.3**
- Same as 0.7.0, only the version number changes.

### Italiano

**Modificato**
- **iPhone Duo chiuso**: le schede stanno in fondo alla colonna di destra, come il dock della Home.
  Quando un'altra app mostra qualcosa nell'isola (navigazione, un timer) ora e batteria scendono, e
  iOS non lo dice alle app: partendo dal basso le schede restano libere qualunque cosa mostri
  l'isola.

**Firmware 0.7.3**
- Uguale alla 0.7.0, cambia solo il numero di versione.

## 0.7.2 (2026-11-03)

The closed iPhone Duo's tabs below the camera. / Le schede del Duo chiuso sotto la fotocamera.

### English

**Fixed**
- **iPhone Duo closed**: the first tab covered the bottom of the front camera; the tabs now start
  below it.

**Firmware 0.7.2**
- Same as 0.7.0, only the version number changes.

### Italiano

**Corretto**
- **iPhone Duo chiuso**: la prima scheda copriva la parte bassa della fotocamera; ora le schede
  partono sotto.

**Firmware 0.7.2**
- Uguale alla 0.7.0, cambia solo il numero di versione.

## 0.7.1 (2026-11-03)

Tabs on the right, for the iPhone Duo and the iPhone on its side. / Schede a destra, per l'iPhone
Duo e l'iPhone in orizzontale.

### English

**New**
- **Tabs on the right** when the screen is wider than it is tall: the iPhone Duo opened, or the
  iPhone on its side in the car mount. The page keeps its whole height.
- **iPhone Duo closed**: the tabs are the column on the right where iOS writes the time and the
  battery, below them, and move lower while a call or a screen recording makes the island taller.
- **Device → Tab bar**: Automatic (the default), Bottom or Right.

**Firmware 0.7.1**
- Same as 0.7.0, only the version number changes.

### Italiano

**Novità**
- **Schede a destra** quando lo schermo è più largo che alto: l'iPhone Duo aperto, o l'iPhone in
  orizzontale sul supporto in auto. La pagina tiene tutta la sua altezza.
- **iPhone Duo chiuso**: le schede sono la colonna a destra dove iOS scrive ora e batteria, sotto di
  esse, e scendono più in basso quando una chiamata o una registrazione dello schermo allunga
  l'isola.
- **Dispositivo → Barra delle schede**: Automatica (predefinita), In basso o A destra.

**Firmware 0.7.1**
- Uguale alla 0.7.0, cambia solo il numero di versione.

## 0.7.0 (2026-11-03)

Drag: acceleration and braking like a performance meter, on the iPhone and the ESP32 dashboard. /
Drag: accelerazione e frenata come un misuratore di prestazioni, sull'iPhone e sul cruscotto
dell'ESP32.

### English

**New**
- **Drag tab**: stop, *READY* comes up, and the clock starts by itself when the car moves off. From
  the GPS speed, each threshold interpolated between two fixes: 0–50, 0–100, 0–150 and 0–200 km/h,
  60 ft, 1/8 and 1/4 mile and 1000 m with the trap speed, 80–120 and 100–200 km/h also rolling, and
  100–0 km/h with the stopping distance (0–30, 0–60, 0–100, 0–130, 50–70, 60–130 mph, the half mile
  and 60–0 in mph). Optional 1 ft rollout, as on a drag strip.
- For every run: the road's slope from the GPS altitude, the peak g, speed and acceleration charts,
  and a picture to share. Your records of each measure, in purple, and the history of every run.
- The voice reads 0–100 (0–60), the quarter mile and braking; a banner shows every measure as it
  is done.
- Demo: a simulated run, a hot hatch on a kilometre of straight road.

**Firmware 0.7.0**
- The FIX packet carries the altitude (24 bytes, the first 20 as before), for the slope.
- CONTROL `0x05`: the Waveshare dashboard switches to drag, with the speed, *READY* / *GO* with the
  run's time, and the main results for 5 seconds.

### Italiano

**Novità**
- **Scheda Drag**: ti fermi, compare *PRONTO*, e il tempo parte da solo quando l'auto si muove.
  Dalla velocità del GPS, con ogni soglia interpolata tra due fix: 0–50, 0–100, 0–150 e 0–200 km/h,
  60 ft, 1/8 e 1/4 di miglio e 1000 m con la velocità all'arrivo, 80–120 e 100–200 km/h anche
  lanciati, e 100–0 km/h con lo spazio di arresto (in mph 0–30, 0–60, 0–100, 0–130, 50–70, 60–130,
  mezzo miglio e 60–0). Rollout di 1 ft a scelta, come sulle piste di accelerazione.
- Per ogni corsa: la pendenza della strada dall'altitudine del GPS, il picco di g, i grafici di
  velocità e accelerazione e un'immagine da condividere. I tuoi record di ogni misura, in viola, e
  lo storico di tutte le corse.
- La voce legge 0–100 (0–60), quarto di miglio e frenata; un banner mostra ogni misura appena fatta.
- Demo: una corsa simulata, una hot hatch su un chilometro di rettilineo.

**Firmware 0.7.0**
- Il pacchetto FIX porta l'altitudine (24 byte, i primi 20 come prima), per la pendenza.
- CONTROL `0x05`: il cruscotto della Waveshare passa alla modalità drag, con la velocità, *READY* /
  *GO* con il tempo della corsa e i risultati principali per 5 secondi.

## 0.6.0 (2026-10-30)

Multiplayer: friends' laps to chase, live groups and online leaderboards. / Multiplayer: i giri
degli amici da sfidare, i gruppi live e le classifiche online.

### English

**New**
- **Challenges**: share a lap from a session as a `.tracklap` file (WhatsApp, Messages, AirDrop…).
  Opened with TrackLap, it lands in Sessions → Friends' laps, on your track with the same start line
  or with the friend's track added to yours. Chase it in Live: the delta is against their lap, on the
  ESP32 dashboard too, the lap banner and the voice give the gap to them. In the analysis it is one
  more lap to compare with, corner by corner.
- **Live group**: create a group and friends join with a five-character code or by scanning its QR
  code with the Camera. Live shows the standings of everyone on your track (best, last lap, gap to
  the leader), their dots on the map, and the real gap to the cars just ahead and behind on the
  track, from the GPS times of both cars at the same point. The voice reads your place at the end of
  each lap and the ESP32 shows it. Each phone still times its own laps: the network only shares them.
- **Online leaderboards** for every track, ESP32 and iPhone apart, from Live, from a track's menu in
  Tracks, or by publishing your best laps automatically (Device → You and your friends). Demo laps
  never go in.
- Device → You and your friends: your name and vehicle for all of this.
- The TrackLap server in `server/`: a Cloudflare Worker with Durable Objects, with its tests.

**Firmware 0.6.0**
- CONTROL `0x03` sets a friend's lap to chase: the deltas at every line and at the finish are against
  it. CONTROL `0x04` is the place in the live group: shown at the top of the Waveshare dashboard and,
  when it changes, for 4 seconds at the bottom with the gap.
- Several commands in a row from the app all get through.

### Italiano

**Novità**
- **Sfide**: un giro di una sessione si condivide come file `.tracklap` (WhatsApp, Messaggi,
  AirDrop…). Aperto con TrackLap finisce in Sessioni → Giri degli amici, sulla tua pista con la
  stessa linea del via o con la pista dell'amico aggiunta alle tue. Lo sfidi in Live: il delta è sul
  suo giro, anche sul cruscotto dell'ESP32, e il banner di fine giro e la voce dicono il distacco da
  lui. Nell'analisi è un giro in più da confrontare, curva per curva.
- **Gruppo live**: crei un gruppo e gli amici entrano con un codice di cinque caratteri o
  inquadrando il QR con la Fotocamera. In Live c'è la classifica di chi è sulla tua pista (best,
  ultimo giro, distacco dal primo), i loro puntini sulla mappa e il distacco vero dalle auto davanti e
  dietro, dall'orario GPS dei due passaggi nello stesso punto. A fine giro la voce dice la posizione
  e l'ESP32 la mostra. Ogni telefono cronometra sempre da sé: la rete serve solo a condividere.
- **Classifiche online** per ogni pista, ESP32 e iPhone separati, da Live, dal menu di una pista in
  Piste, oppure pubblicando in automatico i tuoi best (Dispositivo → Tu e gli amici). I giri della
  Demo non entrano mai.
- Dispositivo → Tu e gli amici: il tuo nome e la tua auto per tutto questo.
- Il server di TrackLap in `server/`: un Cloudflare Worker con Durable Objects, con i suoi test.

**Firmware 0.6.0**
- CONTROL `0x03` imposta il giro di un amico da sfidare: i delta a ogni linea e al traguardo sono su
  quel giro. CONTROL `0x04` è la posizione nel gruppo live: in alto sul cruscotto della Waveshare e,
  quando cambia, per 4 secondi in basso con il distacco.
- Più comandi di fila dall'app arrivano tutti.

## 0.5.0 (2026-10-30)

A welcome on the first launch, and a GitHub page with real screenshots. / Un'introduzione al primo
avvio, e una pagina GitHub con gli screenshot veri.

### English

**New**
- Intro on the first launch, in all six languages: the circuit of the icon draws itself with a car
  lapping it, a lap with its live delta, what the app does, and the choice of GPS source (ESP32,
  iPhone GPS or Demo). Skip it from any page; Device → Information shows it again.
- The README opens with a banner and real screenshots of every screen, a diagram of how the parts
  talk to each other, a preview of the ESP32 dashboard and a wiring diagram for every board.

**Changed**
- The ESP32 firmware has the same version as the app from now on: this is firmware 0.5.0, the same
  code as 0.4.0. Boards on 0.4.0 don't need the update.

### Italiano

**Novità**
- Introduzione al primo avvio, in tutte e sei le lingue: il circuito dell'icona si disegna con
  un'auto che ci gira sopra, un giro con il delta in diretta, cosa fa l'app e la scelta della
  sorgente GPS (ESP32, GPS dell'iPhone o Demo). Si salta da qualsiasi pagina; Dispositivo →
  Informazioni la fa rivedere.
- Il README si apre con un banner e gli screenshot veri di ogni schermata, uno schema di come
  parlano le parti, un'anteprima del cruscotto dell'ESP32 e lo schema dei collegamenti per ogni
  scheda.

**Cambiato**
- Da ora il firmware ESP32 ha lo stesso numero dell'app: questo è il firmware 0.5.0, lo stesso
  codice della 0.4.0. Le schede con la 0.4.0 non hanno bisogno di aggiornarlo.

## 0.4.0 (2026-10-30)

Every ESP32, not just the C6, and the first firmware. / Tutti gli ESP32, non solo il C6, e il primo firmware.

### English

**New**
- ESP32 firmware in `firmware/TrackLap`, for every ESP32 with Bluetooth LE: ESP32, S3, C3, C5, C6
  and H2, one ready-made `.bin` per chip built by GitHub Actions. It has the same version as the
  app, 0.4.0, and installs from the browser at https://esp32.tbsgaming.win.
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
- Live: the circuit map is on satellite imagery.

### Italiano

**Novità**
- Firmware ESP32 in `firmware/TrackLap`, per tutti gli ESP32 con Bluetooth LE: ESP32, S3, C3, C5,
  C6 e H2, con un `.bin` pronto per ogni chip compilato da GitHub Actions. Ha lo stesso numero
  dell'app, 0.4.0, e si installa dal browser su https://esp32.tbsgaming.win.
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
- Live: la mappa del circuito è in vista satellite.

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
