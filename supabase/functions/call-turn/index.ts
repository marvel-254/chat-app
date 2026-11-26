import { createClient } from "npm:@supabase/supabase-js@2.89.0";
import { coturnCredential } from "./credential.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
};
Deno.serve(async (request) => {
  const reply = (status: number, data: unknown) =>
    Response.json(data, { status, headers: cors });
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  if (request.method !== "POST") return reply(405, {});
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return reply(401, {});
  try {
    const client = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        global: { headers: { Authorization: authorization } },
        auth: { persistSession: false, autoRefreshToken: false },
      },
    );
    const { data, error } = await client.auth.getUser(authorization.slice(7));
    if (error || !data.user) return reply(401, {});
    const { data: allowed, error: quotaError } = await client.rpc(
      "claim_bro_turn",
    );
    if (quotaError) return reply(503, {});
    if (!allowed) return reply(429, {});

    const cloudflareKeyId = Deno.env.get("CLOUDFLARE_TURN_KEY_ID");
    const cloudflareApiToken = Deno.env.get("CLOUDFLARE_TURN_API_TOKEN");
    if (cloudflareKeyId || cloudflareApiToken) {
      if (!cloudflareKeyId || !cloudflareApiToken) {
        return reply(503, { error: "Relay not configured" });
      }
      const response = await fetch(
        `https://rtc.live.cloudflare.com/v1/turn/keys/${encodeURIComponent(cloudflareKeyId)}/credentials/generate-ice-servers`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${cloudflareApiToken}`,
            "Content-Type": "application/json",
            "User-Agent": "BRO-call-turn/1.0",
          },
          body: JSON.stringify({ ttl: 12 * 60 * 60 }),
          signal: AbortSignal.timeout(6000),
        },
      );
      if (!response.ok) return reply(503, { error: "Relay unavailable" });
      const result = await response.json();
      const relay = Array.isArray(result?.iceServers)
        ? result.iceServers.find((server: Record<string, unknown>) =>
          typeof server.username === "string" &&
          typeof server.credential === "string" &&
          (Array.isArray(server.urls) ? server.urls : [server.urls]).some(
            (url: unknown) => typeof url === "string" &&
              /^(turn|turns):turn\.cloudflare\.com(?::|\?)/.test(url),
          )
        )
        : null;
      const urls = relay
        ? (Array.isArray(relay.urls) ? relay.urls : [relay.urls])
          .filter((url: unknown) => typeof url === "string" &&
            /^(turn|turns):turn\.cloudflare\.com(?::|\?)/.test(url))
        : [];
      if (!relay || urls.length === 0) {
        return reply(503, { error: "Relay unavailable" });
      }
      return reply(200, {
        urls,
        username: relay.username,
        credential: relay.credential,
      });
    }

    // Keep self-hosted coturn compatible for existing deployments.
    const secret = Deno.env.get("TURN_SHARED_SECRET");
    const urls = (Deno.env.get("TURN_URLS") ?? "").split(",").map((s) =>
      s.trim()
    ).filter(Boolean);
    if (
      !secret || urls.length === 0 ||
      !urls.every((url) => /^(turn|turns):[^\s]+$/.test(url))
    ) {
      return reply(503, { error: "Relay not configured" });
    }
    const username = `${Math.floor(Date.now() / 1000) + 3600}:${data.user.id}`;
    return reply(200, {
      urls,
      username,
      credential: await coturnCredential(secret, username),
    });
  } catch (_) {
    return reply(503, {});
  }
});
