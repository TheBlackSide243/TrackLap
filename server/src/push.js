// Push notifications: Apple's APNs for the iPhone app, Firebase Cloud Messaging for the Android one.
// The keys are Worker secrets, set in the Cloudflare dashboard:
//   APNS_KEY      the text of the .p8 key made on developer.apple.com (Keys, Apple Push Notifications service)
//   APNS_KEY_ID   that key's ID
//   APNS_TEAM_ID  the Apple team's ID
//   FCM_SERVICE_ACCOUNT  the JSON of a service account of the Firebase project (Project settings, Service accounts)
// Without them nothing is sent. The words are the apps': the iPhone looks the Italian key up in its
// own translations (loc-key), Android writes the notification from the data in its language.

const APNS_TOPIC = 'win.shadowbyte.tracklap';
const WEEK = 7 * 24 * 3600;

let apnsAuth = null; // { id, token, at }: Apple wants a new token at most every hour, at least every 20 minutes
let fcmAuth = null; // { email, token, expires }

export const pushPlatforms = ['ios', 'android'];

/// A device token as the apps send it: hex from APNs, Firebase's own from FCM.
export function goodPushToken(platform, token) {
  if (typeof token !== 'string') return false;
  if (platform === 'ios') return /^[0-9a-f]{64,200}$/i.test(token);
  if (platform === 'android') return /^[\w:.-]{100,4096}$/.test(token);
  return false;
}

/// Sends a notification to each device; the tokens Apple or Google say are gone come back, to be
/// forgotten. Never throws: a notification that does not leave must not stop what caused it.
export async function notify(env, devices, note) {
  const gone = [];
  for (const device of devices) {
    try {
      const result = device.platform === 'ios' ? await sendAPNs(env, device.token, note) : await sendFCM(env, device.token, note);
      if (result === 'gone') gone.push(device.token);
    } catch (e) {
      console.log('push failed', device.platform, e.message);
    }
  }
  return gone;
}

async function sendAPNs(env, token, note) {
  if (!env.APNS_KEY || !env.APNS_KEY_ID || !env.APNS_TEAM_ID) return 'off';
  const host = env.APNS_SANDBOX ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
  const res = await fetch(`https://${host}/3/device/${token}`, {
    method: 'POST',
    headers: {
      authorization: 'bearer ' + (await apnsToken(env)),
      'apns-topic': env.APNS_TOPIC || APNS_TOPIC,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'apns-expiration': String(Math.floor(Date.now() / 1000) + WEEK),
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      aps: {
        alert: { 'title-loc-key': note.title, 'loc-key': note.body, 'loc-args': note.args },
        sound: 'default',
        'thread-id': note.kind,
      },
      kind: note.kind,
      ...note.data,
    }),
  });
  if (res.ok) return 'sent';
  const reason = (await res.json().catch(() => ({}))).reason || '';
  console.log('apns', res.status, reason);
  if (res.status === 403 && reason === 'ExpiredProviderToken') apnsAuth = null;
  return res.status === 410 || ['BadDeviceToken', 'Unregistered', 'DeviceTokenNotForTopic'].includes(reason) ? 'gone' : 'failed';
}

async function apnsToken(env) {
  const now = Math.floor(Date.now() / 1000);
  const id = env.APNS_KEY_ID + '.' + env.APNS_TEAM_ID;
  if (apnsAuth && apnsAuth.id === id && now - apnsAuth.at < 45 * 60) return apnsAuth.token;
  const key = await crypto.subtle.importKey('pkcs8', pemBytes(env.APNS_KEY), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const token = await jwt({ alg: 'ES256', kid: env.APNS_KEY_ID }, { iss: env.APNS_TEAM_ID, iat: now }, key, { name: 'ECDSA', hash: 'SHA-256' });
  apnsAuth = { id, token, at: now };
  return token;
}

async function sendFCM(env, token, note) {
  if (!env.FCM_SERVICE_ACCOUNT) return 'off';
  const auth = await fcmToken(env);
  const data = { kind: note.kind, args: JSON.stringify(note.args) };
  for (const [k, v] of Object.entries(note.data)) data[k] = String(v);
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${auth.project}/messages:send`, {
    method: 'POST',
    headers: { authorization: 'Bearer ' + auth.token, 'content-type': 'application/json' },
    body: JSON.stringify({ message: { token, data, android: { priority: 'HIGH', ttl: WEEK + 's' } } }),
  });
  if (res.ok) return 'sent';
  const error = (await res.json().catch(() => ({}))).error || {};
  const code = (error.details || []).find(d => d.errorCode)?.errorCode || error.status || '';
  console.log('fcm', res.status, code);
  if (res.status === 401) fcmAuth = null;
  return res.status === 404 || code === 'UNREGISTERED' ? 'gone' : 'failed';
}

/// Google's access token for FCM, from a JWT signed with the service account's key.
async function fcmToken(env) {
  const account = JSON.parse(env.FCM_SERVICE_ACCOUNT);
  const now = Math.floor(Date.now() / 1000);
  if (fcmAuth && fcmAuth.email === account.client_email && fcmAuth.expires - now > 300) {
    return { token: fcmAuth.token, project: account.project_id };
  }
  const key = await crypto.subtle.importKey('pkcs8', pemBytes(account.private_key), { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const assertion = await jwt({ alg: 'RS256', typ: 'JWT' }, {
    iss: account.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }, key, { name: 'RSASSA-PKCS1-v1_5' });
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }).toString(),
  });
  if (!res.ok) throw new Error('fcm sign-in ' + res.status);
  const got = await res.json();
  fcmAuth = { email: account.client_email, token: got.access_token, expires: now + (got.expires_in || 3600) };
  return { token: got.access_token, project: account.project_id };
}

async function jwt(header, claims, key, algorithm) {
  const input = base64url(text(JSON.stringify(header))) + '.' + base64url(text(JSON.stringify(claims)));
  const signature = await crypto.subtle.sign(algorithm, key, text(input));
  return input + '.' + base64url(new Uint8Array(signature));
}

/// The key in a PEM text (a .p8 file, a service account's private_key), even pasted with \n.
function pemBytes(pem) {
  const b64 = String(pem).replace(/\\n/g, '\n').replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  return Uint8Array.from(atob(b64), c => c.charCodeAt(0));
}

const text = s => new TextEncoder().encode(s);

function base64url(bytes) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
