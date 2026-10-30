// TrackLap server: live groups and per-track leaderboards for the TrackLap app, on Cloudflare
// Workers with Durable Objects. One Room per group, holding the WebSockets of its members (they
// hibernate between messages), and one Boards object for every leaderboard. The phones do all the
// timing: the server only keeps who is in a group with their times, relays positions and laps, and
// stores the best lap of each driver on each track.

const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const CODE = /^[A-HJ-NP-Z2-9]{5}$/;
const ID = /^[A-Za-z0-9-]{8,40}$/;
const ROOM_TTL = 24 * 3600 * 1000;
const MAX_MEMBERS = 30;
const MAX_MESSAGE = 4096;
const SOURCES = ['device', 'phone'];
// Two start lines this close are the same circuit; a lap this much longer or shorter is not one of it.
const SAME_TRACK_M = 150;
const LENGTH_TOLERANCE = 0.2;
const BOARD_SIZE = 100;
const SUBMITS_PER_HOUR = 60;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    try {
      if (path === '/') return json({ name: 'TrackLap', api: 1 });
      if (path === '/v1/rooms' && request.method === 'POST') return await createRoom(env);
      const room = path.match(/^\/v1\/rooms\/([^/]+)\/ws$/);
      if (room) {
        const code = room[1].toUpperCase();
        if (!CODE.test(code)) return json({ error: 'no such group' }, 404);
        return env.ROOMS.get(env.ROOMS.idFromName(code)).fetch(request);
      }
      if (path === '/v1/boards' || path === '/v1/laps') {
        return env.BOARDS.get(env.BOARDS.idFromName('boards')).fetch(request);
      }
      return json({ error: 'not found' }, 404);
    } catch (e) {
      console.error(e);
      return json({ error: 'server error' }, 500);
    }
  },
};

async function createRoom(env) {
  for (let i = 0; i < 6; i++) {
    const code = randomCode();
    const res = await env.ROOMS.get(env.ROOMS.idFromName(code)).fetch('https://room/init', { method: 'POST' });
    if (res.status === 201) return json({ code }, 201);
  }
  return json({ error: 'busy' }, 503);
}

/// A live group. Members say hello with their name, track and times, then send their position about
/// once a second and each lap they finish; everyone else gets them as they come. Positions are only
/// relayed, never stored. The group is deleted after a day with nobody in it.
export class Room {
  constructor(state) {
    this.state = state;
    this.positions = new Map();
    // Keep-alives answered without waking the object.
    state.setWebSocketAutoResponse(new WebSocketRequestResponsePair('{"t":"ping"}', '{"t":"pong"}'));
  }

  async fetch(request) {
    const url = new URL(request.url);
    const storage = this.state.storage;
    if (url.pathname === '/init') {
      if (await storage.get('created')) return new Response(null, { status: 409 });
      const now = Date.now();
      await storage.put({ created: now, active: now, members: {} });
      await storage.setAlarm(now + ROOM_TTL);
      return new Response(null, { status: 201 });
    }
    if (request.headers.get('Upgrade') !== 'websocket') return json({ error: 'websocket only' }, 426);
    if (!(await storage.get('created'))) return json({ error: 'no such group' }, 404);
    if (this.state.getWebSockets().length >= MAX_MEMBERS * 2) return json({ error: 'group full' }, 429);
    const [client, server] = Object.values(new WebSocketPair());
    this.state.acceptWebSocket(server);
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, data) {
    if (typeof data !== 'string' || data.length > MAX_MESSAGE) return;
    let m;
    try {
      m = JSON.parse(data);
    } catch {
      return;
    }
    if (!m || typeof m !== 'object') return;
    if (m.t === 'hello') return this.hello(ws, m);
    const id = ws.deserializeAttachment()?.id;
    if (!id) return;
    if (m.t === 'pos') {
      const p = cleanPos(m);
      if (!p) return;
      p.id = id;
      this.positions.set(id, p);
      this.broadcast(p, ws);
    } else if (m.t === 'lap') {
      await this.lap(ws, id, m);
    }
  }

  async hello(ws, m) {
    const id = clean(m.id, ID);
    if (!id) return ws.close(4000, 'bad hello');
    const storage = this.state.storage;
    const members = (await storage.get('members')) || {};
    if (!members[id] && Object.keys(members).length >= MAX_MEMBERS) return ws.close(4029, 'group full');
    const old = members[id] || {};
    // The phone knows its own times best: what it says now replaces what was kept.
    const member = {
      id,
      name: text(m.name) || 'Driver',
      vehicle: text(m.vehicle),
      track: cleanTrack(m.track),
      best: time(m.best),
      last: time(m.last),
      laps: count(m.laps),
      joined: old.joined || Date.now(),
    };
    members[id] = member;
    ws.serializeAttachment({ id });
    await storage.put({ members, active: Date.now() });
    const all = Object.values(members).map(x => this.view(x));
    ws.send(JSON.stringify({ t: 'state', you: id, members: all, positions: [...this.positions.values()] }));
    this.broadcast({ t: 'member', member: this.view(member) }, ws);
  }

