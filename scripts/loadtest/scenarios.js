// k6 run -e SUPABASE_URL=... -e SUPABASE_ANON_KEY=... -e TEST_USERS=a@x.com,b@x.com -e TEST_PASSWORD=... \
//        -e SCENARIO=baseline scripts/loadtest/scenarios.js
// SCENARIO: smoke | baseline | load | stress | spike | soak   (see docs/testing/PERFORMANCE_LOAD_TEST_PLAN.md)
import { check, sleep, group } from 'k6';
import { Trend } from 'k6/metrics';
import http from 'k6/http';
import { guard, login, rpc, headers, BASE, pickUser } from './lib.js';

const feedMs = new Trend('feed_first_page_ms', true);

const profiles = {
  smoke:    { executor: 'constant-vus', vus: 2, duration: '1m' },
  baseline: { executor: 'constant-vus', vus: 50, duration: '15m' },
  load:     { executor: 'ramping-vus', startVUs: 0, stages: [
              { duration: '30m', target: 1000 }, { duration: '30m', target: 1000 }, { duration: '5m', target: 0 }] },
  stress:   { executor: 'ramping-vus', startVUs: 0, stages: [
              { duration: '10m', target: 500 }, { duration: '10m', target: 1500 }, { duration: '10m', target: 3000 }, { duration: '5m', target: 0 }] },
  spike:    { executor: 'ramping-vus', startVUs: 50, stages: [
              { duration: '1m', target: 50 }, { duration: '1m', target: 500 }, { duration: '5m', target: 500 }, { duration: '1m', target: 50 }] },
  soak:     { executor: 'constant-vus', vus: 500, duration: '8h' },
};
const scenario = __ENV.SCENARIO || 'smoke';

export const options = {
  scenarios: { main: profiles[scenario] },
  // Targets from PERFORMANCE_LOAD_TEST_PLAN.md
  thresholds: {
    'http_req_failed': ['rate<0.01'],
    'http_req_duration{name:feed_first_page}': ['p(95)<400'],
    'http_req_duration{name:feed_next_page}': ['p(95)<300'],
    'http_req_duration{name:search}': ['p(95)<600'],
    'http_req_duration{name:notifications}': ['p(95)<250'],
  },
};

export function setup() { guard(); }

let session;

export default function () {
  if (!session) session = login(pickUser());   // one login per VU, reused for all iterations

  group('feed', () => {
    const first = rpc(session, 'get_home_feed_cursor', { user_id: session.userId, page_size: 20 }, 'feed_first_page');
    feedMs.add(first.timings.duration);
    check(first, { 'feed 200': (r) => r.status === 200 });
    const rows = first.status === 200 ? first.json() : [];
    if (rows.length > 0) {
      const last = rows[rows.length - 1];
      const next = rpc(session, 'get_home_feed_cursor', {
        user_id: session.userId, page_size: 20,
        cursor_is_pinned: last.is_pinned, cursor_created_at: last.created_at, cursor_id: last.id,
      }, 'feed_next_page');
      check(next, { 'next page 200': (r) => r.status === 200 });
    }
  });
  sleep(1 + Math.random() * 2);

  group('search', () => {
    const terms = ['nepal', 'kathmandu', 'festival', 'dashain', 'momo'];
    const r = rpc(session, 'search_posts',
      { viewer_id: session.userId, q: terms[Math.floor(Math.random() * terms.length)], page_size: 20, page_offset: 0 }, 'search');
    check(r, { 'search 200': (x) => x.status === 200 });
  });
  sleep(1 + Math.random() * 2);

  group('notifications', () => {
    const r = http.get(`${BASE}/rest/v1/notifications?select=id,type,is_read,created_at&order=created_at.desc&limit=30`,
      { headers: headers(session), tags: { name: 'notifications' } });
    check(r, { 'notifications 200': (x) => x.status === 200 });
  });
  sleep(2 + Math.random() * 3);
}
