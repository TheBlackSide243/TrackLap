// Friends: invitations, friendships both ways, garages shown to friends only, a friend's laps and
// numbers, through the worker with in-memory stand-ins for the Durable Objects: `npm test` in server/.
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

function server() {
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
  };
  const call = async (method, path, { token, body, headers = {} } = {}) => {
    const h = { 'CF-Connecting-IP': '9.9.9.9', ...headers };
    if (token) h.Authorization = 'Bearer ' + token;
    if (body !== undefined) h['Content-Type'] = 'application/json';
    const res = await worker.fetch(new Request('https://tracklap.test' + path, {
      method,
      headers: h,
      body: body === undefined ? undefined : JSON.stringify(body),
    }), env);
    const type = res.headers.get('Content-Type') || '';
    return { status: res.status, body: type.includes('json') ? await res.json() : type.includes('html') ? await res.text() : res };
  };
  const signUp = async username => {
    const made = await call('POST', '/v1/accounts', { body: { username, password: 'pista-2026' } });
    return { token: made.body.token, id: made.body.account.id };
  };
  return { call, signUp };
}

const mugello = { name: 'Mugello', lat: 43.99752, lon: 11.37147 };
const vallelunga = { name: 'Vallelunga', lat: 42.15742, lon: 12.36908 };

test('an invitation makes two drivers friends both ways', async () => {
  const { call, signUp } = server();
  const luca = await signUp('Luca');
  const marco = await signUp('Marco');
  assert.equal((await call('POST', '/v1/me/invite')).status, 401);

  const inv = await call('POST', '/v1/me/invite', { token: luca.token });
  assert.equal(inv.status, 201);
  assert.match(inv.body.code, /^[A-HJ-NP-Z2-9]{8}$/);
  assert.ok(inv.body.expires > Date.now() + 6 * 24 * 3600 * 1000);
  assert.equal((await call('POST', '/v1/me/invite', { token: luca.token })).body.code, inv.body.code, 'the same link for a week');
  assert.deepEqual((await call('GET', `/v1/invites/${inv.body.code.toLowerCase()}`)).body.name, 'Luca');
  assert.equal((await call('GET', '/v1/invites/AAAAAAAA')).status, 404);

  assert.equal((await call('POST', '/v1/friends', { token: luca.token, body: { code: inv.body.code } })).status, 409, 'not with yourself');
  assert.equal((await call('POST', '/v1/friends', { body: { code: inv.body.code } })).status, 401);
  assert.equal((await call('POST', '/v1/friends', { token: marco.token, body: { code: 'NOPE' } })).status, 404);
  const accepted = await call('POST', '/v1/friends', { token: marco.token, body: { code: inv.body.code } });
  assert.equal(accepted.status, 201);
  assert.equal(accepted.body.name, 'Luca');
  assert.equal(typeof accepted.body.since, 'number');
  assert.equal((await call('POST', '/v1/friends', { token: marco.token, body: { code: inv.body.code } })).status, 200, 'twice is fine');

  assert.deepEqual((await call('GET', '/v1/friends', { token: luca.token })).body.friends.map(f => f.name), ['Marco']);
  assert.deepEqual((await call('GET', '/v1/friends', { token: marco.token })).body.friends.map(f => f.name), ['Luca']);

  // A new link: the old one stops working.
  const renewed = await call('POST', '/v1/me/invite', { token: luca.token, body: { renew: true } });
  assert.notEqual(renewed.body.code, inv.body.code);
  assert.equal((await call('GET', `/v1/invites/${inv.body.code}`)).status, 404);
  const anna = await signUp('Anna');
  assert.equal((await call('POST', '/v1/friends', { token: anna.token, body: { code: inv.body.code } })).status, 404);
  assert.equal((await call('POST', '/v1/friends', { token: anna.token, body: { code: renewed.body.code } })).status, 201);
  assert.deepEqual((await call('GET', '/v1/friends', { token: luca.token })).body.friends.map(f => f.name), ['Anna', 'Marco']);
});

test('a garage shown to friends only: friends read it, nobody else does', async () => {
  const { call, signUp } = server();
  const luca = await signUp('Luca');
  const marco = await signUp('Marco');
  const anna = await signUp('Anna');
  const { code } = (await call('POST', '/v1/me/garage', { token: luca.token })).body;
  const cars = [{ id: 'car-civic-0001', name: 'Civic Type R', power: 320, photo: 'photo-civic-01' }];
  await call('PUT', `/v1/garages/${code}`, { token: luca.token, body: { cars, audience: 'friends' } });

  const inv = (await call('POST', '/v1/me/invite', { token: luca.token })).body;
  await call('POST', '/v1/friends', { token: marco.token, body: { code: inv.code } });

  const own = await call('GET', `/v1/garages/${code}`, { token: luca.token });
  assert.equal(own.body.audience, 'friends');
  const friend = await call('GET', `/v1/garages/${code}`, { token: marco.token });
  assert.equal(friend.status, 200);
  assert.deepEqual(friend.body.cars.map(c => c.name), ['Civic Type R']);
  assert.equal(friend.body.mine, false);

  for (const token of [anna.token, undefined]) {
    const refused = await call('GET', `/v1/garages/${code}`, { token });
    assert.equal(refused.status, 403);
    assert.deepEqual(refused.body, { error: 'friends only' }, 'the owner stays inside the server');
  }
  const spoofed = await call('GET', `/v1/garages/${code}`, { token: anna.token, headers: { 'X-TrackLap-Friend': '1' } });
  assert.equal(spoofed.status, 403, 'the friend header cannot come from outside');
  const page = await call('GET', `/g/${code}`, { headers: { 'Accept-Language': 'it-IT' } });
  assert.equal(page.status, 403);
  assert.match(page.body, /solo ai suoi amici/);
  assert.doesNotMatch(page.body, /Civic/);

  // Shown to everyone again: anyone reads it; anything else is everyone too.
  await call('PUT', `/v1/garages/${code}`, { token: luca.token, body: { cars, audience: 'everybody' } });
  assert.equal((await call('GET', `/v1/garages/${code}`)).body.audience, 'all');

  // No longer friends: friends only again shuts Marco out.
  await call('PUT', `/v1/garages/${code}`, { token: luca.token, body: { cars, audience: 'friends' } });
  const lucaID = (await call('GET', '/v1/friends', { token: marco.token })).body.friends[0].id;
  assert.equal((await call('DELETE', `/v1/friends/${lucaID}`, { token: marco.token })).status, 200);
  assert.deepEqual((await call('GET', '/v1/friends', { token: luca.token })).body.friends, []);
  assert.equal((await call('GET', `/v1/garages/${code}`, { token: marco.token })).status, 403);
});

