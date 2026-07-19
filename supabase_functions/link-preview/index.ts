// Fetches Open Graph metadata for a URL a person pastes into a post, so
// Gather can show a link preview card (title/image/site) without hosting
// or re-serving anyone else's content — same approach Twitter/Reddit/
// WhatsApp use for cross-platform links. Results are cached in
// public.link_previews so repeated posts of a popular link don't refetch.
//
// This function needs the SUPABASE_SERVICE_ROLE_KEY (auto-injected) to
// write to link_previews, since that table only grants SELECT to clients.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  });
}

// --- SSRF guards -----------------------------------------------------
// This function fetches whatever URL a person pastes into a post, so it
// must not be usable to reach internal/private network targets (cloud
// metadata endpoints, localhost, RFC1918 ranges, etc). We validate the
// scheme + host up front, and re-validate on every redirect hop since a
// malicious server can otherwise 30x a public-looking URL straight to a
// private address.
//
// Known residual gap: this checks the literal hostname/IP, not what it
// resolves to, so a DNS-rebinding attack (public domain whose A record
// points at a private IP) isn't fully closed. Closing that requires an
// egress allowlist/proxy at the infra level, not something a single
// function can guarantee.
const PRIVATE_IPV4_PATTERNS = [
  /^127\./, // loopback
  /^10\./, // RFC1918
  /^172\.(1[6-9]|2\d|3[01])\./, // RFC1918
  /^192\.168\./, // RFC1918
  /^169\.254\./, // link-local incl. cloud metadata (169.254.169.254)
  /^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\./, // CGNAT 100.64.0.0/10
  /^0\./, // "this" network
];

function isBlockedHost(hostname: string): boolean {
  const host = hostname.toLowerCase();
  if (host === "localhost" || host.endsWith(".local") || host.endsWith(".internal")) return true;
  // IPv6 literals contain colons (URL.hostname keeps them, minus the
  // brackets) — only apply IPv6-range checks to those, so a domain that
  // happens to start with "fc"/"fd" (e.g. fc-media.com) isn't caught.
  if (host.includes(":")) {
    if (host === "::1" || host.startsWith("fe80:") || host.startsWith("fc") || host.startsWith("fd")) return true;
  }
  if (PRIVATE_IPV4_PATTERNS.some((re) => re.test(host))) return true;
  return false;
}

function assertSafeUrl(rawUrl: string): URL {
  const parsed = new URL(rawUrl);
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    throw new Error("Only http/https URLs are allowed");
  }
  if (isBlockedHost(parsed.hostname)) {
    throw new Error("This URL points to a blocked/internal address");
  }
  return parsed;
}

/// Fetches with a timeout and manually validates every redirect hop
/// against the same SSRF rules before following it.
async function safeFetch(rawUrl: string, maxRedirects = 5): Promise<Response> {
  let current = assertSafeUrl(rawUrl);
  for (let hop = 0; hop <= maxRedirects; hop++) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8000);
    let res: Response;
    try {
      res = await fetch(current.toString(), {
        headers: { "User-Agent": "Mozilla/5.0 (compatible; GatherLinkPreview/1.0; +https://eiquoab.xyz)" },
        redirect: "manual",
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timeout);
    }
    if (res.status >= 300 && res.status < 400 && res.headers.get("location")) {
      current = assertSafeUrl(new URL(res.headers.get("location")!, current).toString());
      continue;
    }
    return res;
  }
  throw new Error("Too many redirects");
}

function metaTag(html: string, ...properties: string[]): string | null {
  for (const prop of properties) {
    const re = new RegExp(
      `<meta[^>]+(?:property|name)=["']${prop}["'][^>]+content=["']([^"']*)["']`,
      "i",
    );
    const match = html.match(re) ?? html.match(new RegExp(`<meta[^>]+content=["']([^"']*)["'][^>]+(?:property|name)=["']${prop}["']`, "i"));
    if (match?.[1]) return match[1];
  }
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, content-type, apikey",
      },
    });
  }
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  let url: string;
  try {
    const body = await req.json();
    url = String(body.url ?? "");
    assertSafeUrl(url); // throws if invalid, non-http(s), or an internal/private target
  } catch {
    return jsonResponse({ error: "A valid, public http(s) 'url' is required" }, 400);
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: cached } = await supabase.from("link_previews").select("*").eq("url", url).maybeSingle();
  if (cached && Date.now() - new Date(cached.fetched_at).getTime() < 1000 * 60 * 60 * 24 * 7) {
    return jsonResponse(cached);
  }

  try {
    const res = await safeFetch(url);
    const html = (await res.text()).slice(0, 200_000); // don't parse megabytes of body

    const preview = {
      url,
      title: metaTag(html, "og:title", "twitter:title") ?? html.match(/<title[^>]*>([^<]*)<\/title>/i)?.[1] ?? null,
      description: metaTag(html, "og:description", "twitter:description", "description"),
      image_url: metaTag(html, "og:image", "twitter:image"),
      site_name: metaTag(html, "og:site_name") ?? new URL(url).hostname.replace(/^www\./, ""),
      fetched_at: new Date().toISOString(),
    };

    await supabase.from("link_previews").upsert(preview);
    return jsonResponse(preview);
  } catch (err) {
    // Still return something usable — a bare link card beats no card.
    const fallback = {
      url,
      title: null,
      description: null,
      image_url: null,
      site_name: new URL(url).hostname.replace(/^www\./, ""),
      fetched_at: new Date().toISOString(),
    };
    return jsonResponse(fallback);
  }
});