  async lap(ws, id, m) {
    const t = time(m.time);
    if (t === null) return;
    const storage = this.state.storage;
    const members = (await storage.get('members')) || {};
    const member = members[id];
    if (!member) return;
    member.last = t;
    member.best = member.best == null || t < member.best ? t : member.best;
    member.laps = Math.min(9999, (member.laps || 0) + 1);
    await storage.put({ members, active: Date.now() });
    this.broadcast({ t: 'lap', id, n: count(m.n), time: t, best: member.best, last: member.last, laps: member.laps }, ws);
  }

  async webSocketClose(ws) {
    await this.left(ws);
    try {
      ws.close(1000, 'bye');
    } catch {}
  }

  async webSocketError(ws) {
    await this.left(ws);
  }

  async left(ws) {
    const id = ws.deserializeAttachment()?.id;
    if (!id || this.online(id, ws)) return;
    this.positions.delete(id);
    const members = (await this.state.storage.get('members')) || {};
    if (members[id]) this.broadcast({ t: 'member', member: { ...this.view(members[id]), online: false } }, ws);
  }

  async alarm() {
    const storage = this.state.storage;
    const active = (await storage.get('active')) || 0;
    if (this.state.getWebSockets().length || Date.now() - active < ROOM_TTL) {
      await storage.setAlarm(Math.max(Date.now(), active) + ROOM_TTL);
      return;
    }
    await storage.deleteAll();
  }

  /// Another connection of the same member is still open (a phone that reconnected).
  online(id, except) {
    return this.state.getWebSockets().some(w => w !== except && w.deserializeAttachment()?.id === id);
  }

  view(m) {
    const { joined, ...rest } = m;
    return { ...rest, online: this.online(m.id) };
  }

  broadcast(msg, except) {
    const s = JSON.stringify(msg);
    for (const w of this.state.getWebSockets()) {
      if (w === except || !w.deserializeAttachment()?.id) continue;
      try {
        w.send(s);
      } catch {}
    }
  }
}

/// Every leaderboard: the circuits by their start line, and for each one the best lap of every
/// driver with each kind of GPS (the ESP32 at 10 Hz and the iPhone at 1 Hz are not mixed up).
export class Boards {
  constructor(state) {
    this.state = state;
    this.submits = new Map();
  }

  async fetch(request) {
    const url = new URL(request.url);
    const driver = clean(request.headers.get('X-TrackLap-Driver'), ID);
    if (url.pathname === '/v1/laps' && request.method === 'POST') {
      const body = await request.json().catch(() => null);
      return this.submit(body, driver, request.headers.get('CF-Connecting-IP') || '');
    }
    if (url.pathname === '/v1/boards' && request.method === 'GET') {
      const q = url.searchParams;
      const track = await this.find(+q.get('lat'), +q.get('lon'), +q.get('len') || 0);
      if (!track) return json({ track: null, laps: [] });
      return json(await this.board(track, driver));
    }
    return json({ error: 'not found' }, 404);
  }

  async submit(b, driver, ip) {
    if (!driver) return json({ error: 'who are you?' }, 400);
    if (!b || typeof b !== 'object') return json({ error: 'bad lap' }, 400);
    const t = time(b.time);
    const distance = +b.distance;
    const track = cleanTrack(b.track);
    if (t === null || !SOURCES.includes(b.source) || !track || !(distance >= 100 && distance <= 30000)) {
      return json({ error: 'bad lap' }, 400);
    }
    if (!this.allow(ip)) return json({ error: 'too many laps' }, 429);

    const storage = this.state.storage;
    // A lap much longer or shorter than the others from the same line is another layout, with a
    // board of its own (and so is a shortcut, with nobody to beat).
    let found = await this.find(track.lat, track.lon, distance);
    if (!found) {
      found = { id: crypto.randomUUID(), name: track.name, lat: track.lat, lon: track.lon, length: Math.round(distance) };
      const tracks = (await storage.get('tracks')) || [];
      tracks.push(found);
      await storage.put('tracks', tracks);
    }
    const key = 'board:' + found.id;
    const entries = (await storage.get(key)) || [];
    const i = entries.findIndex(e => e.driver === driver && e.source === b.source);
    const entry = {
      driver,
      name: text(b.name) || 'Driver',
      vehicle: text(b.vehicle),
      source: b.source,
      time: t,
      sectors: Array.isArray(b.sectors) ? b.sectors.slice(0, 8).map(time).filter(x => x !== null) : [],
      date: Number.isFinite(+b.date) ? Math.round(+b.date) : Date.now(),
    };
    if (i < 0) entries.push(entry);
    else if (t < entries[i].time) entries[i] = entry;
    else Object.assign(entries[i], { name: entry.name, vehicle: entry.vehicle });
    entries.sort((x, y) => x.time - y.time);
    await storage.put(key, entries.slice(0, 1000));
    const same = entries.filter(e => e.source === b.source);
    return json({ track: { id: found.id, name: found.name }, rank: same.findIndex(e => e.driver === driver) + 1, of: same.length });
  }

