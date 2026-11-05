// TrackLap server: live groups, per-track leaderboards, accounts, friends and garages for the
// TrackLap app, on Cloudflare Workers with Durable Objects. One Room per group, holding the
// WebSockets of its members (they hibernate between messages); one Boards object for every
// leaderboard; one Accounts object with the drivers who signed in and who their friends are; one
// Garage per driver who shows their cars. The phones do all the timing: the server only keeps who is
// in a group with their times, relays positions and laps, stores the best lap of each driver on each
// track, and the cars they show.

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
// Accounts: a name that is also the one on the leaderboards, and a password.
const USERNAME = /^[A-Za-z0-9_.-]{3,20}$/;
const MIN_PASSWORD = 8;
const MAX_PASSWORD = 200;
const PBKDF2_ROUNDS = 100000;
const MAX_TOKENS = 20;
const LOGIN_FAILURES = 10;
const SIGNUPS_PER_HOUR = 10;
// Garages: the cars a driver shows to everyone, at a public eight-letter code.
const GARAGE = /^[A-HJ-NP-Z2-9]{8}$/;
const MAX_CARS = 20;
const MAX_MODS = 40;
const MAX_PHOTO = 1536 * 1024;
const MAX_GARAGE_JSON = 64 * 1024;
// Reports from this many different people hide a garage until it is looked at.
const REPORTS_TO_HIDE = 3;
// Friends: an invitation link, good for a week, makes two drivers friends both ways. Friends see
// each other's garage (also one shown to friends only), their best laps and a few numbers.
const INVITE = /^[A-HJ-NP-Z2-9]{8}$/;
const INVITE_TTL = 7 * 24 * 3600 * 1000;
const MAX_FRIENDS = 200;
const AUDIENCES = ['all', 'friends'];
const INTERNAL = /^x-tracklap-(account|name|garage|car|car-name|is-admin|admin|friend)$/i;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    try {
      if (path === '/') return json({ name: 'TrackLap', api: 2 });
      if (path === '/v1/rooms' && request.method === 'POST') return await createRoom(env);
      const room = path.match(/^\/v1\/rooms\/([^/]+)\/ws$/);
      if (room) {
        const code = room[1].toUpperCase();
        if (!CODE.test(code)) return json({ error: 'no such group' }, 404);
        return env.ROOMS.get(env.ROOMS.idFromName(code)).fetch(request);
      }
      if (path === '/v1/me' && request.method === 'DELETE') return await deleteAccount(request, env);
      if (path === '/v1/me/garage' && request.method === 'POST') return await openGarage(request, env);
      if (path === '/v1/me/invite' || path === '/v1/friends' || /^\/v1\/invites\/[^/]+$/.test(path)) {
        return await accounts(env).fetch(await inward(request));
      }
      const friend = path.match(/^\/v1\/friends\/([^/]+)$/);
      if (friend) return await friendRoute(request, env, friend[1]);
      if (path === '/v1/accounts' || path === '/v1/sessions' || path === '/v1/me' || path === '/v1/me/password') {
        return await accounts(env).fetch(await inward(request));
      }
      if (path === '/v1/laps' || path === '/v1/boards') return await boards(request, env);
      const garage = path.match(/^\/v1\/garages\/([^/]+)(\/.*)?$/);
      if (garage) {
        const code = garage[1].toUpperCase();
        if (!GARAGE.test(code)) return json({ error: 'no such garage' }, 404);
        const account = await authenticate(request, env);
        return await garageRoute(request, env, code, account);
      }
      const page = path.match(/^\/g\/([^/]+)\/?$/);
      if (page) return await garagePage(page[1].toUpperCase(), request, env);
      const invite = path.match(/^\/f\/([^/]+)\/?$/);
      if (invite) return await invitePage(invite[1].toUpperCase(), request, env);
      return json({ error: 'not found' }, 404);
    } catch (e) {
      console.error(e);
      return json({ error: 'server error' }, 500);
    }
  },
};

const accounts = env => env.ACCOUNTS.get(env.ACCOUNTS.idFromName('accounts'));
const garages = (env, code) => env.GARAGES.get(env.GARAGES.idFromName(code));
const leaderboards = env => env.BOARDS.get(env.BOARDS.idFromName('boards'));

async function createRoom(env) {
  for (let i = 0; i < 6; i++) {
    const code = randomCode();
    const res = await env.ROOMS.get(env.ROOMS.idFromName(code)).fetch('https://room/init', { method: 'POST' });
    if (res.status === 201) return json({ code }, 201);
  }
  return json({ error: 'busy' }, 503);
}

/// A request passed on to an object. The headers the objects trust are taken off whatever came from
/// outside, and set only from what this worker checked (URI-encoded: a name can be any text).
async function inward(request, internal = {}) {
  const headers = new Headers();
  for (const [k, v] of request.headers) if (!INTERNAL.test(k)) headers.set(k, v);
  for (const [k, v] of Object.entries(internal)) if (v) headers.set(k, encodeURIComponent(v));
  const init = { method: request.method, headers };
  if (request.method !== 'GET' && request.method !== 'HEAD') init.body = await request.arrayBuffer();
  return new Request(request.url, init);
}

/// Who is asking: the account behind the token, and whether the admin key (a Worker secret,
/// ADMIN_KEY) came with the request.
function signedIn(account, env, request) {
  const key = request.headers.get('X-TrackLap-Admin');
  return {
    'X-TrackLap-Account': account?.id,
    'X-TrackLap-Name': account?.name,
    'X-TrackLap-Is-Admin': env.ADMIN_KEY && key && key === env.ADMIN_KEY ? '1' : '',
  };
}

/// The account of the token in the Authorization header ("Bearer <token>"), or null.
async function authenticate(request, env) {
  const auth = request.headers.get('Authorization') || '';
  if (!auth.startsWith('Bearer ')) return null;
  const res = await accounts(env).fetch(new Request('https://accounts/internal/verify', {
    method: 'POST',
    headers: { Authorization: auth },
  }));
  return res.ok ? res.json() : null;
}

