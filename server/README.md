# TrackLap server

English first, then Italian. / Prima in inglese, poi in italiano.

## English

The live groups, the online leaderboards, the accounts and the public garages of the TrackLap app,
as one Cloudflare Worker with four Durable Object classes ([`src/index.js`](src/index.js)). It runs
on the Workers free plan.

- **Room**, one per group: the WebSockets of its members (they hibernate between messages, so an
  idle group costs nothing), their names and times. Positions are relayed, never stored. A group is
  deleted a day after the last activity with nobody connected.
- **Boards**, one for every leaderboard: the circuits by the middle of their start line (two lines
  within 150 m are the same circuit, a lap more than 20% longer or shorter is another layout), and
  for each one the best lap of every driver with each kind of GPS, with the car of that lap.
- **Accounts**, one for everyone: a username (3 to 20 letters, numbers, `.` `-` `_`, unique whatever
  the capitals) and a password kept as a salted PBKDF2-SHA256 hash. Signing in gives the phone a
  token; only its hash is stored. Ten wrong passwords in 15 minutes block a name or an address for
  a while.
- **Garage**, one per driver who shows their cars: up to 20 cars with one JPEG photo each (up to
  1.5 MB), year, power in CV, weight in kg, modifications and notes. Only the owner writes; anyone
  reads, in the app or on the page `/g/<code>`. Reports from three different people hide a garage
  until the admin looks at it.

The phones do all the timing: the server only stores and relays.

### API

| Call | What it does |
|---|---|
| `POST /v1/rooms` | a new group: `{"code":"K7P2Q"}` |
| `GET /v1/rooms/<code>/ws` | the group's WebSocket |
| `POST /v1/accounts` | `{username, password}` → `{token, account: {id, name, garage}}` (409 if the name is taken) |
| `POST /v1/sessions` | sign in, same body and answer |
| `DELETE /v1/sessions` | sign out this token |
| `GET /v1/me` | the account of the token |
| `POST /v1/me/password` | `{old, new}` → a new token; every other token stops working |
| `DELETE /v1/me` | `{password}`: the account goes, with its garage and its laps |
| `POST /v1/me/garage` | your garage's code (made the first time): `{"code":"K7P2QX9M"}` |
| `GET /v1/garages/<code>` | the garage: `{code, name, cars: [{id, name, year, power, weight, mods, notes, photo}], mine}`; for its owner also the photos still `missing` |
| `PUT /v1/garages/<code>` | the owner's cars, all of them: the answer lists the `missing` photos; photos of cars that went are deleted |
| `PUT /v1/garages/<code>/photos/<id>` | a JPEG for a car of the garage, owner only |
| `GET /v1/garages/<code>/photos/<id>` | the photo, cached for good (a new photo gets a new id) |
| `POST /v1/garages/<code>/report` | `{reason, car}` from anyone |
| `GET /g/<code>` | the garage's page, in Italian or English, with a preview for chats |
| `GET /v1/boards?lat=&lon=&len=` | the leaderboard of the circuit whose start line is there (`len` = a lap in metres, to pick the layout); each lap has `name`, `vehicle`, `garage` and `car`, and yours `"mine":true` when signed in |
| `POST /v1/laps` | signed in: `{source: "device"\|"phone", time, distance, sectors, date, track: {name, lat, lon}, car}`; the name is the account's, and `car` links the lap only if it is in your garage |

Signed-in calls carry `Authorization: Bearer <token>`.

WebSocket messages, JSON with a `t`:

| From the phone | |
|---|---|
| `hello` | `{id, name, vehicle, track: {name, lat, lon}, best, last, laps}`, first and after every reconnection; the times replace what the server had |
| `pos` | `{lat, lon, lap, d, v, g}`: the lap in progress (0 = not timing), metres into it, speed in m/s, UTC of the fix (GPS time with the ESP32); about once a second |
| `lap` | `{n, time}` at every lap |
| `ping` | answered `pong` without waking the group |

