// Real-money eSewa (ePay v2) integration for the Professional Page System's
// donations / subscriptions / marketplace orders.
//
// Flow (see 090_pages_payments_esewa.sql for the DB side):
//   1. Client calls the initiate_page_payment(...) RPC directly (no secrets
//      involved) -> gets back a page_payment_transactions.id.
//   2. Client opens, in an external browser, GET /esewa-payment/pay/<id>.
//      This handler looks up the pending transaction (service role),
//      builds the HMAC-SHA256-signed eSewa form fields SERVER-SIDE (the
//      secret key never reaches the client), and returns a tiny
//      auto-submitting HTML page that POSTs straight to eSewa.
//   3. eSewa redirects the browser to this function's own
//      /esewa-payment/success or /esewa-payment/failure, both of which:
//        - decode + verify eSewa's response signature,
//        - THEN independently call eSewa's transaction-status API to
//          confirm — a redirect alone, even with a valid-looking
//          signature, is never enough to credit money,
//        - update page_payment_transactions.status and the
//          purpose-specific row (donation/subscriber/order),
//        - serve a plain confirmation page telling the person to return
//          to the Gather app.
//   4. The Flutter client watches its own transaction row over Supabase
//      Realtime (RLS already scopes SELECT to payer_id = auth.uid()) to
//      reflect the final status without polling.
//
// Required function secrets (`supabase secrets set`, NOT in git):
//   ESEWA_PRODUCT_CODE   - eSewa merchant/product code (e.g. EPAYTEST in
//                          sandbox)
//   ESEWA_SECRET_KEY     - eSewa HMAC secret key for this product code
//   ESEWA_ENV            - "test" | "live" (selects rc-epay vs epay hosts)
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY - injected by the platform,
//                          with the same MANUAL_SERVICE_ROLE_KEY override
//                          used by notification-dispatch if that grant
//                          issue recurs on this project.
//
// STATUS-CHECK HOST FIX (Aug 2026): eSewa's official developer docs
// (developer.esewa.com.np/pages/Epay-V2) give the UAT/test status-check
// host as https://uat.esewa.com.np/... and production as
// https://epay.esewa.com.np/... — this file previously pointed at
// rc.esewa.com.np (test) / esewa.com.np (prod), neither of which is
// eSewa's documented host. Corrected below. This only affected step 3
// (the post-redirect status re-check), not step 2 (the signed form
// POST) — if payments were failing before eSewa's login page even
// appeared, the cause is almost certainly ESEWA_SECRET_KEY not being
// set to eSewa's exact published UAT secret (see note below), not this
// URL.
//
// UAT test credentials (product_code=EPAYTEST only):
//   ESEWA_SECRET_KEY must be exactly: 8gBm/:&EnhH.1/q
//   Test eSewa login ID: 9806800001 (also ...002/003/004/005)
//   Password: Nepal@123   MPIN: 1122   OTP token: 123456
// Get/verify these in the Supabase dashboard under
// Edge Functions > esewa-payment > Secrets, or via
// `supabase secrets list` — never print the value in logs.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("MANUAL_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const PRODUCT_CODE = Deno.env.get("ESEWA_PRODUCT_CODE") ?? "";
const SECRET_KEY = Deno.env.get("ESEWA_SECRET_KEY") ?? "";
const ESEWA_ENV = Deno.env.get("ESEWA_ENV") ?? "test";

const IS_LIVE = ESEWA_ENV === "live";
const ESEWA_FORM_URL = IS_LIVE
  ? "https://epay.esewa.com.np/api/epay/main/v2/form"
  : "https://rc-epay.esewa.com.np/api/epay/main/v2/form";
const ESEWA_STATUS_URL = IS_LIVE
  ? "https://epay.esewa.com.np/api/epay/transaction/status/"
  : "https://uat.esewa.com.np/api/epay/transaction/status/";

const FUNCTION_BASE = `${SUPABASE_URL}/functions/v1/esewa-payment`;

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

interface Transaction {
  id: string;
  page_id: string;
  payer_id: string;
  purpose: "donation" | "subscription" | "marketplace_order";
  reference_id: string;
  amount_cents: number;
  currency: string;
  status: string;
}

async function hmacSha256Base64(message: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return btoa(String.fromCharCode(...new Uint8Array(sig)));
}

