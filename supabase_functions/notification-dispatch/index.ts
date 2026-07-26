// Phase 9: Notification dispatch.
//
// Wired as a Supabase Database Webhook: INSERT on public.notifications ->
// this function. (Configured via Dashboard/CLI, not SQL — same "Supabase-
// managed hook" pattern as the auth-email Send Email Hook. A Database
// Webhook already carries its own signing; we additionally check a shared
// secret header set on the webhook config, so a stolen function URL alone
// isn't enough to spam-fire notifications.)
//
// For every insert this does two independent things, best-effort, and
// never throws back to Postgres (a failed push/email must never roll back
// or block the DB insert that already happened):
//   1. Push via FCM HTTP v1 (the legacy server-key API Google shut down in
//      2024 — v1 requires an OAuth2 access token from a service-account
//      JWT, built here with Web Crypto since there's no Node crypto in
//      Deno edge runtime).
//   2. Email via Resend, for the categories worth an inbox notification
//      (security/login always; moderation/appeal/report/broadcast if the
//      recipient hasn't muted that category). Social types (likes,
//      comments, follows, mentions, community posts) are push-only by
//      design — nobody wants a follower-count inbox.
//
// Required function secrets (set via `supabase secrets set`, NOT in git):
//   SUPABASE_SERVICE_ROLE_KEY   - already injected by the edge runtime
//   SUPABASE_URL                - already injected by the edge runtime
//   NOTIFICATION_WEBHOOK_SECRET - shared secret; must match the custom
//                                 header configured on the Database Webhook
//   FCM_SERVICE_ACCOUNT_JSON    - full Firebase service-account JSON (single
//                                 line), for FCM v1 OAuth
//   FCM_PROJECT_ID              - Firebase project ID (messages:send URL)
//   RESEND_API_KEY              - Resend API key (same one auth-email uses)
//   NOTIFICATION_EMAIL_FROM     - optional, defaults to noreply@eiquoab.xyz

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const WEBHOOK_SECRET = Deno.env.get("NOTIFICATION_WEBHOOK_SECRET") ?? "";
const FCM_SERVICE_ACCOUNT_JSON = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON") ?? "";
const FCM_PROJECT_ID = Deno.env.get("FCM_PROJECT_ID") ?? "";
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const FROM_ADDRESS = Deno.env.get("NOTIFICATION_EMAIL_FROM") || "Gather <noreply@eiquoab.xyz>";
const BRAND_COLOR = "#0F766E";

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

interface NotificationRow {
  id: string;
  recipient_id: string;
  actor_id: string | null;
  type: string;
  post_id: string | null;
  metadata: Record<string, unknown>;
}

interface WebhookPayload {
  type: "INSERT";
  table: string;
  record: NotificationRow;
}

// Settings-key gate per type. `null` = always send (not user-mutable),
// matching the categories already in Settings > Notifications
// (`users.notification_settings` jsonb) plus two new Phase 9 keys
// (`moderation_alerts`, `admin_broadcasts`) the client now also exposes.
const CATEGORY_KEY: Record<string, string | null> = {
  new_follower: "friend_requests",
  post_like: "likes",
  post_comment: "comments",
  post_reply: "comments",
  post_repost: "likes",
  poll_vote: "likes",
  mention: "mentions",
  community_post: "community_activity",
  event_reminder: null,
  scheduled_post_published: null,
  security_alert: null,
  login_alert: null,
  moderation_alert: "moderation_alerts",
  appeal_update: "moderation_alerts",
  report_update: "moderation_alerts",
  admin_broadcast: "admin_broadcasts",
};

// Categories that also get an email, not just a push. Kept short
// deliberately — social engagement notifications staying push-only avoids
// turning email into a second, noisier feed.
const EMAIL_TYPES = new Set([
  "security_alert",
  "login_alert",
  "moderation_alert",
  "appeal_update",
  "report_update",
]);

const CRITICAL_TYPES = new Set(["security_alert", "login_alert"]);

