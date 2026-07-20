// Phase 3 privacy compliance: "download your data".
//
// Called by the client (SupabaseConfig.client.functions.invoke('data-export'))
// with the person's own session JWT. Assembles everything Gather holds about
// them into one JSON bundle, uploads it to the private 'data-exports'
// storage bucket, and returns a 7-day signed download URL. The
// data_export_requests row (created by the request_data_export() RPC, see
// migration 015) is updated in place so the client can poll/display status.
//
// This function needs the SUPABASE_SERVICE_ROLE_KEY (auto-injected) both to
// read across tables regardless of RLS and to write to the private bucket,
// which grants no direct client access — export files are only ever handed
// out via a signed URL.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SIGNED_URL_TTL_SECONDS = 60 * 60 * 24 * 7; // 7 days

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, content-type",
      },
    });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "");
  if (!jwt) return jsonResponse({ error: "Missing Authorization header" }, 401);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  // The gateway already validated this JWT (verify_jwt is on for this
  // function), but we still need it decoded to get the user id.
  const { data: userRes, error: userErr } = await admin.auth.getUser(jwt);
  if (userErr || !userRes?.user) {
    return jsonResponse({ error: "Invalid or expired session" }, 401);
  }
  const userId = userRes.user.id;

  // Reuse an in-flight request if one exists, same dedup rule as the
  // request_data_export() RPC, rather than doing the work twice.
  const { data: existing } = await admin
    .from("data_export_requests")
    .select("*")
    .eq("user_id", userId)
    .in("status", ["pending", "processing"])
    .order("requested_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  let requestRow = existing;
  if (!requestRow) {
    const { data: inserted, error: insertErr } = await admin
      .from("data_export_requests")
      .insert({ user_id: userId, status: "processing" })
      .select("*")
      .single();
    if (insertErr || !inserted) {
      return jsonResponse({ error: `Could not create export request: ${insertErr?.message}` }, 500);
    }
    requestRow = inserted;
  } else if (requestRow.status === "pending") {
    await admin.from("data_export_requests").update({ status: "processing" }).eq("id", requestRow.id);
  }

  const requestId = requestRow.id as string;

  try {
    const bundle = await assembleUserData(admin, userId);

    const path = `${userId}/${requestId}.json`;
    const { error: uploadErr } = await admin.storage
      .from("data-exports")
      .upload(path, JSON.stringify(bundle, null, 2), {
        contentType: "application/json",
        upsert: true,
      });
    if (uploadErr) throw new Error(`Upload failed: ${uploadErr.message}`);

    const { data: signed, error: signErr } = await admin.storage
      .from("data-exports")
      .createSignedUrl(path, SIGNED_URL_TTL_SECONDS);
    if (signErr || !signed) throw new Error(`Could not sign URL: ${signErr?.message}`);

    const expiresAt = new Date(Date.now() + SIGNED_URL_TTL_SECONDS * 1000).toISOString();

    const { data: updated } = await admin
      .from("data_export_requests")
      .update({
        status: "ready",
        file_path: signed.signedUrl,
        completed_at: new Date().toISOString(),
        expires_at: expiresAt,
        error_message: null,
      })
      .eq("id", requestId)
      .select("*")
      .single();

    return jsonResponse(updated ?? { ...requestRow, status: "ready", file_path: signed.signedUrl });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    await admin
      .from("data_export_requests")
      .update({ status: "failed", error_message: message.slice(0, 500) })
      .eq("id", requestId);
    return jsonResponse({ error: message }, 500);
  }
});

// deno-lint-ignore no-explicit-any
async function assembleUserData(admin: any, userId: string) {
  const [
    profile,
    posts,
    comments,
    likes,
    bookmarks,
    following,
    followers,
    notifications,
    consentHistory,
    stories,
    closeFriends,
    blockedUsers,
    mutedUsers,
    legalComplaints,
    appeals,
    verificationRequests,
  ] = await Promise.all([
    admin.from("users").select("*").eq("id", userId).single(),
    admin.from("posts").select("*").eq("author_id", userId).order("created_at", { ascending: false }),
    admin.from("post_comments").select("*").eq("user_id", userId).order("created_at", { ascending: false }),
    admin.from("post_likes").select("post_id, created_at").eq("user_id", userId),
    admin.from("bookmarks").select("post_id, created_at").eq("user_id", userId),
    admin.from("user_follows").select("following_id, created_at").eq("follower_id", userId),
    admin.from("user_follows").select("follower_id, created_at").eq("following_id", userId),
    admin.from("notifications").select("*").eq("recipient_id", userId).order("created_at", { ascending: false }).limit(500),
    admin.from("consent_records").select("*").eq("user_id", userId).order("recorded_at", { ascending: false }),
    admin.from("stories").select("*").eq("author_id", userId).order("created_at", { ascending: false }),
    admin.from("close_friends").select("friend_id, created_at").eq("user_id", userId),
    admin.from("user_blocks").select("blocked_id, created_at").eq("blocker_id", userId),
    admin.from("user_mutes").select("muted_id, created_at").eq("muter_id", userId),
    admin.from("legal_complaints").select("*").eq("complainant_id", userId).order("created_at", { ascending: false }),
    admin.from("user_appeals").select("*").eq("appellant_id", userId).order("created_at", { ascending: false }),
    admin.from("user_verification_requests").select("*").eq("user_id", userId).order("submitted_at", { ascending: false }),
  ]);

  return {
    export_generated_at: new Date().toISOString(),
    profile: profile.data ?? null,
    posts: posts.data ?? [],
    comments: comments.data ?? [],
    likes: likes.data ?? [],
    bookmarks: bookmarks.data ?? [],
    following: following.data ?? [],
    followers: followers.data ?? [],
    notifications: notifications.data ?? [],
    consent_history: consentHistory.data ?? [],
    stories: stories.data ?? [],
    close_friends: closeFriends.data ?? [],
    blocked_users: blockedUsers.data ?? [],
    muted_users: mutedUsers.data ?? [],
    legal_complaints_filed: legalComplaints.data ?? [],
    appeals_filed: appeals.data ?? [],
    verification_requests: verificationRequests.data ?? [],
  };
}
