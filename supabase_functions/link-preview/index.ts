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
    new URL(url); // throws if invalid
  } catch {
    return jsonResponse({ error: "A valid 'url' is required" }, 400);
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: cached } = await supabase.from("link_previews").select("*").eq("url", url).maybeSingle();
  if (cached && Date.now() - new Date(cached.fetched_at).getTime() < 1000 * 60 * 60 * 24 * 7) {
    return jsonResponse(cached);
  }

  try {
    const res = await fetch(url, {
      headers: { "User-Agent": "Mozilla/5.0 (compatible; GatherLinkPreview/1.0; +https://eiquoab.xyz)" },
      redirect: "follow",
    });
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
