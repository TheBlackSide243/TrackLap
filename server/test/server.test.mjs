// The Room and Boards objects against an in-memory stand-in for the Durable Object state, with no
// Cloudflare runtime: `npm test` in server/.
import test from 'node:test';
import assert from 'node:assert/strict';

globalThis.WebSocketRequestResponsePair = class {
  constructor(req, res) {
    this.request = req;
    this.response = res;
  }
};

const { default: worker, Room, Boards } = await import('../src/index.js');

function fakeState() {
  const data = new Map();
  const sockets = [];
  return {
    alarm: null,
    sockets,
    storage: {
      async get(k) {
        return structuredClone(data.get(k));
      },
      async put(k, v) {
        if (typeof k === 'object') for (const [a, b] of Object.entries(k)) data.set(a, structuredClone(b));
        else data.set(k, structuredClone(v));
      },
      async deleteAll() {
        data.clear();
      },
      async setAlarm(t) {
        this.alarm = t;
      },
      data,
    },
    setWebSocketAutoResponse() {},
    acceptWebSocket(ws) {
      sockets.push(ws);
    },
    getWebSockets() {
      return sockets.filter(s => !s.closed);
    },
  };
}

function fakeSocket() {
  return {
    sent: [],
    closed: false,
    attachment: null,
    serializeAttachment(a) {
      this.attachment = a;
    },
    deserializeAttachment() {
      return this.attachment;
    },
    send(s) {
      this.sent.push(JSON.parse(s));
    },
    close(code) {
      this.closed = true;
      this.code = code;
    },
  };
}

const mugello = { name: 'Mugello', lat: 43.99752, lon: 11.37147 };

async function room() {
  const state = fakeState();
  const r = new Room(state);
  assert.equal((await r.fetch(new Request('https://room/init', { method: 'POST' }))).status, 201);
  assert.equal((await r.fetch(new Request('https://room/init', { method: 'POST' }))).status, 409);
  return { r, state };
}

async function join(r, state, id, name, extra = {}) {
  const ws = fakeSocket();
  state.acceptWebSocket(ws);
  await r.webSocketMessage(ws, JSON.stringify({ t: 'hello', id, name, track: mugello, laps: 0, ...extra }));
  return ws;
}

test('a group: hello, positions and laps reach the others', async () => {
  const { r, state } = await room();
  const a = await join(r, state, 'aaaaaaaa-1111', 'Marco');
  assert.equal(a.sent[0].t, 'state');
  assert.equal(a.sent[0].you, 'aaaaaaaa-1111');
  assert.equal(a.sent[0].members.length, 1);

  const b = await join(r, state, 'bbbbbbbb-2222', 'Luca', { vehicle: 'Clio RS' });
  assert.equal(b.sent[0].members.length, 2);
  assert.deepEqual(a.sent.at(-1).member.name, 'Luca');
  assert.equal(a.sent.at(-1).member.online, true);

  await r.webSocketMessage(b, JSON.stringify({ t: 'pos', lat: 43.99, lon: 11.37, lap: 2, d: 812.5, v: 51.2, g: 1798000000.5 }));
  assert.deepEqual(a.sent.at(-1), { t: 'pos', id: 'bbbbbbbb-2222', lat: 43.99, lon: 11.37, lap: 2, d: 812.5, v: 51.2, g: 1798000000.5 });
  assert.equal(b.sent.length, 1, 'no echo to the sender');

  await r.webSocketMessage(b, JSON.stringify({ t: 'lap', n: 2, time: 112.3456 }));
  await r.webSocketMessage(b, JSON.stringify({ t: 'lap', n: 3, time: 113.1 }));
  const lap = a.sent.at(-1);
  assert.equal(lap.t, 'lap');
  assert.equal(lap.best, 112.346);
  assert.equal(lap.last, 113.1);
  assert.equal(lap.laps, 2);

  // A third joins and gets the times and the last position.
  const c = await join(r, state, 'cccccccc-3333', 'Giulia');
  const luca = c.sent[0].members.find(m => m.name === 'Luca');
  assert.equal(luca.best, 112.346);
  assert.equal(luca.vehicle, 'Clio RS');
  assert.equal(c.sent[0].positions.length, 1);
});

test('leaving: offline only when the last connection of a member closes', async () => {
  const { r, state } = await room();
  const a = await join(r, state, 'aaaaaaaa-1111', 'Marco');
  const b1 = await join(r, state, 'bbbbbbbb-2222', 'Luca');
  const b2 = await join(r, state, 'bbbbbbbb-2222', 'Luca');
  const before = a.sent.length;
  b1.closed = true;
  await r.webSocketClose(b1, 1006);
  assert.equal(a.sent.length, before, 'still connected through the other socket');
  b2.closed = true;
  await r.webSocketClose(b2, 1000);
  assert.equal(a.sent.at(-1).member.online, false);
});

test('bad messages are ignored, a bad hello closes', async () => {
  const { r, state } = await room();
  const a = await join(r, state, 'aaaaaaaa-1111', 'Marco');
  const n = a.sent.length;
  const x = fakeSocket();
  state.acceptWebSocket(x);
  await r.webSocketMessage(x, JSON.stringify({ t: 'pos', lat: 1, lon: 1, lap: 1, d: 1, v: 1, g: 1 }));
  await r.webSocketMessage(x, '{not json');
  await r.webSocketMessage(x, 'x'.repeat(5000));
  assert.equal(a.sent.length, n, 'nothing relayed before hello');
  await r.webSocketMessage(x, JSON.stringify({ t: 'hello', id: '../../' }));
  assert.equal(x.code, 4000);
  await r.webSocketMessage(a, JSON.stringify({ t: 'lap', time: 'fast' }));
  await r.webSocketMessage(a, JSON.stringify({ t: 'pos', lat: 500, lon: 1, lap: 1, d: 1, v: 1, g: 1 }));
  assert.equal(a.sent.length, n);
});

