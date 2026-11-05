// Push notifications: the phones an account registers, and the notification that reaches whoever
// sent an invitation when a friend accepts it, through APNs and FCM with fetch stood in for.
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
      async setAlarm() {},
      data,
    },
    setWebSocketAutoResponse() {},
    getWebSockets: () => [],
  };
}

const pem = bytes => '-----BEGIN PRIVATE KEY-----\n' + Buffer.from(bytes).toString('base64').match(/.{1,64}/g).join('\n') + '\n-----END PRIVATE KEY-----\n';
const apple = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
const google = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
const keys = {
  APNS_KEY: pem(new Uint8Array(await crypto.subtle.exportKey('pkcs8', apple.privateKey))),
  APNS_KEY_ID: 'ABC123DEFG',
  APNS_TEAM_ID: 'TEAM123456',
  FCM_SERVICE_ACCOUNT: JSON.stringify({
    project_id: 'tracklap-test',
    client_email: 'push@tracklap-test.iam.gserviceaccount.com',
    private_key: pem(new Uint8Array(await crypto.subtle.exportKey('pkcs8', google.privateKey))),
  }),
};

const IPHONE = 'a1'.repeat(32);
const ANDROID = 'fcm-token:' + 'x'.repeat(140);

/// What left for Apple and Google; `answer` says how they reply.
function network(answer = () => new Response('{}', { status: 200 })) {
  const sent = [];
  globalThis.fetch = async (input, init = {}) => {
    const url = String(input);
    const req = { url, method: init.method, headers: init.headers || {}, body: init.body };
    if (url === 'https://oauth2.googleapis.com/token') {
      sent.push({ ...req, kind: 'google-auth' });
      return Response.json({ access_token: 'google-access', expires_in: 3600 });
    }
    sent.push({ ...req, kind: url.includes('push.apple.com') ? 'apns' : 'fcm', json: JSON.parse(init.body) });
    return answer(req);
  };
  return sent;
}

function server(extra = keys) {
  const objects = new Map();
  const env = { ADMIN_KEY: 'admin-secret', ...extra };
  const accounts = [];
  const ns = (kind, make) => ({
    idFromName: name => kind + ':' + name,
    get: id => {
      if (!objects.has(id)) objects.set(id, make());
      const object = objects.get(id);
      return { fetch: (input, init) => object.fetch(input instanceof Request ? input : new Request(input, init)) };
    },
  });
  Object.assign(env, {
    ROOMS: ns('room', () => new Room(fakeState())),
    BOARDS: ns('boards', () => new Boards(fakeState())),
    ACCOUNTS: ns('accounts', () => {
      const a = new Accounts(fakeState(), env);
      accounts.push(a);
      return a;
    }),
    GARAGES: ns('garage', () => new Garage(fakeState())),
  });
  const call = async (method, path, { token, body } = {}) => {
    const h = { 'CF-Connecting-IP': '9.9.9.9' };
    if (token) h.Authorization = 'Bearer ' + token;
    if (body !== undefined) h['Content-Type'] = 'application/json';
    const res = await worker.fetch(new Request('https://tracklap.test' + path, {
      method,
      headers: h,
      body: body === undefined ? undefined : JSON.stringify(body),
    }), env);
    return { status: res.status, body: await res.json() };
  };
  const signUp = async username => (await call('POST', '/v1/accounts', { body: { username, password: 'pista-2026' } })).body;
  // The notification leaves after the answer: wait for it.
  const settled = () => Promise.all(accounts.map(a => a.pending));
  const befriend = async (inviter, guest) => {
    const { code } = (await call('POST', '/v1/me/invite', { token: inviter.token })).body;
    const res = await call('POST', '/v1/friends', { token: guest.token, body: { code } });
    await settled();
    return res;
  };
  return { call, signUp, befriend, settled };
}

function decode(part) {
  return JSON.parse(Buffer.from(part, 'base64url').toString());
}