async function boards(request, env) {
  const account = await authenticate(request, env);
  const internal = signedIn(account, env, request);
  if (request.method === 'POST') {
    if (!account) return json({ error: 'sign in first' }, 401);
    // The car comes from the driver's own garage, so a lap can only point at a car they show.
    const body = await request.clone().json().catch(() => null);
    const car = clean(body?.car, ID);
    if (account.garage && car) {
      const res = await garages(env, account.garage).fetch(new Request(`https://garage/v1/garages/${account.garage}`, {
        headers: { 'X-TrackLap-Account': encodeURIComponent(account.id) },
      }));
      const found = res.ok ? (await res.json()).cars.find(c => c.id === car) : null;
      if (found) Object.assign(internal, { 'X-TrackLap-Garage': account.garage, 'X-TrackLap-Car': car, 'X-TrackLap-Car-Name': found.name });
    }
  }
  return leaderboards(env).fetch(await inward(request, internal));
}

/// A garage call. A garage shown to friends only answers 403 to anyone else: when the one asking is
/// a friend of its owner, the call goes again saying so. The owner's id never leaves the worker.
async function garageRoute(request, env, code, account) {
  const internal = signedIn(account, env, request);
  const again = request.method === 'GET' ? request.clone() : null;
  const res = await garages(env, code).fetch(await inward(request, internal));
  if (res.status !== 403 || !again) return res;
  const refused = await res.json();
  if (refused.error !== 'friends only') return json(refused, 403);
  if (account && refused.owner && (await areFriends(env, account.id, refused.owner))) {
    return garages(env, code).fetch(await inward(again, { ...internal, 'X-TrackLap-Friend': '1' }));
  }
  return json({ error: 'friends only' }, 403);
}

async function areFriends(env, a, b) {
  const res = await accounts(env).fetch(new Request('https://accounts/internal/friends', {
    method: 'POST',
    body: JSON.stringify({ a, b }),
  }));
  return res.ok && (await res.json()).friends === true;
}

/// A friend: who they are (only if you are friends), their best lap on every track and a few
/// numbers from the leaderboards. DELETE ends the friendship, for both.
async function friendRoute(request, env, id) {
  const res = await accounts(env).fetch(await inward(request));
  if (!res.ok || request.method !== 'GET') return res;
  const friend = await res.json();
  const laps = await leaderboards(env).fetch(new Request('https://boards/internal/driver', {
    headers: { 'X-TrackLap-Account': encodeURIComponent(friend.id) },
  }));
  return json({ ...friend, ...(await laps.json()) });
}

/// Your garage: made the first time you show a car, then always the same code.
async function openGarage(request, env) {
  const account = await authenticate(request, env);
  if (!account) return json({ error: 'sign in first' }, 401);
  if (account.garage) return json({ code: account.garage });
  for (let i = 0; i < 6; i++) {
    const code = randomCode(8);
    const res = await garages(env, code).fetch(new Request('https://garage/init', {
      method: 'POST',
      body: JSON.stringify({ owner: account.id, name: account.name }),
    }));
    if (res.status !== 201) continue;
    await accounts(env).fetch(new Request('https://accounts/internal/garage', {
      method: 'POST',
      body: JSON.stringify({ id: account.id, code }),
    }));
    return json({ code }, 201);
  }
  return json({ error: 'busy' }, 503);
}

