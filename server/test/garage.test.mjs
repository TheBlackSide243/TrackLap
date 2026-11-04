// Accounts, garages, the public garage page and the leaderboards with the car of each lap, through
// the worker with in-memory stand-ins for the Durable Objects: `npm test` in server/.
import test from 'node:test';
import assert from 'node:assert/strict';

globalThis.WebSocketRequestResponsePair = class {};

const { default: worker, Room, Boards, Accounts, Garage } = await import('../src/index.js');

function fakeState() {
  const data = new Map();
  return {
    storage: {
      async get(k) {
        return structuredClone(data.get(k));
      },
      async put(k, v) {
        if (typeof k === 'object') for (const [a, b] of Object.entries(k)) data.set(a, structuredClone(b));
        else data.set(k, structuredClone(v));
      },
      async delete(k) {
        for (const key of Array.isArray(k) ? k : [k]) data.delete(key);
      },
      async deleteAll() {
        data.clear();
      },
      async setAlarm() {},
      data,
    },
    setWebSocketAutoResponse() {},
    getWebSockets: () => [],
  };
}

function server(extra = {}) {
  const objects = new Map();
  const ns = (kind, make) => ({
    idFromName: name => kind + ':' + name,
    get: id => {
      if (!objects.has(id)) objects.set(id, make());
      const object = objects.get(id);
      return { fetch: (input, init) => object.fetch(input instanceof Request ? input : new Request(input, init)) };
    },
  });
  const env = {
    ROOMS: ns('room', () => new Room(fakeState())),
    BOARDS: ns('boards', () => new Boards(fakeState())),
    ACCOUNTS: ns('accounts', () => new Accounts(fakeState())),
    GARAGES: ns('garage', () => new Garage(fakeState())),
    ADMIN_KEY: 'admin-secret',
    ...extra,
  };
  const call = async (method, path, { token, body, headers = {}, raw } = {}) => {
    const h = { 'CF-Connecting-IP': '9.9.9.9', ...headers };
    if (token) h.Authorization = 'Bearer ' + token;
    if (body !== undefined) h['Content-Type'] = 'application/json';
    const res = await worker.fetch(new Request('https://tracklap.test' + path, {
      method,
      headers: h,
      body: raw ?? (body === undefined ? undefined : JSON.stringify(body)),
    }), env);
    const type = res.headers.get('Content-Type') || '';
    return { status: res.status, body: type.includes('json') ? await res.json() : type.includes('html') ? await res.text() : res, headers: res.headers };
  };
  return { env, call };
}

const mugello = { name: 'Mugello', lat: 43.99752, lon: 11.37147 };
const jpeg = size => {
  const b = new Uint8Array(size);
  b[0] = 0xff;
  b[1] = 0xd8;
  return b;
};

test('accounts: sign up, sign in, sign out, change the password', async () => {
  const { call } = server();
  const made = await call('POST', '/v1/accounts', { body: { username: 'Luca_R', password: 'pista-2026' } });
  assert.equal(made.status, 201);
  assert.equal(made.body.account.name, 'Luca_R');
  assert.equal(made.body.account.garage, null);
  const token = made.body.token;

  assert.equal((await call('POST', '/v1/accounts', { body: { username: 'luca_r', password: 'altra-pass' } })).status, 409, 'capitals do not make a new name');
  assert.equal((await call('POST', '/v1/accounts', { body: { username: 'no spaces', password: 'pista-2026' } })).status, 400);
  assert.equal((await call('POST', '/v1/accounts', { body: { username: 'Marco', password: 'short' } })).status, 400);

  assert.equal((await call('POST', '/v1/sessions', { body: { username: 'luca_r', password: 'wrong-pass' } })).status, 403);
  const second = await call('POST', '/v1/sessions', { body: { username: 'LUCA_R', password: 'pista-2026' } });
  assert.equal(second.status, 200);
  assert.equal((await call('GET', '/v1/me', { token: second.body.token })).body.name, 'Luca_R');

  assert.equal((await call('DELETE', '/v1/sessions', { token: second.body.token })).status, 200);
  assert.equal((await call('GET', '/v1/me', { token: second.body.token })).status, 401);
  assert.equal((await call('GET', '/v1/me', { token })).status, 200, 'the other phone stays signed in');

  assert.equal((await call('POST', '/v1/me/password', { token, body: { old: 'nope-nope', new: 'nuova-pass' } })).status, 403);
  const changed = await call('POST', '/v1/me/password', { token, body: { old: 'pista-2026', new: 'nuova-pass' } });
  assert.equal(changed.status, 200);
  assert.equal((await call('GET', '/v1/me', { token })).status, 401, 'old tokens go with the old password');
  assert.equal((await call('GET', '/v1/me', { token: changed.body.token })).status, 200);
  assert.equal((await call('POST', '/v1/sessions', { body: { username: 'luca_r', password: 'nuova-pass' } })).status, 200);
});