test('a friend accepting your invitation reaches your iPhone and your Android phone', async () => {
  const sent = network();
  const { call, signUp, befriend } = server();
  const luca = await signUp('Luca');
  const marco = await signUp('Marco');
  assert.equal((await call('PUT', '/v1/me/push', { body: { platform: 'ios', token: IPHONE } })).status, 401);
  assert.equal((await call('PUT', '/v1/me/push', { token: luca.token, body: { platform: 'ios', token: 'nope' } })).status, 400);
  assert.equal((await call('PUT', '/v1/me/push', { token: luca.token, body: { platform: 'web', token: IPHONE } })).status, 400);
  assert.equal((await call('PUT', '/v1/me/push', { token: luca.token, body: { platform: 'ios', token: IPHONE } })).status, 200);
  assert.equal((await call('PUT', '/v1/me/push', { token: luca.token, body: { platform: 'ios', token: IPHONE } })).status, 200, 'twice is once');
  assert.equal((await call('PUT', '/v1/me/push', { token: luca.token, body: { platform: 'android', token: ANDROID } })).status, 200);

  assert.equal((await befriend(luca, marco)).status, 201);
  const apns = sent.filter(s => s.kind === 'apns');
  assert.equal(apns.length, 1, 'one iPhone, once');
  assert.equal(apns[0].url, `https://api.push.apple.com/3/device/${IPHONE}`);
  assert.equal(apns[0].headers['apns-topic'], 'win.shadowbyte.tracklap');
  assert.equal(apns[0].headers['apns-push-type'], 'alert');
  assert.deepEqual(apns[0].json.aps.alert, {
    'title-loc-key': 'Nuovo amico',
    'loc-key': '%@ ha accettato il tuo invito: ora siete amici.',
    'loc-args': ['Marco'],
  });
  assert.equal(apns[0].json.friend, marco.account.id);
  // Signed for Apple with the team's key.
  const [header, claims, signature] = apns[0].headers.authorization.replace('bearer ', '').split('.');
  assert.deepEqual(decode(header), { alg: 'ES256', kid: 'ABC123DEFG' });
  assert.equal(decode(claims).iss, 'TEAM123456');
  assert.ok(await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, apple.publicKey,
    Buffer.from(signature, 'base64url'), new TextEncoder().encode(header + '.' + claims)));

  const auth = sent.find(s => s.kind === 'google-auth');
  const assertion = new URLSearchParams(auth.body).get('assertion').split('.');
  assert.equal(decode(assertion[1]).scope, 'https://www.googleapis.com/auth/firebase.messaging');
  assert.ok(await crypto.subtle.verify('RSASSA-PKCS1-v1_5', google.publicKey,
    Buffer.from(assertion[2], 'base64url'), new TextEncoder().encode(assertion[0] + '.' + assertion[1])));
  const fcm = sent.filter(s => s.kind === 'fcm');
  assert.equal(fcm.length, 1);
  assert.equal(fcm[0].url, 'https://fcm.googleapis.com/v1/projects/tracklap-test/messages:send');
  assert.equal(fcm[0].headers.authorization, 'Bearer google-access');
  assert.deepEqual(fcm[0].json.message.data, { kind: 'friend', args: '["Marco"]', friend: marco.account.id, name: 'Marco' });
  assert.equal(fcm[0].json.message.token, ANDROID);

  // Who accepts gets nothing: they know.
  assert.equal(sent.filter(s => s.kind !== 'google-auth').length, 2);
});

test('signing out, a phone Apple forgot, and no keys: nothing goes', async () => {
  let gone = false;
  const sent = network(() => (gone ? Response.json({ reason: 'Unregistered' }, { status: 410 }) : new Response('{}')));
  const { call, signUp, befriend } = server();
  const luca = await signUp('Luca');
  await call('PUT', '/v1/me/push', { token: luca.token, body: { platform: 'ios', token: IPHONE } });
  await call('PUT', '/v1/me/push', { token: luca.token, body: { platform: 'android', token: ANDROID } });
  await call('DELETE', '/v1/me/push', { token: luca.token, body: { token: ANDROID } });
  await befriend(luca, await signUp('Marco'));
  assert.deepEqual(sent.filter(s => s.kind !== 'google-auth').map(s => s.kind), ['apns'], 'the Android phone was taken off');

  // Apple says the app is gone from that iPhone: it is forgotten.
  gone = true;
  await befriend(luca, await signUp('Anna'));
  await befriend(luca, await signUp('Sara'));
  assert.equal(sent.filter(s => s.kind === 'apns').length, 2, 'not asked again');

  // A password change keeps this phone's notifications, signing out ends them.
  gone = false;
  const giulia = await signUp('Giulia');
  await call('PUT', '/v1/me/push', { token: giulia.token, body: { platform: 'android', token: ANDROID } });
  const changed = await call('POST', '/v1/me/password', { token: giulia.token, body: { old: 'pista-2026', new: 'pista-2027' } });
  await befriend({ token: changed.body.token }, await signUp('Paolo'));
  assert.equal(sent.filter(s => s.kind === 'fcm').length, 1, 'still there after the new password');
  await call('DELETE', '/v1/sessions', { token: changed.body.token });
  const again = (await call('POST', '/v1/sessions', { body: { username: 'Giulia', password: 'pista-2027' } })).body;
  await befriend({ token: again.token }, await signUp('Elena'));
  assert.equal(sent.filter(s => s.kind === 'fcm').length, 1, 'signed out: nothing more');

  // Without the keys the server sends nothing and still makes friends.
  const quiet = network();
  const off = server({});
  const a = await off.signUp('Luca');
  await off.call('PUT', '/v1/me/push', { token: a.token, body: { platform: 'ios', token: IPHONE } });
  assert.equal((await off.befriend(a, await off.signUp('Marco'))).status, 201);
  assert.equal(quiet.length, 0);
});
