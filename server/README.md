# TrackLap server

English first, then Italian. / Prima in inglese, poi in italiano.

## English

The live groups and the online leaderboards of the TrackLap app, as one Cloudflare Worker with two
Durable Object classes ([`src/index.js`](src/index.js)). It runs on the Workers free plan.

- **Room**, one per group: the WebSockets of its members (they hibernate between messages, so an
  idle group costs nothing), their names and times. Positions are relayed, never stored. A group is
  deleted a day after the last activity with nobody connected.
- **Boards**, one for every leaderboard: the circuits by the middle of their start line (two lines
  within 150 m are the same circuit, a lap more than 20% longer or shorter is another layout), and
  for each one the best lap of every driver with each kind of GPS. Drivers are known by a secret id
  that never comes back in an answer.

The phones do all the timing: the server only stores and relays.

### API

| Call | What it does |
|---|---|
| `POST /v1/rooms` | a new group: `{"code":"K7P2Q"}` |
| `GET /v1/rooms/<code>/ws` | the group's WebSocket |
| `GET /v1/boards?lat=&lon=&len=` | the leaderboard of the circuit whose start line is there (`len` = a lap in metres, to pick the layout); header `X-TrackLap-Driver` marks your laps with `"mine":true` |
| `POST /v1/laps` | a lap for the leaderboard, header `X-TrackLap-Driver`: `{name, vehicle, source: "device"\|"phone", time, distance, sectors, date, track: {name, lat, lon}}` |

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

### Tests and deployment

`npm test` runs both objects against an in-memory stand-in for the Durable Object runtime (Node 22
or later, nothing to install).

Cloudflare deploys it from this folder through its Git integration (Workers & Pages → the `tracklap`
Worker → Settings → Build, root directory `server`), with `npx wrangler deploy` and the migrations
in [`wrangler.toml`](wrangler.toml). The app talks to `https://tracklap.tbsgaming.win`, a custom
domain on the Worker; `-server <url>` on the app's command line points it somewhere else.

## Italiano

I gruppi live e le classifiche online dell'app TrackLap, in un Cloudflare Worker con due classi di
Durable Object ([`src/index.js`](src/index.js)). Sta nel piano gratuito di Workers.

- **Room**, una per gruppo: le WebSocket dei membri (vanno in ibernazione tra un messaggio e
  l'altro, quindi un gruppo fermo non costa niente), i nomi e i tempi. Le posizioni passano e
  basta, non vengono salvate. Un gruppo viene cancellato un giorno dopo l'ultima attività, se non
  c'è nessuno collegato.
- **Boards**, una per tutte le classifiche: i circuiti per il centro della linea del via (due linee
  entro 150 m sono lo stesso circuito, un giro più lungo o più corto del 20% è un'altra
  configurazione) e per ognuno il giro migliore di ogni pilota con ogni tipo di GPS. I piloti sono
  riconosciuti da un id segreto che non torna mai indietro nelle risposte.

I tempi li calcolano i telefoni: il server salva e inoltra e basta. Le chiamate e i messaggi sono
nelle tabelle sopra.

`npm test` prova i due oggetti con una copia in memoria del runtime dei Durable Object (Node 22 o
successivo, niente da installare). Cloudflare lo pubblica da questa cartella con l'integrazione Git
(Workers & Pages → il Worker `tracklap` → Settings → Build, cartella `server`); l'app usa
`https://tracklap.tbsgaming.win`, dominio personalizzato del Worker.