test('names are cut and cleaned', async () => {
  const { r, state } = await room();
  const a = await join(r, state, 'aaaaaaaa-1111', '  A very long name that goes on and on\n');
  assert.equal(a.sent[0].members[0].name, 'A very long name that go');
});

test('an empty group is deleted a day later, an active one is kept', async () => {
  const { r, state } = await room();
  const a = await join(r, state, 'aaaaaaaa-1111', 'Marco');
  await r.alarm();
  assert.ok(await state.storage.get('created'), 'someone is connected');
  a.closed = true;
  await state.storage.put('active', Date.now() - 25 * 3600 * 1000);
  await r.alarm();
  assert.equal(await state.storage.get('created'), undefined);
});

function lapRequest(driver, body) {
  return new Request('https://x/v1/laps', {
    method: 'POST',
    headers: { 'X-TrackLap-Driver': driver, 'CF-Connecting-IP': '1.2.3.4' },
    body: JSON.stringify(body),
  });
}

const lap = (time, extra = {}) => ({ name: 'Marco', vehicle: 'Clio', source: 'device', time, distance: 5240, sectors: [40, 35, 37.3], date: 1798000000000, track: mugello, ...extra });

test('leaderboards: best per driver and source, matched by start line and length', async () => {
  const b = new Boards(fakeState());
  const D1 = '11111111-aaaa', D2 = '22222222-bbbb';
  let res = await (await b.fetch(lapRequest(D1, lap(112.3)))).json();
  assert.equal(res.rank, 1);
  assert.equal(res.of, 1);
  const trackID = res.track.id;

  // Slower does not replace, faster does; 60 m away is the same circuit.
  await b.fetch(lapRequest(D1, lap(113)));
  res = await (await b.fetch(lapRequest(D2, lap(111.9, { name: 'Luca', track: { ...mugello, lat: mugello.lat + 0.0005 } })))).json();
  assert.equal(res.track.id, trackID);
  assert.equal(res.rank, 1);
  await b.fetch(lapRequest(D1, lap(111.5)));
  await b.fetch(lapRequest(D1, lap(118, { source: 'phone' })));

  const board = await (await b.fetch(new Request(`https://x/v1/boards?lat=${mugello.lat}&lon=${mugello.lon}&len=5200`, { headers: { 'X-TrackLap-Driver': D2 } }))).json();
  assert.deepEqual(board.laps.map(l => [l.name, l.source, l.rank, l.time, l.mine]), [
    ['Marco', 'device', 1, 111.5, false],
    ['Luca', 'device', 2, 111.9, true],
    ['Marco', 'phone', 1, 118, false],
  ]);
  assert.equal(JSON.stringify(board).includes(D1), false, 'driver ids stay secret');

  // A much shorter lap from the same line is another layout.
  res = await (await b.fetch(lapRequest(D1, lap(70, { distance: 2900 })))).json();
  assert.notEqual(res.track.id, trackID);
  const far = await (await b.fetch(new Request('https://x/v1/boards?lat=45&lon=9'))).json();
  assert.equal(far.track, null);
});

test('leaderboards refuse demo laps, nonsense and floods', async () => {
  const b = new Boards(fakeState());
  const D = '11111111-aaaa';
  assert.equal((await b.fetch(lapRequest(D, lap(100, { source: 'demo' })))).status, 400);
  assert.equal((await b.fetch(lapRequest(D, lap(1)))).status, 400);
  assert.equal((await b.fetch(lapRequest(D, lap(100, { distance: 5 })))).status, 400);
  assert.equal((await b.fetch(lapRequest('x', lap(100)))).status, 400);
  for (let i = 0; i < 60; i++) assert.equal((await b.fetch(lapRequest(D, lap(100 + i)))).status, 200);
  assert.equal((await b.fetch(lapRequest(D, lap(99)))).status, 429);
});

test('the worker: new group codes, routing', async () => {
  const rooms = new Map();
  const ns = make => ({
    idFromName: name => name,
    // A stub's fetch takes a URL and options too, like the real one.
    get: name => {
      if (!rooms.has(name)) rooms.set(name, make());
      const object = rooms.get(name);
      return { fetch: (input, init) => object.fetch(input instanceof Request ? input : new Request(input, init)) };
    },
  });
  const env = { ROOMS: ns(() => new Room(fakeState())), BOARDS: ns(() => new Boards(fakeState())) };
  const res = await worker.fetch(new Request('https://x/v1/rooms', { method: 'POST' }), env);
  assert.equal(res.status, 201);
  const { code } = await res.json();
  assert.match(code, /^[A-HJ-NP-Z2-9]{5}$/);
  assert.equal(rooms.size, 1);
  // Not a WebSocket: refused by the group itself; a code that cannot exist: refused by the worker.
  assert.equal((await worker.fetch(new Request(`https://x/v1/rooms/${code.toLowerCase()}/ws`), env)).status, 426);
  assert.equal((await worker.fetch(new Request('https://x/v1/rooms/OO000/ws'), env)).status, 404);
  assert.equal((await worker.fetch(new Request('https://x/v1/boards?lat=1&lon=1'), env)).status, 200);
  assert.equal((await worker.fetch(new Request('https://x/nope'), env)).status, 404);
});