/// The account goes, and with it the garage, the friendships and every lap on the leaderboards.
async function deleteAccount(request, env) {
  const res = await accounts(env).fetch(await inward(request));
  if (!res.ok) return res;
  const gone = await res.json();
  if (gone.garage) {
    await garages(env, gone.garage).fetch(new Request(`https://garage/v1/garages/${gone.garage}`, {
      method: 'DELETE',
      headers: { 'X-TrackLap-Account': encodeURIComponent(gone.id) },
    }));
  }
  await leaderboards(env).fetch(new Request('https://boards/internal/forget', {
    method: 'POST',
    headers: { 'X-TrackLap-Account': encodeURIComponent(gone.id) },
  }));
  return json({ ok: true });
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
    // Set by the worker from the token: the account, its name and the car of the lap.
    const driver = header(request, 'X-TrackLap-Account') || null;
    if (url.pathname === '/internal/forget' && request.method === 'POST') return this.forget(driver);
    if (url.pathname === '/internal/driver') return json(await this.driver(driver));
    if (url.pathname === '/v1/laps' && request.method === 'POST') {
      const body = await request.json().catch(() => null);
      const who = {
        driver,
        name: header(request, 'X-TrackLap-Name'),
        garage: header(request, 'X-TrackLap-Garage'),
        car: header(request, 'X-TrackLap-Car'),
        vehicle: header(request, 'X-TrackLap-Car-Name'),
      };
      return this.submit(body, who, request.headers.get('CF-Connecting-IP') || '');
    }
    if (url.pathname === '/v1/boards' && request.method === 'GET') {
      const q = url.searchParams;
      const track = await this.find(+q.get('lat'), +q.get('lon'), +q.get('len') || 0);
      if (!track) return json({ track: null, laps: [] });
      return json(await this.board(track, driver));
    }
    return json({ error: 'not found' }, 404);
  }

  async submit(b, who, ip) {
    const driver = who.driver;
    if (!driver) return json({ error: 'sign in first' }, 401);
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
      name: text(who.name) || 'Driver',
      vehicle: longText(who.vehicle, 40),
      garage: clean(who.garage, GARAGE) || '',
      car: clean(who.car, ID) || '',
      source: b.source,
      time: t,
      sectors: Array.isArray(b.sectors) ? b.sectors.slice(0, 8).map(time).filter(x => x !== null) : [],
      date: Number.isFinite(+b.date) ? Math.round(+b.date) : Date.now(),
      // Every session sends its best lap: how many came, and when the last one was driven.
      sessions: 1,
    };
    entry.last = entry.date;
    if (i >= 0) {
      const old = entries[i];
      const seen = { sessions: (old.sessions || 1) + 1, last: Math.max(old.last || old.date, entry.date) };
      if (t < old.time) entries[i] = { ...entry, ...seen };
      else Object.assign(old, seen, { name: entry.name });
    } else {
      entries.push(entry);
    }
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
      return { rank: ranks[e.source], name: e.name, vehicle: e.vehicle, garage: e.garage || '', car: e.car || '', source: e.source, time: e.time, date: e.date, mine: e.driver === driver };
    });
    const shown = laps.filter(e => e.rank <= BOARD_SIZE || e.mine);
    return { track: { id: track.id, name: track.name, length: track.length }, laps: shown };
  }

  /// A driver's best lap on every track, with its place there, and a few numbers: how many tracks,
  /// sessions and first places, the track driven most and the last day on track.
  async driver(driver) {
    const laps = [];
    if (!driver) return { laps, stats: null };
    const storage = this.state.storage;
    for (const t of (await storage.get('tracks')) || []) {
      const entries = (await storage.get('board:' + t.id)) || [];
      for (const e of entries) {
        if (e.driver !== driver) continue;
        const same = entries.filter(x => x.source === e.source);
        laps.push({
          track: { id: t.id, name: t.name, length: t.length },
          source: e.source,
          time: e.time,
          sectors: e.sectors || [],
          date: e.date,
          last: e.last || e.date,
          sessions: e.sessions || 1,
          vehicle: e.vehicle || '',
          garage: e.garage || '',
          car: e.car || '',
          rank: same.indexOf(e) + 1,
          of: same.length,
        });
      }
    }
    laps.sort((a, b) => b.last - a.last);
    const byTrack = new Map();
    for (const l of laps) {
      const s = byTrack.get(l.track.id) || { name: l.track.name, sessions: 0, last: 0 };
      s.sessions += l.sessions;
      s.last = Math.max(s.last, l.last);
      byTrack.set(l.track.id, s);
    }
    const favourite = [...byTrack.values()].sort((a, b) => b.sessions - a.sessions || b.last - a.last)[0];
    return {
      laps,
      stats: {
        tracks: byTrack.size,
        sessions: laps.reduce((n, l) => n + l.sessions, 0),
        wins: laps.filter(l => l.rank === 1).length,
        favourite: favourite ? favourite.name : null,
        last: laps.length ? Math.max(...laps.map(l => l.last)) : null,
      },
    };
  }

  /// A deleted account: its laps leave every leaderboard.
  async forget(driver) {
    if (!driver) return json({ error: 'who?' }, 400);
    const storage = this.state.storage;
    for (const t of (await storage.get('tracks')) || []) {
      const key = 'board:' + t.id;
      const entries = (await storage.get(key)) || [];
      const kept = entries.filter(e => e.driver !== driver);
      if (kept.length !== entries.length) await storage.put(key, kept);
    }
    return json({ ok: true });
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

/// The drivers who signed in: a name, unique whatever its capitals, and a password kept as a salted
/// PBKDF2 hash. Signing in gives the phone a token; only its hash is stored, so the stored data
/// alone cannot be used to sign in.
export class Accounts {
  constructor(state) {
    this.state = state;
    this.failures = new Map();
    this.signups = new Map();
  }

  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;
    const ip = request.headers.get('CF-Connecting-IP') || '';
    if (path === '/internal/verify') {
      const found = await this.byToken(request);
      return found ? json(this.view(found.user)) : json({ error: 'signed out' }, 401);
    }
    if (path === '/internal/garage') {
      const b = await request.json();
      const user = await this.byID(b.id);
      if (!user) return json({ error: 'no such account' }, 404);
      user.garage = b.code;
      await this.state.storage.put('user:' + user.name.toLowerCase(), user);
      return json({ ok: true });
    }
    if (path === '/internal/friends') {
      const b = await request.json();
      const user = await this.byID(b.a);
      return json({ friends: !!user && (user.friends || []).some(f => f.id === b.b) });
    }
    const invited = path.match(/^\/v1\/invites\/([^/]+)$/);
    if (invited && method === 'GET') {
      const from = await this.invitation(invited[1]);
      return from ? json({ name: from.user.name, expires: from.expires }) : json({ error: 'no such invitation' }, 404);
    }
    if (path === '/v1/accounts' && method === 'POST') return this.signUp(await body(request), ip);
    if (path === '/v1/sessions' && method === 'POST') return this.signIn(await body(request), ip);
    const found = await this.byToken(request);
    if (!found) return json({ error: 'signed out' }, 401);
    const { user, hash } = found;
    if (path === '/v1/sessions' && method === 'DELETE') {
      user.tokens = user.tokens.filter(t => t !== hash);
      await this.state.storage.put('user:' + user.name.toLowerCase(), user);
      await this.state.storage.delete('token:' + hash);
      return json({ ok: true });
    }
    if (path === '/v1/me' && method === 'GET') return json(this.view(user));
    if (path === '/v1/me/password' && method === 'POST') {
      const b = await body(request);
      if (!(await this.check(user, b?.old))) return json({ error: 'wrong password' }, 403);
      if (!goodPassword(b?.new)) return json({ error: 'password too short' }, 400);
      Object.assign(user, await hashPassword(b.new));
      // Every other phone is signed out.
      await this.state.storage.delete(user.tokens.map(t => 'token:' + t));
      user.tokens = [];
      return json({ token: await this.issue(user), account: this.view(user) });
    }
    if (path === '/v1/me/invite' && method === 'POST') return this.invite(user, (await body(request))?.renew === true);
    if (path === '/v1/friends' && method === 'GET') return json({ friends: await this.friendsOf(user) });
    if (path === '/v1/friends' && method === 'POST') return this.accept(user, (await body(request))?.code);
    const friend = path.match(/^\/v1\/friends\/([^/]+)$/);
    if (friend) {
      const other = user.friends?.some(f => f.id === friend[1]) ? await this.byID(friend[1]) : null;
      if (!other) return json({ error: 'not a friend' }, 404);
      if (method === 'GET') return json(this.friendView(other, user));
      if (method === 'DELETE') {
        await this.unfriend(user, other);
        return json({ ok: true });
      }
    }
    if (path === '/v1/me' && method === 'DELETE') {
      const b = await body(request);
      if (!(await this.check(user, b?.password))) return json({ error: 'wrong password' }, 403);
      for (const f of user.friends || []) {
        const other = await this.byID(f.id);
        if (other) await this.unfriend(user, other);
      }
      if (user.invite) await this.state.storage.delete('invite:' + user.invite);
      await this.state.storage.delete([...user.tokens.map(t => 'token:' + t), 'user:' + user.name.toLowerCase(), 'id:' + user.id]);
      console.log('account deleted', user.name);
      return json({ id: user.id, garage: user.garage || null });
    }
    return json({ error: 'not found' }, 404);
  }

  async signUp(b, ip) {
    const name = typeof b?.username === 'string' ? b.username.trim() : '';
    if (!USERNAME.test(name)) return json({ error: 'bad username' }, 400);
    if (!goodPassword(b?.password)) return json({ error: 'password too short' }, 400);
    if (!this.count(this.signups, ip, SIGNUPS_PER_HOUR, 3600 * 1000)) return json({ error: 'too many accounts' }, 429);
    const key = 'user:' + name.toLowerCase();
    if (await this.state.storage.get(key)) return json({ error: 'username taken' }, 409);
    const user = { id: crypto.randomUUID(), name, created: Date.now(), garage: null, tokens: [], ...(await hashPassword(b.password)) };
    await this.state.storage.put({ [key]: user, ['id:' + user.id]: name.toLowerCase() });
    return json({ token: await this.issue(user), account: this.view(user) }, 201);
  }

  async signIn(b, ip) {
    const name = typeof b?.username === 'string' ? b.username.trim().toLowerCase() : '';
    const tries = 'ip:' + ip;
    const named = 'name:' + name;
    if (!this.allowed(tries) || !this.allowed(named)) return json({ error: 'too many attempts' }, 429);
    const user = USERNAME.test(name) ? await this.state.storage.get('user:' + name) : null;
    if (!user || !(await this.check(user, b?.password))) {
      this.fail(tries);
      this.fail(named);
      return json({ error: 'wrong username or password' }, 403);
    }
    this.failures.delete(named);
    return json({ token: await this.issue(user), account: this.view(user) });
  }

  /// A new token for a phone; the oldest go when there are too many.
  async issue(user) {
    const token = base64url(crypto.getRandomValues(new Uint8Array(32)));
    const hash = await sha256(token);
    user.tokens.push(hash);
    const dropped = user.tokens.length > MAX_TOKENS ? user.tokens.splice(0, user.tokens.length - MAX_TOKENS) : [];
    if (dropped.length) await this.state.storage.delete(dropped.map(t => 'token:' + t));
    await this.state.storage.put({ ['user:' + user.name.toLowerCase()]: user, ['token:' + hash]: user.name.toLowerCase() });
    return token;
  }

  async byToken(request) {
    const auth = request.headers.get('Authorization') || '';
    const token = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
    if (!/^[A-Za-z0-9_-]{20,100}$/.test(token)) return null;
    const hash = await sha256(token);
    const name = await this.state.storage.get('token:' + hash);
    const user = name ? await this.state.storage.get('user:' + name) : null;
    return user && user.tokens.includes(hash) ? { user, hash } : null;
  }

  async byID(id) {
    const name = typeof id === 'string' ? await this.state.storage.get('id:' + id) : null;
    return name ? this.state.storage.get('user:' + name) : null;
  }

  async check(user, password) {
    if (typeof password !== 'string' || password.length > MAX_PASSWORD) return false;
    const { hash } = await hashPassword(password, user.salt);
    return same(hash, user.hash);
  }

  view(user) {
    return { id: user.id, name: user.name, garage: user.garage || null };
  }

  /// Your invitation link's code: the same one for a week, so a link sent around keeps working; a
  /// new one when it has less than a day left, or when you ask (the old one stops working).
  async invite(user, renew) {
    const storage = this.state.storage;
    const current = user.invite ? await storage.get('invite:' + user.invite) : null;
    if (current && !renew && current.expires - Date.now() > 24 * 3600 * 1000) {
      return json({ code: user.invite, expires: current.expires });
    }
    for (let i = 0; i < 6; i++) {
      const code = randomCode(8);
      if (await storage.get('invite:' + code)) continue;
      const expires = Date.now() + INVITE_TTL;
      if (user.invite) await storage.delete('invite:' + user.invite);
      user.invite = code;
      await storage.put({ ['invite:' + code]: { id: user.id, expires }, ['user:' + user.name.toLowerCase()]: user });
      return json({ code, expires }, 201);
    }
    return json({ error: 'busy' }, 503);
  }

  /// Who an invitation is from, while it is good.
  async invitation(raw) {
    const code = typeof raw === 'string' ? raw.toUpperCase() : '';
    if (!INVITE.test(code)) return null;
    const inv = await this.state.storage.get('invite:' + code);
    if (!inv || inv.expires < Date.now()) return null;
    const user = await this.byID(inv.id);
    return user && user.invite === code ? { user, expires: inv.expires } : null;
  }

  /// An invitation accepted: friends both ways, from now.
  async accept(user, code) {
    const from = await this.invitation(code);
    if (!from) return json({ error: 'no such invitation' }, 404);
    const other = from.user;
    if (other.id === user.id) return json({ error: 'that is you' }, 409);
    user.friends ||= [];
    other.friends ||= [];
    if (user.friends.some(f => f.id === other.id)) return json(this.friendView(other, user));
    if (user.friends.length >= MAX_FRIENDS || other.friends.length >= MAX_FRIENDS) return json({ error: 'too many friends' }, 409);
    const since = Date.now();
    user.friends.push({ id: other.id, since });
    other.friends.push({ id: user.id, since });
    await this.state.storage.put({ ['user:' + user.name.toLowerCase()]: user, ['user:' + other.name.toLowerCase()]: other });
    return json(this.friendView(other, user), 201);
  }

  async unfriend(user, other) {
    user.friends = (user.friends || []).filter(f => f.id !== other.id);
    other.friends = (other.friends || []).filter(f => f.id !== user.id);
    await this.state.storage.put({ ['user:' + user.name.toLowerCase()]: user, ['user:' + other.name.toLowerCase()]: other });
  }

  /// Your friends by name; friends whose account went are dropped on the way.
  async friendsOf(user) {
    const out = [];
    for (const f of user.friends || []) {
      const other = await this.byID(f.id);
      if (other) out.push(this.friendView(other, user));
    }
    if (out.length !== (user.friends || []).length) {
      user.friends = user.friends.filter(f => out.some(o => o.id === f.id));
      await this.state.storage.put('user:' + user.name.toLowerCase(), user);
    }
    return out.sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));
  }

  friendView(other, user) {
    const since = (user.friends || []).find(f => f.id === other.id)?.since ?? null;
    return { ...this.view(other), since };
  }

  allowed(key) {
    const now = Date.now();
    const recent = (this.failures.get(key) || []).filter(t => now - t < 15 * 60 * 1000);
    this.failures.set(key, recent);
    return recent.length < LOGIN_FAILURES;
  }

  fail(key) {
    this.failures.set(key, [...(this.failures.get(key) || []), Date.now()]);
  }

  count(map, key, max, window) {
    const now = Date.now();
    const recent = (map.get(key) || []).filter(t => now - t < window);
    if (recent.length >= max) return false;
    recent.push(now);
    map.set(key, recent);
    return true;
  }
}

