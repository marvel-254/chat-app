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
    const { data: allowed, error: quotaError } = await client.rpc(
      "claim_bro_turn",
    );
    if (quotaError) return reply(503, {});
    if (!allowed) return reply(429, {});
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
