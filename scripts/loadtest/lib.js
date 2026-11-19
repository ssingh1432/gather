// Shared helpers for the k6 load tests. STAGING ONLY — never point these at production.
import http from 'k6/http';
import { fail } from 'k6';

export const BASE = __ENV.SUPABASE_URL;          // https://<staging-ref>.supabase.co
export const ANON = __ENV.SUPABASE_ANON_KEY;
const PROD_REF = 'xttxiwjllumskuhzxngx';

export function guard() {
  if (!BASE || !ANON) fail('Set SUPABASE_URL and SUPABASE_ANON_KEY (staging).');
  if (BASE.includes(PROD_REF) && __ENV.I_KNOW_THIS_IS_PRODUCTION !== 'yes') {
    fail('Refusing to run against production. Use a staging project.');
  }
}

// Signs in the pool of pre-created TEST users (TEST_USERS="a@x.com,b@x.com", TEST_PASSWORD=...).
export function login(email) {
  const r = http.post(`${BASE}/auth/v1/token?grant_type=password`,
    JSON.stringify({ email, password: __ENV.TEST_PASSWORD }),
    { headers: { apikey: ANON, 'Content-Type': 'application/json' }, tags: { name: 'auth_login' } });
  if (r.status !== 200) fail(`login failed for ${email}: ${r.status}`);
  const body = r.json();
  return { token: body.access_token, userId: body.user.id };
}

export function headers(session) {
  return { apikey: ANON, Authorization: `Bearer ${session.token}`, 'Content-Type': 'application/json' };
}

export function rpc(session, name, args, tag) {
  return http.post(`${BASE}/rest/v1/rpc/${name}`, JSON.stringify(args),
    { headers: headers(session), tags: { name: tag || name } });
}

export function pickUser() {
  const users = (__ENV.TEST_USERS || '').split(',').filter(Boolean);
  if (users.length === 0) fail('Set TEST_USERS to a comma-separated list of staging test emails.');
  return users[Math.floor(Math.random() * users.length)];
}