/// A driver's garage: the cars they show, each with one photo, the power, the weight, the
/// modifications and a few notes. Only its owner can change it. Shown to everyone, anyone can read
/// it, in the app or at /g/<code>; shown to friends only, the owner's friends (the worker says so)
/// and nobody else. A photo is read by its id, which only those who can read the garage get.
/// Reports from three different people hide it until the admin looks.
export class Garage {
  constructor(state) {
    this.state = state;
  }

  async fetch(request) {
    const url = new URL(request.url);
    const storage = this.state.storage;
    const method = request.method;
    if (url.pathname === '/init') {
      if (await storage.get('meta')) return new Response(null, { status: 409 });
      const b = await body(request);
      if (typeof b?.owner !== 'string') return new Response(null, { status: 400 });
      const now = Date.now();
      await storage.put({
        meta: { owner: b.owner, created: now, hidden: false, reports: {} },
        garage: { name: text(b.name), cars: [], updated: now },
        photos: [],
      });
      return new Response(null, { status: 201 });
    }
    const meta = await storage.get('meta');
    if (!meta) return json({ error: 'no such garage' }, 404);
    const m = url.pathname.match(/^\/v1\/garages\/([^/]+)(?:\/photos\/([^/]+)|\/(report|restore))?$/);
    if (!m) return json({ error: 'not found' }, 404);
    const code = m[1].toUpperCase();
    const account = header(request, 'X-TrackLap-Account');
    const mine = !!account && account === meta.owner;
    const admin = header(request, 'X-TrackLap-Is-Admin') === '1';
    const friend = header(request, 'X-TrackLap-Friend') === '1';
    const visible = !meta.hidden || mine || admin;

    if (m[2] !== undefined) {
      const id = clean(m[2], ID);
      if (!id) return json({ error: 'no such photo' }, 404);
      if (method === 'GET') {
        const bytes = visible ? await storage.get('photo:' + id) : null;
        if (!bytes) return json({ error: 'no such photo' }, 404);
        // A new photo always gets a new id, so a photo never changes at its address.
        return new Response(bytes, { headers: { 'Content-Type': 'image/jpeg', 'Cache-Control': 'public, max-age=31536000, immutable' } });
      }
      if (method === 'PUT') {
        if (!mine) return json({ error: 'not yours' }, 403);
        const garage = await storage.get('garage');
        if (!garage.cars.some(c => c.photo === id)) return json({ error: 'not in the garage' }, 409);
        const bytes = new Uint8Array(await request.arrayBuffer());
        if (bytes.length < 100 || bytes.length > MAX_PHOTO || bytes[0] !== 0xff || bytes[1] !== 0xd8) {
          return json({ error: 'a JPEG up to 1.5 MB' }, 400);
        }
        const photos = (await storage.get('photos')) || [];
        await storage.put({ ['photo:' + id]: bytes, photos: [...new Set([...photos, id])] });
        return json({ ok: true });
      }
      return json({ error: 'not found' }, 404);
    }

    if (m[3] === 'report' && method === 'POST') return this.report(request, meta, code);
    if (m[3] === 'restore' && method === 'POST') {
      if (!admin) return json({ error: 'not allowed' }, 403);
      await storage.put('meta', { ...meta, hidden: false, reports: {} });
      return json({ ok: true });
    }
    if (m[3]) return json({ error: 'not found' }, 404);

    if (method === 'GET') {
      if (!visible) return json({ error: 'hidden' }, 404);
      const garage = await storage.get('garage');
      const audience = garage.audience || 'all';
      // The worker asks again for a friend of the owner, and keeps the owner to itself.
      if (audience === 'friends' && !mine && !admin && !friend) return json({ error: 'friends only', owner: meta.owner }, 403);
      const photos = new Set((await storage.get('photos')) || []);
      const cars = garage.cars.map(c => ({ ...c, photo: photos.has(c.photo) ? c.photo : null }));
      const out = { code, name: garage.name, cars, updated: garage.updated, mine, audience };
      if (mine) out.missing = garage.cars.map(c => c.photo).filter(p => p && !photos.has(p));
      if (mine || admin) out.hidden = meta.hidden;
      if (admin) out.reports = Object.values(meta.reports || {});
      return json(out);
    }
    if (method === 'PUT') {
      if (!mine) return json({ error: 'not yours' }, 403);
      const raw = await request.text();
      if (raw.length > MAX_GARAGE_JSON) return json({ error: 'too big' }, 413);
      let b;
      try {
        b = JSON.parse(raw);
      } catch {
        return json({ error: 'bad garage' }, 400);
      }
      const garage = cleanGarage(b, decodeURIComponent(request.headers.get('X-TrackLap-Name') || ''));
      if (!garage) return json({ error: 'bad garage' }, 400);
      // Photos of cars that went, or that changed photo, are deleted now.
      const stored = (await storage.get('photos')) || [];
      const wanted = new Set(garage.cars.map(c => c.photo).filter(Boolean));
      const gone = stored.filter(id => !wanted.has(id));
      if (gone.length) await storage.delete(gone.map(id => 'photo:' + id));
      const kept = stored.filter(id => wanted.has(id));
      await storage.put({ garage, photos: kept });
      return json({ code, missing: [...wanted].filter(id => !kept.includes(id)) });
    }
    if (method === 'DELETE') {
      if (!mine && !admin) return json({ error: 'not yours' }, 403);
      await storage.deleteAll();
      console.log('garage deleted', code, admin ? 'by the admin' : 'by its owner');
      return json({ ok: true });
    }
    return json({ error: 'not found' }, 404);
  }