function htmlPage(title: string, message: string): Response {
  return new Response(
    `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>${title}</title>
    <style>body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#F4F6F5;display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0;padding:24px;text-align:center;}
    .card{background:#fff;border-radius:12px;padding:32px;max-width:420px;box-shadow:0 1px 3px rgba(0,0,0,0.1);}
    h1{font-size:20px;color:#111827;margin:0 0 12px;} p{color:#4B5563;font-size:15px;line-height:1.5;margin:0;}</style>
    </head><body><div class="card"><h1>${title}</h1><p>${message}</p></div></body></html>`,
    { status: 200, headers: { "Content-Type": "text/html; charset=utf-8" } },
  );
}

// ---- Step 2: build + serve the auto-submitting eSewa form -----------------

async function handlePay(txnId: string): Promise<Response> {
  if (!PRODUCT_CODE || !SECRET_KEY) {
    return htmlPage("Payments unavailable", "eSewa isn't configured on this server yet. Please try again later.");
  }
  if (!SERVICE_ROLE_KEY) {
    console.log("DEBUG: no service role key available at all (neither MANUAL_SERVICE_ROLE_KEY nor SUPABASE_SERVICE_ROLE_KEY set)");
  }

  const { data: txn, error } = await admin.from("page_payment_transactions").select("*").eq("id", txnId).single();
  if (error) {
    console.log("DEBUG: transaction lookup error for", txnId, JSON.stringify(error));
    return htmlPage("Payment not found", "This payment link is invalid or has expired.");
  }
  if (!txn) return htmlPage("Payment not found", "This payment link is invalid or has expired.");
  const t = txn as Transaction;
  if (t.status !== "pending") return htmlPage("Already processed", `This payment has already been marked as "${t.status}".`);

  const amount = (t.amount_cents / 100).toFixed(2);
  const transactionUuid = t.id; // reuse our own id as eSewa's transaction_uuid — one-to-one, no separate mapping needed
  const signedFieldNames = "total_amount,transaction_uuid,product_code";
  const message = `total_amount=${amount},transaction_uuid=${transactionUuid},product_code=${PRODUCT_CODE}`;
  const signature = await hmacSha256Base64(message, SECRET_KEY);

  const fields: Record<string, string> = {
    amount,
    tax_amount: "0",
    total_amount: amount,
    transaction_uuid: transactionUuid,
    product_code: PRODUCT_CODE,
    product_service_charge: "0",
    product_delivery_charge: "0",
    success_url: `${FUNCTION_BASE}/success`,
    failure_url: `${FUNCTION_BASE}/failure`,
    signed_field_names: signedFieldNames,
    signature,
  };

  const inputs = Object.entries(fields)
    .map(([k, v]) => `<input type="hidden" name="${k}" value="${v.replace(/"/g, "&quot;")}">`)
    .join("\n");

  return new Response(
    `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Redirecting to eSewa…</title>
    <style>body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#F4F6F5;display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0;padding:24px;text-align:center;}
    .card{background:#fff;border-radius:12px;padding:32px;max-width:420px;box-shadow:0 1px 3px rgba(0,0,0,0.1);}
    p{color:#4B5563;font-size:15px;line-height:1.5;margin:0 0 20px;}
    button{background:#0F766E;color:#fff;border:none;border-radius:8px;padding:14px 28px;font-size:16px;font-weight:600;}</style>
    </head>
    <body onload="document.forms[0].submit()">
      <div class="card">
        <p>Redirecting to eSewa…</p>
        <form method="POST" action="${ESEWA_FORM_URL}">
          ${inputs}
          <button type="submit">Continue to eSewa</button>
        </form>
        <p style="margin-top:16px;font-size:13px;">If nothing happens automatically, tap the button above.</p>
      </div>
    </body></html>`,
    { status: 200, headers: { "Content-Type": "text/html; charset=utf-8" } },
  );
}

// ---- Step 3: verify eSewa's redirect + re-check status server-side --------

async function checkEsewaStatus(productCode: string, totalAmount: string, transactionUuid: string): Promise<{ status: string; ref_id?: string } | null> {
  try {
    const url = `${ESEWA_STATUS_URL}?product_code=${encodeURIComponent(productCode)}&total_amount=${encodeURIComponent(totalAmount)}&transaction_uuid=${encodeURIComponent(transactionUuid)}`;
    const res = await fetch(url);
    if (!res.ok) {
      console.log("DEBUG: eSewa status check HTTP error", res.status, await res.text());
      return null;
    }
    const data = await res.json();
    return { status: String(data.status ?? "").toUpperCase(), ref_id: data.ref_id ?? data.transaction_code };
  } catch (err) {
    console.log("DEBUG: eSewa status check threw", String(err));
    return null;
  }
}