test('accounts: too many wrong passwords are refused for a while', async () => {
  const { call } = server();
  await call('POST', '/v1/accounts', { body: { username: 'Giulia', password: 'pista-2026' } });
  for (let i = 0; i < 10; i++) {
    assert.equal((await call('POST', '/v1/sessions', { body: { username: 'giulia', password: 'guess-' + i } })).status, 403);
  }
  assert.equal((await call('POST', '/v1/sessions', { body: { username: 'giulia', password: 'pista-2026' } })).status, 429);
});

test('garage: the owner shows cars with photos, anyone reads them', async () => {
  const { call } = server();
  const { token } = (await call('POST', '/v1/accounts', { body: { username: 'Luca', password: 'pista-2026' } })).body;
  assert.equal((await call('POST', '/v1/me/garage')).status, 401);
  const opened = await call('POST', '/v1/me/garage', { token });
  assert.equal(opened.status, 201);
  const code = opened.body.code;
  assert.match(code, /^[A-HJ-NP-Z2-9]{8}$/);
  assert.equal((await call('POST', '/v1/me/garage', { token })).body.code, code, 'always the same garage');
  assert.equal((await call('GET', '/v1/me', { token })).body.garage, code);

  const cars = [
    { id: 'car-civic-0001', name: 'Honda Civic Type R', year: 2019, power: 320, weight: 1380, mods: ['Scarico Akrapovic', 'Pastiglie Ferodo DS2500', ''], notes: 'Gomme da pista\n\n\n\nsolo in autodromo', photo: 'photo-civic-01' },
    { id: 'car-clio-00002', name: '<b>Clio</b> RS', power: 'tanti', mods: 'nope', photo: null },
  ];
  const put = await call('PUT', `/v1/garages/${code}`, { token, body: { name: 'someone else', cars } });
  assert.equal(put.status, 200);
  assert.deepEqual(put.body.missing, ['photo-civic-01']);

  // Only the owner, and only for a car of the garage.
  const { token: other } = (await call('POST', '/v1/accounts', { body: { username: 'Marco', password: 'pista-2026' } })).body;
  assert.equal((await call('PUT', `/v1/garages/${code}`, { token: other, body: { cars: [] } })).status, 403);
  assert.equal((await call('PUT', `/v1/garages/${code}/photos/photo-civic-01`, { token: other, raw: jpeg(500) })).status, 403);
  assert.equal((await call('PUT', `/v1/garages/${code}/photos/photo-other-1`, { token, raw: jpeg(500) })).status, 409);
  assert.equal((await call('PUT', `/v1/garages/${code}/photos/photo-civic-01`, { token, raw: new Uint8Array(500) })).status, 400, 'not a JPEG');
  assert.equal((await call('PUT', `/v1/garages/${code}/photos/photo-civic-01`, { token, raw: jpeg(2 * 1024 * 1024) })).status, 400, 'too big');
  assert.equal((await call('PUT', `/v1/garages/${code}/photos/photo-civic-01`, { token, raw: jpeg(500) })).status, 200);

  const read = await call('GET', `/v1/garages/${code.toLowerCase()}`);
  assert.equal(read.status, 200);
  assert.equal(read.body.name, 'Luca', 'the name is the account, not what was sent');
  assert.equal(read.body.mine, false);
  assert.equal(read.body.missing, undefined);
  const [civic, clio] = read.body.cars;
  assert.equal(civic.photo, 'photo-civic-01');
  assert.deepEqual(civic.mods, ['Scarico Akrapovic', 'Pastiglie Ferodo DS2500']);
  assert.equal(civic.notes, 'Gomme da pista\n\nsolo in autodromo');
  assert.equal(clio.power, null);
  assert.deepEqual(clio.mods, []);
  assert.equal((await call('GET', `/v1/garages/${code}`, { token })).body.mine, true);

  const photo = await call('GET', `/v1/garages/${code}/photos/photo-civic-01`);
  assert.equal(photo.status, 200);
  assert.equal(photo.headers.get('Content-Type'), 'image/jpeg');
  assert.equal((await photo.body.arrayBuffer()).byteLength, 500);

  // A new photo for the Civic: the old one is deleted.
  cars[0].photo = 'photo-civic-02';
  assert.deepEqual((await call('PUT', `/v1/garages/${code}`, { token, body: { cars } })).body.missing, ['photo-civic-02']);
  assert.equal((await call('GET', `/v1/garages/${code}/photos/photo-civic-01`)).status, 404);
  assert.equal((await call('GET', `/v1/garages/${code}`)).body.cars[0].photo, null, 'no photo until it is uploaded');

  assert.equal((await call('GET', '/v1/garages/NOPE')).status, 404);
  assert.equal((await call('GET', '/v1/garages/ABCDEFGH')).status, 404);
});