  async report(request, meta, code) {
    const b = await body(request);
    const reason = longText(b?.reason, 200);
    const who = (await sha256('report:' + (request.headers.get('CF-Connecting-IP') || ''))).slice(0, 16);
    const reports = meta.reports || {};
    if (Object.keys(reports).length < 50) reports[who] = { reason, car: clean(b?.car, ID), at: Date.now() };
    const n = Object.keys(reports).length;
    const hidden = meta.hidden || n >= REPORTS_TO_HIDE;
    await this.state.storage.put('meta', { ...meta, reports, hidden });
    console.warn('garage reported', code, n, hidden ? 'now hidden' : '', reason);
    return json({ ok: true });
  }
}

/// The page of a garage at /g/<code>, for anyone with the link: the photos in a grid, and a car's
/// photo with what was done to it when it is tapped. In Italian for an Italian browser, otherwise
/// in English. The link previews in chats show the first photo.
async function garagePage(code, request, env) {
  const lang = /^it\b/i.test(request.headers.get('Accept-Language') || '') ? 'it' : 'en';
  const t = PAGE_TEXT[lang];
  const origin = new URL(request.url).origin;
  let g = null;
  let friendsOnly = false;
  if (GARAGE.test(code)) {
    const res = await garages(env, code).fetch(new Request(`${origin}/v1/garages/${code}`));
    if (res.ok) g = await res.json();
    friendsOnly = res.status === 403;
  }
  if (friendsOnly) {
    return html(pageShell(lang, t.friendsOnlyTitle, `<main class="empty"><h1>${esc(t.friendsOnlyTitle)}</h1><p>${esc(t.friendsOnly)}</p><p><a class="open" href="tracklap://garage/${code}">${esc(t.open)}</a></p></main>`, ''), 403);
  }
  if (!g) return html(pageShell(lang, t.missingTitle, `<main class="empty"><h1>${esc(t.missingTitle)}</h1><p>${esc(t.missing)}</p></main>`, ''), 404);

  const title = t.title(g.name || 'TrackLap');
  const photo = id => `${origin}/v1/garages/${code}/photos/${id}`;
  const first = g.cars.find(c => c.photo);
  const power = c => (c.power ? (lang === 'it' ? `${c.power} CV` : `${Math.round(c.power * 0.98632)} hp`) : '');
  const cards = g.cars.map(c => `
    <button class="card" data-car="${esc(c.id)}">
      ${c.photo ? `<img src="${esc(photo(c.photo))}" alt="" loading="lazy">` : `<div class="noimg">${CAR_ICON}</div>`}
      <span class="name">${esc(c.name)}</span>
      <span class="sub">${esc([c.year, power(c)].filter(Boolean).join(' · '))}</span>
    </button>`).join('');
  const cars = g.cars.map(c => ({ ...c, photo: c.photo ? photo(c.photo) : null, powerText: power(c) }));
  const meta = [
    `<meta property="og:title" content="${esc(title)}">`,
    `<meta property="og:description" content="${esc(t.cars(g.cars.length))}">`,
    first ? `<meta property="og:image" content="${esc(photo(first.photo))}">` : '',
    `<meta name="twitter:card" content="${first ? 'summary_large_image' : 'summary'}">`,
  ].join('\n');
  const body = `
<header>
  <p class="kicker">TrackLap</p>
  <h1>${esc(title)}</h1>
  <p class="count">${esc(t.cars(g.cars.length))}</p>
</header>
<main>
  ${g.cars.length ? `<div class="grid">${cards}</div>` : `<p class="empty">${esc(t.noCars)}</p>`}
</main>
<footer>
  <a class="open" href="tracklap://garage/${code}">${esc(t.open)}</a>
  <button class="report" type="button">${esc(t.report)}</button>
</footer>
<dialog id="car">
  <form method="dialog"><button class="close" aria-label="${esc(t.close)}">×</button></form>
  <div id="photo"></div>
  <h2 id="carName"></h2>
  <div id="specs" class="specs"></div>
  <h3 id="modsTitle">${esc(t.mods)}</h3>
  <ul id="mods"></ul>
  <p id="notes"></p>
</dialog>
<script type="application/json" id="data">${JSON.stringify({ cars, code, t: { reportAsk: t.reportAsk, reported: t.reported, year: t.year, weight: t.weight, ratio: t.ratio, power: t.power } }).replace(/</g, '\\u003c')}</script>
<script>${PAGE_SCRIPT}</script>`;
  return html(pageShell(lang, title, body, meta));
}

