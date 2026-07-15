// Supabase Auth "Send Email" Hook -> Resend
//
// Supabase calls this function for every auth email (signup confirmation,
// password recovery, email change, magic link, reauthentication) instead of
// sending its own default email. We verify the request came from Supabase
// using the official `standardwebhooks` library, build a branded HTML email
// per action type, and send it through Resend using the verified
// eiquoab.xyz domain.
//
// Required function secrets (set these yourself, they are NOT in git):
//   RESEND_API_KEY         - Resend API key
//   SEND_EMAIL_HOOK_SECRET - the secret Supabase shows you when you enable
//                             the "Send Email" auth hook (starts with
//                             "v1,whsec_...")
// SUPABASE_URL is already injected automatically by the edge runtime.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const RAW_HOOK_SECRET = Deno.env.get("SEND_EMAIL_HOOK_SECRET") ?? "";
const HOOK_SECRET = RAW_HOOK_SECRET.replace("v1,whsec_", "");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const FROM_ADDRESS = Deno.env.get("AUTH_EMAIL_FROM") || "Gather <noreply@eiquoab.xyz>";

const BRAND_COLOR = "#0F766E"; // teal, matches the Gather mark

interface HookPayload {
  user: { email: string; user_metadata?: Record<string, unknown> };
  email_data: {
    token: string;
    token_hash: string;
    redirect_to: string;
    email_action_type: string;
    site_url: string;
    token_new?: string;
    token_hash_new?: string;
  };
}

function jsonError(message: string, httpCode = 500): Response {
  return new Response(
    JSON.stringify({ error: { http_code: httpCode, message } }),
    { status: httpCode, headers: { "Content-Type": "application/json" } },
  );
}

function buildLink(emailData: HookPayload["email_data"]): string {
  const params = new URLSearchParams({
    token: emailData.token_hash,
    type: emailData.email_action_type,
    redirect_to: emailData.redirect_to,
  });
  return `${SUPABASE_URL}/auth/v1/verify?${params.toString()}`;
}

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
            If you didn't request this, you can safely ignore this email.
          </td></tr>
        </table>
      </td></tr>
    </table>
  </body>
</html>`;
}

function button(url: string, label: string): string {
  return `<a href="${url}" style="display:inline-block;background:${BRAND_COLOR};color:#ffffff;text-decoration:none;padding:12px 24px;border-radius:8px;font-weight:600;font-size:15px;margin:12px 0;">${label}</a>`;
}

function fallbackLink(url: string): string {
  return `<p style="color:#6B7280;font-size:13px;word-break:break-all;">Or paste this link into your browser:<br/><a href="${url}" style="color:${BRAND_COLOR};">${url}</a></p>`;
}

function renderEmail(payload: HookPayload): { subject: string; html: string } {
  const { email_action_type } = payload.email_data;
  const link = buildLink(payload.email_data);

  switch (email_action_type) {
    case "signup":
      return {
        subject: "Confirm your email for Gather",
        html: emailShell(
          "Confirm your email to finish creating your Gather account.",
          "Welcome to Gather 👋",
          `<p style="color:#374151;font-size:15px;line-height:1.5;">Tap the button below to confirm your email and activate your account.</p>
           ${button(link, "Confirm email")}
           ${fallbackLink(link)}`,
        ),
      };
    case "recovery":
      return {
        subject: "Reset your Gather password",
        html: emailShell(
          "Reset your Gather password.",
          "Reset your password",
          `<p style="color:#374151;font-size:15px;line-height:1.5;">We got a request to reset the password for your Gather account. This link expires in 1 hour.</p>
           ${button(link, "Reset password")}
           ${fallbackLink(link)}
           <p style="color:#9CA3AF;font-size:13px;">Didn't request this? Your password is still safe — just ignore this email.</p>`,
        ),
      };
    case "email_change":
      return {
        subject: "Confirm your new email for Gather",
        html: emailShell(
          "Confirm your new email address for Gather.",
          "Confirm your new email",
          `<p style="color:#374151;font-size:15px;line-height:1.5;">Tap below to confirm this is your new email address for Gather.</p>
           ${button(link, "Confirm new email")}
           ${fallbackLink(link)}`,
        ),
      };
    case "magiclink":
      return {
        subject: "Your Gather sign-in link",
        html: emailShell(
          "Your Gather sign-in link.",
          "Sign in to Gather",
          `<p style="color:#374151;font-size:15px;line-height:1.5;">Tap below to sign in. This link expires shortly.</p>
           ${button(link, "Sign in")}
           ${fallbackLink(link)}`,
        ),
      };
    case "reauthentication":
      return {
        subject: "Your Gather verification code",
        html: emailShell(
          "Your Gather verification code.",
          "Verify it's you",
          `<p style="color:#374151;font-size:15px;line-height:1.5;">Enter this code to continue:</p>
           <p style="font-size:28px;font-weight:700;letter-spacing:4px;color:${BRAND_COLOR};">${payload.email_data.token}</p>`,
        ),
      };
    default:
      return {
        subject: "Gather account notification",
        html: emailShell("Gather account notification.", "Account update", `${button(link, "Continue")}${fallbackLink(link)}`),
      };
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return jsonError("Method not allowed", 405);

  const rawBody = await req.text();
  const headers = Object.fromEntries(req.headers);

  let payload: HookPayload;
  try {
    const wh = new Webhook(HOOK_SECRET);
    payload = wh.verify(rawBody, headers) as HookPayload;
  } catch (err) {
    console.log("DEBUG: webhook verify failed", String(err));
    return jsonError("Invalid webhook signature", 401);
  }

  if (!RESEND_API_KEY) return jsonError("RESEND_API_KEY is not configured", 500);

  const { subject, html } = renderEmail(payload);

  const resendRes = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: FROM_ADDRESS,
      to: [payload.user.email],
      subject,
      html,
    }),
  });

  if (!resendRes.ok) {
    const detail = await resendRes.text();
    console.log("DEBUG: resend failed", resendRes.status, detail);
    return jsonError(`Resend send failed: ${resendRes.status} ${detail}`, 500);
  }

  return new Response(JSON.stringify({}), { status: 200, headers: { "Content-Type": "application/json" } });
});
