import { createClient } from "npm:@supabase/supabase-js@2";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
};
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  const reply = (obj: unknown, status: number) =>
    Response.json(obj, { status, headers: cors });
  if (req.method !== "POST") return reply({}, 405);
  try {
    const auth = req.headers.get("authorization");
    if (!auth?.startsWith("Bearer ")) return reply({}, 401);
    const db = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        global: { headers: { Authorization: auth } },
        auth: { persistSession: false },
      },
    );
    const { data: { user } } = await db.auth.getUser(auth.slice(7));
    if (!user) return reply({}, 401);
    const { conversation_id } = await req.json();
    const { data: ok, error } = await db.rpc("claim_call_relay", {
      p_conversation: conversation_id,
    });
    if (error || !ok) return reply({}, 403);
    const urls = (Deno.env.get("TURN_URLS") ?? "").split(",").map((s) =>
      s.trim()
    );
    const secret = Deno.env.get("TURN_SHARED_SECRET");
    if (
      !secret ||
      !urls.every((s) =>
        /^turns?:[a-z0-9.-]+:\d+(?:\?transport=(udp|tcp))?$/i.test(s)
      )
    ) return reply({ error: "Relay not configured" }, 503);
    const username = `${
      Math.floor(Date.now() / 1000) + 3600
    }:${crypto.randomUUID()}`;
    const enc = new TextEncoder();
    const key = await crypto.subtle.importKey(
      "raw",
      enc.encode(secret),
      { name: "HMAC", hash: "SHA-1" },
      false,
      ["sign"],
    );
    const credential = btoa(
      String.fromCharCode(
        ...new Uint8Array(
          await crypto.subtle.sign("HMAC", key, enc.encode(username)),
        ),
      ),
    );
    return reply({
      iceServers: [{ urls, username, credential }, {
        urls: "stun:stun.l.google.com:19302",
      }],
    }, 200);
  } catch {
    return reply({ error: "Relay unavailable" }, 503);
  }
});