const PAGE_TEXT = {
  it: {
    title: n => `Il garage di ${n}`,
    cars: n => (n === 1 ? '1 auto' : `${n} auto`),
    noCars: 'Ancora nessuna auto in questo garage.',
    open: 'Apri in TrackLap',
    report: 'Segnala',
    reportAsk: 'Perché segnali questo garage? (foto o testi inadatti, non è suo…)',
    reported: 'Grazie: lo controlliamo.',
    mods: 'Modifiche',
    close: 'Chiudi',
    year: 'Anno',
    power: 'Potenza',
    weight: 'Peso',
    ratio: 'kg/CV',
    missingTitle: 'Garage non trovato',
    missing: 'Il link non è giusto, oppure il garage è stato tolto.',
    friendsOnlyTitle: 'Garage solo per gli amici',
    friendsOnly: 'Questo pilota mostra il garage solo ai suoi amici su TrackLap.',
    inviteTitle: n => `${n} ti invita su TrackLap`,
    invite: 'Diventate amici: vedrete i vostri garage, i giri migliori su ogni pista e le statistiche.',
    inviteOpen: "Accetta nell'app",
    inviteApp: "Serve l'app TrackLap, su iPhone o su Android: aprila e accedi con il tuo account.",
    inviteGoneTitle: 'Invito scaduto',
    inviteGone: 'Questo invito non vale più: chiedine uno nuovo a chi te lo ha mandato.',
  },
  en: {
    title: n => `${n}'s garage`,
    cars: n => (n === 1 ? '1 car' : `${n} cars`),
    noCars: 'No cars in this garage yet.',
    open: 'Open in TrackLap',
    report: 'Report',
    reportAsk: 'Why are you reporting this garage? (unsuitable photos or text, not theirs…)',
    reported: 'Thanks: we will look at it.',
    mods: 'Modifications',
    close: 'Close',
    year: 'Year',
    power: 'Power',
    weight: 'Weight',
    ratio: 'kg/hp',
    missingTitle: 'Garage not found',
    missing: 'The link is wrong, or the garage was taken down.',
    friendsOnlyTitle: 'Garage for friends only',
    friendsOnly: 'This driver shows their garage to their TrackLap friends only.',
    inviteTitle: n => `${n} invites you to TrackLap`,
    invite: "Become friends: you will see each other's garage, best lap on every track and numbers.",
    inviteOpen: 'Accept in the app',
    inviteApp: 'You need the TrackLap app, on iPhone or Android: open it and sign in with your account.',
    inviteGoneTitle: 'Invitation expired',
    inviteGone: 'This invitation is no longer good: ask whoever sent it for a new one.',
  },
};