function isCategoryEnabled(settings: Record<string, unknown> | null, type: string): boolean {
  if (CRITICAL_TYPES.has(type)) return true;
  const key = CATEGORY_KEY[type];
  if (key === null || key === undefined) return true;
  const value = settings?.[key];
  return value !== false; // default on, same convention the client uses (Settings' `_notif` helper)
}

function pushCopy(type: string, actorName: string, metadata: Record<string, unknown>): { title: string; body: string } {
  const name = actorName || "Someone";
  switch (type) {
    case "new_follower":
      return { title: "New follower", body: `${name} started following you` };
    case "post_like":
      return { title: "New like", body: `${name} liked your post` };
    case "post_comment":
      return { title: "New comment", body: `${name} commented on your post` };
    case "post_reply":
      return { title: "New reply", body: `${name} replied to your post` };
    case "mention":
      return { title: "You were mentioned", body: `${name} tagged you in a post` };
    case "community_post":
      return { title: "Community activity", body: `${name} posted in a community you're in` };
    case "post_repost":
      return { title: "New repost", body: `${name} reposted your post` };
    case "poll_vote":
      return { title: "Poll vote", body: `${name} voted in your poll` };
    case "event_reminder":
      return { title: "Event reminder", body: "Your event is starting soon" };
    case "scheduled_post_published":
      return { title: "Post published", body: "Your scheduled post just went live" };
    case "security_alert": {
      const eventType = String(metadata?.event_type ?? "account change");
      return { title: "Security alert", body: `A security change was made on your account: ${eventType.replaceAll("_", " ")}` };
    }
    case "login_alert":
      return { title: "New sign-in", body: `New sign-in from ${String(metadata?.device_label ?? "a device")} you haven't used before` };
    case "moderation_alert": {
      const action = String(metadata?.action ?? "moderation action");
      return { title: "Moderation update", body: `Your account had a moderation action applied: ${action.replaceAll("_", " ")}` };
    }
    case "appeal_update":
      return { title: "Appeal update", body: `Your appeal status changed to "${String(metadata?.status ?? "updated")}"` };
    case "report_update":
      return { title: "Report update", body: "A report you filed has been reviewed" };
    case "admin_broadcast":
      return { title: String(metadata?.title ?? "Announcement"), body: String(metadata?.body ?? "") };
    default:
      return { title: "Gather", body: `${name} interacted with your content` };
  }
}

// ---- FCM v1 (OAuth2 service-account JWT, signed with Web Crypto) --------

function base64url(input: ArrayBuffer | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : new Uint8Array(input);
  let str = "";
  for (const b of bytes) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const clean = pem.replace(/-----BEGIN PRIVATE KEY-----/, "").replace(/-----END PRIVATE KEY-----/, "").replace(/\s+/g, "");
  const raw = atob(clean);
  const buf = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) buf[i] = raw.charCodeAt(i);
  return buf.buffer;
}

let cachedToken: { token: string; expiresAt: number } | null = null;

async function getFcmAccessToken(): Promise<string | null> {
  if (!FCM_SERVICE_ACCOUNT_JSON) return null;
  if (cachedToken && cachedToken.expiresAt > Date.now() + 30_000) return cachedToken.token;

  const sa = JSON.parse(FCM_SERVICE_ACCOUNT_JSON) as { client_email: string; private_key: string };
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(claims))}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
  const jwt = `${unsigned}.${base64url(signature)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) {
    console.log("DEBUG: FCM OAuth token fetch failed", res.status, await res.text());
    return null;
  }
  const data = await res.json();
  cachedToken = { token: data.access_token, expiresAt: Date.now() + (data.expires_in ?? 3600) * 1000 };
  return cachedToken.token;
}

async function sendPush(fcmToken: string, title: string, body: string, notif: NotificationRow): Promise<boolean> {
  if (!FCM_PROJECT_ID) return false;
  const accessToken = await getFcmAccessToken();
  if (!accessToken) return false;

  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      message: {
        token: fcmToken,
        notification: { title, body },
        data: {
          type: notif.type,
          notification_id: notif.id,
          post_id: notif.post_id ?? "",
        },
      },
    }),
  });

  if (!res.ok) {
    const detail = await res.text();
    console.log("DEBUG: FCM send failed", res.status, detail);
    // Token no longer valid (uninstalled app, expired) — stop retrying it.
    if (res.status === 404 || detail.includes("UNREGISTERED") || detail.includes("INVALID_ARGUMENT")) {
      await admin.from("users").update({ fcm_token: null }).eq("id", notif.recipient_id);
    }
    return false;
  }
  return true;
}

// ---- Email (Resend) -------------------------------------------------------

function emailShell(preheader: string, heading: string, bodyHtml: string): string {
  return `<!DOCTYPE html>