| From the server | |
|---|---|
| `state` | `{you, members, positions}` after `hello` |
| `member` | `{member}`: someone joined, changed, or went offline |
| `pos`, `lap` | another member's, with their `id`; `lap` carries their new `best`, `last` and `laps` |

### Moderation

Set a secret `ADMIN_KEY` on the Worker (Settings → Variables and Secrets). Reports show in the
Worker's logs as `garage reported <code>`. With the header `X-TrackLap-Admin: <key>`:
`GET /v1/garages/<code>` shows a hidden garage and its reports, `POST /v1/garages/<code>/restore`
shows it again, `DELETE /v1/garages/<code>` deletes it.

### Tests and deployment

`npm test` runs the objects and the worker against an in-memory stand-in for the Durable Object
runtime (Node 22 or later, nothing to install).

Cloudflare deploys it from this folder through its Git integration (Workers & Pages → the `tracklap`
Worker → Settings → Build, root directory `server`), with `npx wrangler deploy` and the migrations
in [`wrangler.toml`](wrangler.toml), at every push to `main`. The app talks to
`https://tracklap.tbsgaming.win`, a custom domain on the Worker (also at
`https://tracklap.theblackside243.workers.dev`); `-server <url>` on the app's command line points it
somewhere else.

## Italiano

I gruppi live, le classifiche online, gli account e i garage pubblici dell'app TrackLap, in un
Cloudflare Worker con quattro classi di Durable Object ([`src/index.js`](src/index.js)). Sta nel
piano gratuito di Workers.

- **Room**, una per gruppo: le WebSocket dei membri (vanno in ibernazione tra un messaggio e
  l'altro, quindi un gruppo fermo non costa niente), i nomi e i tempi. Le posizioni passano e
  basta, non vengono salvate. Un gruppo viene cancellato un giorno dopo l'ultima attività, se non
  c'è nessuno collegato.
- **Boards**, una per tutte le classifiche: i circuiti per il centro della linea del via (due linee
  entro 150 m sono lo stesso circuito, un giro più lungo o più corto del 20% è un'altra
  configurazione) e per ognuno il giro migliore di ogni pilota con ogni tipo di GPS, con l'auto di
  quel giro.
- **Accounts**, uno per tutti: un nome utente (da 3 a 20 tra lettere, numeri, `.` `-` `_`, unico
  anche cambiando le maiuscole) e una password salvata come hash PBKDF2-SHA256 con sale.
  L'accesso dà al telefono un token, e del token si salva solo l'hash. Dieci password sbagliate in
  15 minuti bloccano per un po' un nome o un indirizzo.
- **Garage**, uno per pilota che mostra le sue auto: fino a 20 auto con una foto JPEG ciascuna
  (fino a 1,5 MB), anno, potenza in CV, peso in kg, modifiche e note. Scrive solo il proprietario;
  leggono tutti, nell'app o alla pagina `/g/<codice>`. Le segnalazioni di tre persone diverse
  nascondono il garage finché l'amministratore non lo guarda.

I tempi li calcolano i telefoni: il server salva e inoltra e basta. Le chiamate e i messaggi sono
nelle tabelle sopra; le chiamate con account portano `Authorization: Bearer <token>`.

**Moderazione**: sul Worker va impostato il segreto `ADMIN_KEY` (Settings → Variables and
Secrets). Le segnalazioni compaiono nei log del Worker come `garage reported <codice>`. Con
l'intestazione `X-TrackLap-Admin: <chiave>`, `GET /v1/garages/<codice>` mostra un garage nascosto
con le segnalazioni, `POST /v1/garages/<codice>/restore` lo rimette visibile e
`DELETE /v1/garages/<codice>` lo cancella.

`npm test` prova gli oggetti e il worker con una copia in memoria del runtime dei Durable Object
(Node 22 o successivo, niente da installare). Cloudflare lo pubblica da questa cartella con
l'integrazione Git (Workers & Pages → il Worker `tracklap` → Settings → Build, cartella `server`) a
ogni push su `main`; l'app usa `https://tracklap.tbsgaming.win`, dominio personalizzato del Worker
(c'è anche `https://tracklap.theblackside243.workers.dev`).