/// The page of a friend invitation at /f/<code>: who it is from, and the button that opens the app
/// on it. Chats show the title in their preview.
async function invitePage(code, request, env) {
  const lang = /^it\b/i.test(request.headers.get('Accept-Language') || '') ? 'it' : 'en';
  const t = PAGE_TEXT[lang];
  const res = INVITE.test(code) ? await accounts(env).fetch(new Request(`https://accounts/v1/invites/${code}`)) : null;
  if (!res?.ok) {
    return html(pageShell(lang, t.inviteGoneTitle, `<main class="empty"><h1>${esc(t.inviteGoneTitle)}</h1><p>${esc(t.inviteGone)}</p></main>`, ''), 404);
  }
  const { name } = await res.json();
  const title = t.inviteTitle(name);
  const meta = [
    `<meta property="og:title" content="${esc(title)}">`,
    `<meta property="og:description" content="${esc(t.invite)}">`,
    '<meta name="twitter:card" content="summary">',
  ].join('\n');
  const body = `
<main class="empty">
  <p class="kicker">TrackLap</p>
  <h1>${esc(title)}</h1>
  <p>${esc(t.invite)}</p>
  <p><a class="open" href="tracklap://friend/${code}">${esc(t.inviteOpen)}</a></p>
  <p class="count">${esc(t.inviteApp)}</p>
</main>`;
  return html(pageShell(lang, title, body, meta));
}

const CAR_ICON = '<svg viewBox="0 0 24 24" width="40" height="40" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M5 17h-1a1 1 0 0 1-1-1v-3.5l2-5A2 2 0 0 1 6.9 6h10.2a2 2 0 0 1 1.9 1.5l2 5V16a1 1 0 0 1-1 1h-1"/><circle cx="7.5" cy="17" r="2"/><circle cx="16.5" cy="17" r="2"/><path d="M9.5 17h5M3 12.5h18"/></svg>';

const PAGE_SCRIPT = `
const data = JSON.parse(document.getElementById('data').textContent);
const dialog = document.getElementById('car');
const el = id => document.getElementById(id);
function show(id) {
  const c = data.cars.find(x => x.id === id);
  if (!c) return;
  el('photo').innerHTML = '';
  if (c.photo) { const img = new Image(); img.src = c.photo; img.alt = ''; el('photo').append(img); }
  el('carName').textContent = c.name;
  const specs = [[data.t.year, c.year], [data.t.power, c.powerText], [data.t.weight, c.weight ? c.weight + ' kg' : '']];
  if (c.power && c.weight) specs.push([data.t.ratio, (c.weight / c.power).toFixed(2)]);
  el('specs').innerHTML = '';
  for (const [k, v] of specs) {
    if (!v) continue;
    const d = document.createElement('div');
    const a = document.createElement('span'); a.textContent = k;
    const b = document.createElement('strong'); b.textContent = v;
    d.append(a, b); el('specs').append(d);
  }
  el('mods').innerHTML = '';
  for (const m of c.mods) { const li = document.createElement('li'); li.textContent = m; el('mods').append(li); }
  el('modsTitle').hidden = !c.mods.length;
  el('notes').textContent = c.notes || '';
  history.replaceState(null, '', '#' + c.id);
  dialog.showModal();
}
document.querySelectorAll('.card').forEach(b => b.addEventListener('click', () => show(b.dataset.car)));
dialog.addEventListener('close', () => history.replaceState(null, '', location.pathname));
dialog.addEventListener('click', e => { if (e.target === dialog) dialog.close(); });
if (location.hash) show(location.hash.slice(1));
document.querySelector('.report').addEventListener('click', async e => {
  const reason = prompt(data.t.reportAsk);
  if (reason === null) return;
  await fetch('/v1/garages/' + data.code + '/report', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ reason }) });
  e.target.textContent = data.t.reported;
  e.target.disabled = true;
});
`;