async function applySideEffect(t: Transaction, success: boolean) {
  if (t.purpose === "donation") {
    await admin.from("page_donations").update({ status: success ? "completed" : "failed" }).eq("id", t.reference_id);
  } else if (t.purpose === "subscription") {
    if (success) {
      const now = new Date();
      const periodEnd = new Date(now);
      periodEnd.setDate(periodEnd.getDate() + 30);
      await admin.from("page_subscribers").update({
        status: "active",
        started_at: now.toISOString(),
        current_period_end: periodEnd.toISOString(),
      }).eq("id", t.reference_id);
    }
    // On failure, leave the subscriber row 'inactive' — nothing to undo.
  } else if (t.purpose === "marketplace_order") {
    await admin.from("page_marketplace_orders").update({ status: success ? "paid" : "cancelled" }).eq("id", t.reference_id);
  }
}

async function handleReturn(req: Request, success: boolean): Promise<Response> {
  const url = new URL(req.url);
  const dataParam = url.searchParams.get("data");
  if (!dataParam) return htmlPage("Payment incomplete", "No payment data was received. If you completed payment, please check the Gather app in a moment.");

  let decoded: Record<string, unknown>;
  try {
    decoded = JSON.parse(atob(dataParam));
  } catch {
    return htmlPage("Payment error", "Could not read the payment response.");
  }

  const transactionUuid = String(decoded.transaction_uuid ?? "");
  const { data: txn, error } = await admin.from("page_payment_transactions").select("*").eq("id", transactionUuid).single();
  if (error || !txn) return htmlPage("Payment not found", "This payment could not be matched to an order.");
  const t = txn as Transaction;
  if (t.status !== "pending") return htmlPage("Already processed", `This payment has already been marked as "${t.status}".`);

  // Verify the signature over exactly the fields eSewa says it signed.
  const signedFieldNames = String(decoded.signed_field_names ?? "");
  const fieldsToSign = signedFieldNames.split(",").map((f) => f.trim()).filter(Boolean);
  const message = fieldsToSign.map((f) => `${f}=${decoded[f] ?? ""}`).join(",");
  const expectedSig = SECRET_KEY ? await hmacSha256Base64(message, SECRET_KEY) : "";
  const signatureValid = SECRET_KEY.length > 0 && expectedSig === decoded.signature;

  if (!signatureValid) {
    console.log("DEBUG: eSewa signature mismatch for txn", transactionUuid);
    await admin.from("page_payment_transactions").update({ status: "failed", raw_response: decoded }).eq("id", t.id);
    await applySideEffect(t, false);
    return htmlPage("Payment could not be verified", "Something didn't match — this payment was not completed. Please contact support if you were charged.");
  }

  // Never trust the redirect alone — independently re-check with eSewa.
  const amount = (t.amount_cents / 100).toFixed(2);
  const verified = await checkEsewaStatus(PRODUCT_CODE, amount, t.id);
  const isComplete = success && verified?.status === "COMPLETE";

  await admin.from("page_payment_transactions").update({
    status: isComplete ? "completed" : "failed",
    gateway_ref_id: verified?.ref_id ?? null,
    raw_response: { redirect: decoded, status_check: verified },
  }).eq("id", t.id);

  await applySideEffect(t, isComplete);

  return isComplete
    ? htmlPage("Payment successful", "Thank you! Your payment went through. You can return to the Gather app now.")
    : htmlPage("Payment not completed", "This payment wasn't completed. You can return to the Gather app and try again.");
}

// ---- Entry point ------------------------------------------------------------

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  const path = url.pathname.replace(/^\/esewa-payment/, "");

  try {
    if (path.startsWith("/pay/")) {
      return await handlePay(path.slice("/pay/".length));
    }
    if (path === "/success") return await handleReturn(req, true);
    if (path === "/failure") return await handleReturn(req, false);
    return new Response("Not found", { status: 404 });
  } catch (err) {
    console.log("DEBUG: esewa-payment error", String(err));
    return htmlPage("Something went wrong", "Please return to the Gather app and try again.");
  }
});