<html>
  <body style="margin:0;padding:0;background:#F4F6F5;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
    <span style="display:none;max-height:0;overflow:hidden;">${preheader}</span>
    <table width="100%" cellpadding="0" cellspacing="0" style="padding:32px 16px;">
      <tr><td align="center">
        <table width="480" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:12px;overflow:hidden;">
          <tr><td style="background:${BRAND_COLOR};padding:24px 32px;">
            <span style="color:#ffffff;font-size:20px;font-weight:700;letter-spacing:0.3px;">Gather</span>
          </td></tr>
          <tr><td style="padding:32px;">
            <h1 style="margin:0 0 16px;font-size:20px;color:#111827;">${heading}</h1>
            ${bodyHtml}
          </td></tr>
          <tr><td style="padding:20px 32px;background:#F9FAFB;color:#6B7280;font-size:12px;">
            You're receiving this because of activity on your Gather account. Manage notification
            preferences in Settings &gt; Notifications.
          </td></tr>
        </table>
      </td></tr>
    </table>
  </body>
</html>`;
}

async function sendEmail(toEmail: string, title: string, body: string): Promise<void> {
  if (!RESEND_API_KEY) return;
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${RESEND_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from: FROM_ADDRESS,
      to: [toEmail],
      subject: title,
      html: emailShell(body, title, `<p style="color:#374151;font-size:15px;line-height:1.5;">${body}</p>`),
    }),
  });
  if (!res.ok) console.log("DEBUG: Resend send failed", res.status, await res.text());
}

// ---- Entry point -----------------------------------------------------------

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  if (WEBHOOK_SECRET) {
    const provided = req.headers.get("x-webhook-secret") ?? "";
    if (provided !== WEBHOOK_SECRET) return new Response("Unauthorized", { status: 401 });
  }

  let payload: WebhookPayload;
  try {
    payload = await req.json();
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  if (payload.table !== "notifications" || payload.type !== "INSERT") {
    return new Response(JSON.stringify({ skipped: true }), { status: 200 });
  }

  const notif = payload.record;

  try {
    const { data: recipient } = await admin
      .from("users")
      .select("fcm_token, email, notification_settings, username")
      .eq("id", notif.recipient_id)
      .single();

    if (!recipient) return new Response(JSON.stringify({ ok: true, note: "recipient not found" }), { status: 200 });

    const settings = (recipient.notification_settings as Record<string, unknown>) ?? {};
    if (!isCategoryEnabled(settings, notif.type)) {
      return new Response(JSON.stringify({ ok: true, note: "category muted" }), { status: 200 });
    }

    let actorName = "";
    if (notif.actor_id && notif.actor_id !== notif.recipient_id) {
      const { data: actor } = await admin.from("users").select("username").eq("id", notif.actor_id).single();
      actorName = (actor?.username as string) ?? "";
    }

    const { title, body } = pushCopy(notif.type, actorName, notif.metadata ?? {});

    const tasks: Promise<unknown>[] = [];
    if (recipient.fcm_token) tasks.push(sendPush(recipient.fcm_token as string, title, body, notif));
    if (recipient.email && EMAIL_TYPES.has(notif.type)) tasks.push(sendEmail(recipient.email as string, title, body));

    await Promise.allSettled(tasks);

    return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (err) {
    // Never fail loudly back to the DB webhook caller — log and 200 so
    // Supabase doesn't treat this as a webhook health failure and disable it.
    console.log("DEBUG: notification-dispatch error", String(err));
    return new Response(JSON.stringify({ ok: false, error: String(err) }), { status: 200 });
  }
});