function pageShell(lang, title, body, meta) {
  return `<!doctype html>
<html lang="${lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
${meta}
<style>
:root { --bg: #0f0f11; --panel: #1c1c20; --line: #34343c; --text: #f2f2f6; --sub: #9696a2; --accent: #22d3ee; color-scheme: dark; }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text); font: 16px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
header, main, footer { max-width: 1100px; margin: 0 auto; padding: 0 16px; }
header { padding-top: 40px; padding-bottom: 20px; }
.kicker { margin: 0 0 4px; color: var(--accent); font-weight: 800; letter-spacing: .12em; text-transform: uppercase; font-size: 13px; }
h1 { margin: 0; font-size: 30px; line-height: 1.15; }
.count { margin: 6px 0 0; color: var(--sub); }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); gap: 12px; }
.card { display: flex; flex-direction: column; text-align: left; padding: 0; border: 1px solid var(--line); border-radius: 16px; background: var(--panel); color: inherit; font: inherit; overflow: hidden; cursor: pointer; }
.card:hover, .card:focus-visible { border-color: var(--accent); outline: none; }
.card img, .noimg { width: 100%; aspect-ratio: 4 / 3; object-fit: cover; display: block; }
.noimg { display: grid; place-items: center; color: var(--sub); background: #26262c; }
.name { padding: 10px 12px 0; font-weight: 700; }
.sub { padding: 2px 12px 12px; color: var(--sub); font-size: 14px; min-height: 1.4em; }
footer { display: flex; gap: 12px; align-items: center; justify-content: space-between; padding-top: 32px; padding-bottom: 40px; }
.open { display: inline-block; padding: 12px 18px; border-radius: 14px; background: var(--accent); color: #000; font-weight: 800; text-decoration: none; }
.report { background: none; border: 0; color: var(--sub); font: inherit; font-size: 14px; cursor: pointer; text-decoration: underline; }
.empty { color: var(--sub); }
main.empty { padding-top: 80px; text-align: center; }
dialog { width: min(720px, calc(100vw - 32px)); max-height: calc(100vh - 32px); padding: 0 0 20px; border: 1px solid var(--line); border-radius: 20px; background: var(--panel); color: var(--text); }
dialog::backdrop { background: rgba(0, 0, 0, .7); }
dialog form { position: sticky; top: 0; height: 0; text-align: right; z-index: 1; }
.close { margin: 10px; width: 36px; height: 36px; border-radius: 18px; border: 0; background: rgba(0, 0, 0, .6); color: #fff; font-size: 22px; line-height: 1; cursor: pointer; }
#photo img { width: 100%; display: block; }
dialog h2, dialog h3, dialog ul, dialog p, .specs { margin-left: 20px; margin-right: 20px; }
dialog h2 { margin-top: 16px; margin-bottom: 12px; font-size: 24px; }
dialog h3 { margin-top: 20px; margin-bottom: 6px; font-size: 13px; color: var(--sub); text-transform: uppercase; letter-spacing: .1em; }
.specs { display: grid; grid-template-columns: repeat(auto-fit, minmax(110px, 1fr)); gap: 8px; }
.specs div { padding: 10px 12px; border: 1px solid var(--line); border-radius: 12px; }
.specs span { display: block; color: var(--sub); font-size: 12px; }
.specs strong { font-size: 18px; font-variant-numeric: tabular-nums; }
#mods { padding-left: 20px; }
#mods li { margin: 4px 0; }
#notes { color: var(--sub); white-space: pre-line; }
</style>
</head>
<body>
${body}
</body>
</html>`;
}

// MARK: - Helpers

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

function randomCode(length = 5) {
  const bytes = crypto.getRandomValues(new Uint8Array(length));
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

async function body(request) {
  return request.json().catch(() => null);
}

/// A header set by the worker (URI-encoded), or ''.
function header(request, name) {
  const v = request.headers.get(name);
  if (!v) return '';
  try {
    return decodeURIComponent(v);
  } catch {
    return '';
  }
}

function goodPassword(p) {
  return typeof p === 'string' && p.length >= MIN_PASSWORD && p.length <= MAX_PASSWORD;
}

/// A password as a PBKDF2-SHA256 hash with a random salt (or the stored one, to check it).
async function hashPassword(password, saltHex) {
  const salt = saltHex ? Uint8Array.from(saltHex.match(/../g).map(h => parseInt(h, 16))) : crypto.getRandomValues(new Uint8Array(16));
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations: PBKDF2_ROUNDS }, key, 256);
  return { salt: hex(salt), hash: hex(new Uint8Array(bits)) };
}

/// Two hashes compared in a time that does not depend on where they differ.
function same(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

async function sha256(s) {
  return hex(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s))));
}

function hex(bytes) {
  return [...bytes].map(b => b.toString(16).padStart(2, '0')).join('');
}

function base64url(bytes) {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/// Free text: printable, cut at `max` characters; new lines kept only where asked, two at most in a row.
function longText(s, max, lines = false) {
  if (typeof s !== 'string') return '';
  const t = lines
    ? s.replace(/\r\n?/g, '\n').replace(/[\u0000-\u0009\u000b-\u001f\u007f]/g, '').replace(/\n{3,}/g, '\n\n')
    : s.replace(/[\u0000-\u001f\u007f]/g, ' ');
  return [...t.trim()].slice(0, max).join('').trim();
}

/// A whole number between lo and hi, or null.
function int(x, lo, hi) {
  if (x === null || x === undefined || x === '') return null;
  const n = Math.round(+x);
  return Number.isFinite(n) && n >= lo && n <= hi ? n : null;
}

/// The cars as the owner sent them, checked one by one; null if the whole thing makes no sense.
function cleanGarage(b, name) {
  if (!b || typeof b !== 'object' || !Array.isArray(b.cars) || b.cars.length > MAX_CARS) return null;
  const ids = new Set();
  const cars = [];
  for (const c of b.cars) {
    const id = c && typeof c === 'object' ? clean(c.id, ID) : null;
    if (!id || ids.has(id)) return null;
    ids.add(id);
    cars.push({
      id,
      name: longText(c.name, 40) || 'Car',
      year: int(c.year, 1900, 2100),
      power: int(c.power, 1, 5000),
      weight: int(c.weight, 50, 10000),
      mods: Array.isArray(c.mods) ? c.mods.slice(0, MAX_MODS).map(m => longText(m, 80)).filter(Boolean) : [],
      notes: longText(c.notes, 600, true),
      photo: clean(c.photo, ID),
    });
  }
  return { name: text(name), cars, audience: AUDIENCES.includes(b.audience) ? b.audience : 'all', updated: Date.now() };
}

function html(body, status = 200) {
  return new Response(body, { status, headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'public, max-age=60' } });
}

function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}