  async board(track, driver) {
    const entries = (await this.state.storage.get('board:' + track.id)) || [];
    const ranks = {};
    const laps = entries.map(e => {
      ranks[e.source] = (ranks[e.source] || 0) + 1;
      return { rank: ranks[e.source], name: e.name, vehicle: e.vehicle, source: e.source, time: e.time, date: e.date, mine: e.driver === driver };
    });
    const shown = laps.filter(e => e.rank <= BOARD_SIZE || e.mine);
    return { track: { id: track.id, name: track.name, length: track.length }, laps: shown };
  }

  /// The circuit whose start line is nearest, within 150 m, and as long as the lap when given.
  async find(lat, lon, length) {
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null;
    const tracks = (await this.state.storage.get('tracks')) || [];
    let best = null;
    for (const t of tracks) {
      const d = distance(lat, lon, t.lat, t.lon);
      if (d > SAME_TRACK_M) continue;
      if (length && Math.abs(length - t.length) > t.length * LENGTH_TOLERANCE) continue;
      if (!best || d < best.d) best = { d, t };
    }
    return best ? best.t : null;
  }

  allow(ip) {
    const now = Date.now();
    const recent = (this.submits.get(ip) || []).filter(t => now - t < 3600 * 1000);
    if (recent.length >= SUBMITS_PER_HOUR) return false;
    recent.push(now);
    this.submits.set(ip, recent);
    return true;
  }
}

// MARK: - Helpers

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

function randomCode() {
  const bytes = crypto.getRandomValues(new Uint8Array(5));
  return [...bytes].map(b => CODE_CHARS[b % CODE_CHARS.length]).join('');
}

function clean(s, re) {
  return typeof s === 'string' && re.test(s) ? s : null;
}

/// A name or a vehicle: printable, at most 24 characters.
function text(s) {
  if (typeof s !== 'string') return '';
  return [...s.replace(/[\u0000-\u001f\u007f]/g, '').trim()].slice(0, 24).join('');
}

/// A lap time in seconds, or null.
function time(x) {
  const t = +x;
  return x !== null && x !== undefined && Number.isFinite(t) && t >= 5 && t <= 3600 ? Math.round(t * 1000) / 1000 : null;
}

function count(x) {
  const n = Math.floor(+x);
  return Number.isFinite(n) && n >= 0 ? Math.min(n, 9999) : 0;
}

function coord(lat, lon) {
  return Number.isFinite(lat) && Number.isFinite(lon) && Math.abs(lat) <= 90 && Math.abs(lon) <= 180;
}

/// The track a member is on: its name and the middle of its start line.
function cleanTrack(t) {
  if (!t || typeof t !== 'object' || !coord(+t.lat, +t.lon)) return null;
  return { name: text(t.name) || 'Track', lat: +t.lat, lon: +t.lon };
}

function cleanPos(m) {
  const lat = +m.lat, lon = +m.lon, d = +m.d, v = +m.v, g = +m.g;
  if (!coord(lat, lon) || !Number.isFinite(d) || !Number.isFinite(v) || !Number.isFinite(g)) return null;
  return { t: 'pos', lat, lon, lap: count(m.lap), d: Math.max(-1, Math.min(d, 100000)), v: Math.max(0, Math.min(v, 150)), g };
}

function distance(lat1, lon1, lat2, lon2) {
  const r = 6371000, rad = Math.PI / 180;
  const dLat = (lat2 - lat1) * rad, dLon = (lon2 - lon1) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dLon / 2) ** 2;
  return 2 * r * Math.asin(Math.min(1, Math.sqrt(h)));
}