test("a friend's best laps and numbers, for friends only", async () => {
  const { call, signUp } = server();
  const luca = await signUp('Luca');
  const marco = await signUp('Marco');
  const anna = await signUp('Anna');
  const lap = (track, time, date, extra = {}) => ({ source: 'phone', time, distance: track === mugello ? 5240 : 4100, sectors: [], date, track, ...extra });
  await call('POST', '/v1/laps', { token: luca.token, body: lap(mugello, 115.2, 1798000000000) });
  await call('POST', '/v1/laps', { token: luca.token, body: lap(mugello, 113.9, 1798100000000) });
  await call('POST', '/v1/laps', { token: luca.token, body: lap(mugello, 116.0, 1798200000000) });
  await call('POST', '/v1/laps', { token: luca.token, body: lap(vallelunga, 98.4, 1797000000000) });
  await call('POST', '/v1/laps', { token: anna.token, body: lap(vallelunga, 97.1, 1797000000000) });

  const inv = (await call('POST', '/v1/me/invite', { token: luca.token })).body;
  await call('POST', '/v1/friends', { token: marco.token, body: { code: inv.code } });

  assert.equal((await call('GET', `/v1/friends/${luca.id}`, { token: anna.token })).status, 404, 'not a friend');
  assert.equal((await call('GET', `/v1/friends/${luca.id}`)).status, 401);
  const seen = await call('GET', `/v1/friends/${luca.id}`, { token: marco.token });
  assert.equal(seen.status, 200);
  assert.equal(seen.body.name, 'Luca');
  assert.deepEqual(seen.body.laps.map(l => [l.track.name, l.time, l.sessions, l.rank, l.of]), [
    ['Mugello', 113.9, 3, 1, 1],
    ['Vallelunga', 98.4, 1, 2, 2],
  ]);
  assert.equal(seen.body.laps[0].last, 1798200000000, 'the last session, even when it was slower');
  assert.deepEqual(seen.body.stats, { tracks: 2, sessions: 4, wins: 1, favourite: 'Mugello', last: 1798200000000 });
  assert.equal(JSON.stringify(seen.body).includes(anna.id), false);

  // The leaderboards look the same as before.
  const board = await call('GET', `/v1/boards?lat=${mugello.lat}&lon=${mugello.lon}&len=5200`);
  assert.deepEqual(Object.keys(board.body.laps[0]).sort(), ['car', 'date', 'garage', 'mine', 'name', 'rank', 'source', 'time', 'vehicle']);
});

test('deleting an account ends its friendships and its invitation', async () => {
  const { call, signUp } = server();
  const luca = await signUp('Luca');
  const marco = await signUp('Marco');
  const inv = (await call('POST', '/v1/me/invite', { token: luca.token })).body;
  await call('POST', '/v1/friends', { token: marco.token, body: { code: inv.code } });
  assert.equal((await call('DELETE', '/v1/me', { token: luca.token, body: { password: 'pista-2026' } })).status, 200);
  assert.deepEqual((await call('GET', '/v1/friends', { token: marco.token })).body.friends, []);
  assert.equal((await call('GET', `/v1/invites/${inv.code}`)).status, 404);
  assert.equal((await call('GET', `/f/${inv.code}`)).status, 404);
});

test('the invitation page: who it is from, escaped, and the button for the app', async () => {
  const { call, signUp } = server();
  const luca = await signUp('Luca_R');
  const { code } = (await call('POST', '/v1/me/invite', { token: luca.token })).body;
  const it = await call('GET', `/f/${code}`, { headers: { 'Accept-Language': 'it' } });
  assert.equal(it.status, 200);
  assert.match(it.body, /Luca_R ti invita su TrackLap/);
  assert.match(it.body, new RegExp(`href="tracklap://friend/${code}"`));
  assert.match(it.body, /og:title/);
  const en = await call('GET', `/f/${code.toLowerCase()}`, { headers: { 'Accept-Language': 'en-GB' } });
  assert.match(en.body, /Luca_R invites you to TrackLap/);
  assert.equal((await call('GET', '/f/<script>')).status, 404);
});