test('the garage page: escaped, with the first photo for link previews', async () => {
  const { call } = server();
  const { token } = (await call('POST', '/v1/accounts', { body: { username: 'Luca', password: 'pista-2026' } })).body;
  const { code } = (await call('POST', '/v1/me/garage', { token })).body;
  const cars = [{ id: 'car-clio-00002', name: '<script>alert(1)</script>', power: 220, weight: 1200, mods: ['</script><b>x'], photo: 'photo-clio-001' }];
  await call('PUT', `/v1/garages/${code}`, { token, body: { cars } });
  await call('PUT', `/v1/garages/${code}/photos/photo-clio-001`, { token, raw: jpeg(500) });

  const it = await call('GET', `/g/${code}`, { headers: { 'Accept-Language': 'it-IT,it;q=0.9' } });
  assert.equal(it.status, 200);
  assert.match(it.body, /Il garage di Luca/);
  assert.match(it.body, /220 CV/);
  assert.match(it.body, new RegExp(`og:image" content="https://tracklap.test/v1/garages/${code}/photos/photo-clio-001"`));
  assert.match(it.body, new RegExp(`tracklap://garage/${code}`));
  assert.equal(it.body.includes('<script>alert(1)'), false);
  assert.equal(it.body.includes('</script><b>'), false, 'the data cannot close its script');

  const en = await call('GET', `/g/${code.toLowerCase()}`, { headers: { 'Accept-Language': 'en-US' } });
  assert.match(en.body, /Luca&#39;s garage/);
  assert.match(en.body, /217 hp/);
  assert.equal((await call('GET', '/g/ABCDEFGH')).status, 404);
});

test('leaderboards: only signed in, the name of the account and the car from its garage', async () => {
  const { call } = server();
  const lap = extra => ({ source: 'device', time: 112.3, distance: 5240, sectors: [], date: 1798000000000, track: mugello, ...extra });
  assert.equal((await call('POST', '/v1/laps', { body: lap({ name: 'Fake' }) })).status, 401);

  const { token } = (await call('POST', '/v1/accounts', { body: { username: 'Luca', password: 'pista-2026' } })).body;
  const { code } = (await call('POST', '/v1/me/garage', { token })).body;
  await call('PUT', `/v1/garages/${code}`, { token, body: { cars: [{ id: 'car-civic-0001', name: 'Civic Type R', power: 320 }] } });
  const { token: marco } = (await call('POST', '/v1/accounts', { body: { username: 'Marco', password: 'pista-2026' } })).body;

  assert.equal((await call('POST', '/v1/laps', { token, body: lap({ name: 'Not Luca', car: 'car-civic-0001' }) })).status, 200);
  // A car that is not in your garage is not linked.
  assert.equal((await call('POST', '/v1/laps', { token: marco, body: lap({ time: 113, source: 'phone', car: 'car-civic-0001' }) })).status, 200);

  const board = await call('GET', `/v1/boards?lat=${mugello.lat}&lon=${mugello.lon}&len=5200`, { token });
  assert.deepEqual(board.body.laps.map(l => [l.name, l.source, l.vehicle, l.garage, l.car, l.mine]), [
    ['Luca', 'device', 'Civic Type R', code, 'car-civic-0001', true],
    ['Marco', 'phone', '', '', '', false],
  ]);
  assert.equal(JSON.stringify(board.body).includes('X-TrackLap'), false);

  // Headers the worker sets cannot come from outside.
  assert.equal((await call('POST', '/v1/laps', { headers: { 'X-TrackLap-Account': 'aaaaaaaa-1111', 'X-TrackLap-Name': 'Hacker' }, body: lap({}) })).status, 401);
});

test('reports hide a garage after three people, the admin brings it back or deletes it', async () => {
  const { call } = server();
  const { token } = (await call('POST', '/v1/accounts', { body: { username: 'Luca', password: 'pista-2026' } })).body;
  const { code } = (await call('POST', '/v1/me/garage', { token })).body;
  for (const ip of ['1.1.1.1', '1.1.1.1', '2.2.2.2']) {
    await call('POST', `/v1/garages/${code}/report`, { headers: { 'CF-Connecting-IP': ip }, body: { reason: 'spam' } });
  }
  assert.equal((await call('GET', `/v1/garages/${code}`)).status, 200, 'the same person twice counts once');
  await call('POST', `/v1/garages/${code}/report`, { headers: { 'CF-Connecting-IP': '3.3.3.3' }, body: { reason: 'spam' } });
  assert.equal((await call('GET', `/v1/garages/${code}`)).status, 404);
  assert.equal((await call('GET', `/g/${code}`)).status, 404);
  const own = await call('GET', `/v1/garages/${code}`, { token });
  assert.equal(own.body.hidden, true, 'the owner still sees it, and that it is hidden');

  assert.equal((await call('POST', `/v1/garages/${code}/restore`, { headers: { 'X-TrackLap-Admin': 'wrong' } })).status, 403);
  const admin = await call('GET', `/v1/garages/${code}`, { headers: { 'X-TrackLap-Admin': 'admin-secret' } });
  assert.equal(admin.body.reports.length, 3);
  assert.equal((await call('POST', `/v1/garages/${code}/restore`, { headers: { 'X-TrackLap-Admin': 'admin-secret' } })).status, 200);
  assert.equal((await call('GET', `/v1/garages/${code}`)).status, 200);
  assert.equal((await call('DELETE', `/v1/garages/${code}`, { headers: { 'X-TrackLap-Admin': 'admin-secret' } })).status, 200);
  assert.equal((await call('GET', `/v1/garages/${code}`)).status, 404);
});

test('deleting the account takes the garage and the laps with it', async () => {
  const { call } = server();
  const { token } = (await call('POST', '/v1/accounts', { body: { username: 'Luca', password: 'pista-2026' } })).body;
  const { code } = (await call('POST', '/v1/me/garage', { token })).body;
  await call('POST', '/v1/laps', { token, body: { source: 'device', time: 112.3, distance: 5240, track: mugello } });
  assert.equal((await call('DELETE', '/v1/me', { token, body: { password: 'wrong-pass' } })).status, 403);
  assert.equal((await call('DELETE', '/v1/me', { token, body: { password: 'pista-2026' } })).status, 200);
  assert.equal((await call('GET', '/v1/me', { token })).status, 401);
  assert.equal((await call('GET', `/v1/garages/${code}`)).status, 404);
  const board = await call('GET', `/v1/boards?lat=${mugello.lat}&lon=${mugello.lon}&len=5200`);
  assert.deepEqual(board.body.laps, []);
  assert.equal((await call('POST', '/v1/accounts', { body: { username: 'luca', password: 'pista-2026' } })).status, 201, 'the name is free again');
});
