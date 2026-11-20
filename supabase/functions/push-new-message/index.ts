import { createClient } from "npm:@supabase/supabase-js@2.89.0";

import { classify, type Delivery, payload, retryDelay } from "./delivery.ts";

type FirebaseServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

const encoder = new TextEncoder();
let cachedAccessToken: { value: string; expiresAt: number } | null = null;

function encodeBase64Url(value: Uint8Array): string {
  let binary = "";
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/,
    "",
  );
}

function encodeJson(value: unknown): string {
  return encodeBase64Url(encoder.encode(JSON.stringify(value)));
}

async function firebaseAccessToken(
  account: FirebaseServiceAccount,
): Promise<string> {
  if (cachedAccessToken && cachedAccessToken.expiresAt > Date.now() + 60_000) {
    return cachedAccessToken.value;
  }

  const privateKey = account.private_key
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replaceAll(/\s/g, "");
  const signingKey = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(privateKey), (character) => character.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const now = Math.floor(Date.now() / 1000);
  const unsignedJwt = `${encodeJson({ alg: "RS256", typ: "JWT" })}.${
    encodeJson({
      iss: account.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    })
  }`;
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    signingKey,
    encoder.encode(unsignedJwt),
  );
  const assertion = `${unsignedJwt}.${
    encodeBase64Url(new Uint8Array(signature))
  }`;
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    signal: AbortSignal.timeout(5000),
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!response.ok) throw new Error("Firebase authorization failed.");
  const result = await response.json();
  cachedAccessToken = {
    value: result.access_token,
    expiresAt: Date.now() + Number(result.expires_in) * 1000,
  };
  return cachedAccessToken.value;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  const secret = Deno.env.get("PUSH_WEBHOOK_SECRET");
  if (!secret || request.headers.get("x-bro-webhook-secret") !== secret) {
    return new Response("Unauthorized", { status: 401 });
  }
  try {
    const account = JSON.parse(
      atob(Deno.env.get("FIREBASE_SERVICE_ACCOUNT_B64") ?? ""),
    ) as FirebaseServiceAccount;
    if (!account.project_id || !account.client_email || !account.private_key) {
      throw new Error();
    }
    const db = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      {
        auth: { persistSession: false, autoRefreshToken: false },
      },
    );
    // Authenticate before leasing so credential misconfiguration does not burn attempts.
    const access = await firebaseAccessToken(account);
    const { data, error } = await db.rpc("claim_bro_push");
    if (error) throw error;
    const deliveries = (data ?? []) as Delivery[];
    const counts = { sent: 0, discarded: 0, retry: 0, ackFailed: 0 };
    for (let i = 0; i < deliveries.length; i += 8) {
      await Promise.all(
        deliveries.slice(i, i + 8).map(async (job) => {
          let outcome: ReturnType<typeof classify> = "retry";
          let retryAfter: string | null = null;
          if (Date.parse(job.expires_at) <= Date.now()) outcome = "discarded";
          else {
            try {
              const response = await fetch(
                `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
                {
                  method: "POST",
                  signal: AbortSignal.timeout(4500),
                  headers: {
                    Authorization: `Bearer ${access}`,
                    "Content-Type": "application/json",
                  },
                  body: JSON.stringify({ message: payload(job) }),
                },
              );
              retryAfter = response.headers.get("Retry-After");
              const result = response.ok
                ? null
                : await response.json().catch(() => null);
              outcome = classify(response.status, result);
              if (response.status === 401) cachedAccessToken = null;
            } catch (_) { /* transient transport error */ }
          }
          if (outcome === "invalid") {
            // Never delete a token that rotated while this delivery was leased.
            const removed = await db.from("bro_push_devices").delete().eq(
              "id",
              job.device_id,
            ).eq("token", job.token);
            if (removed.error) counts.ackFailed++;
            outcome = "discarded";
          }
          if (outcome === "retry" && job.attempts >= 5) outcome = "discarded";
          counts[outcome]++;
          const next = new Date(
            Date.now() + retryDelay(job.attempts, retryAfter),
          ).toISOString();
          const ack = await db.from("bro_push_deliveries").update({
            status: outcome === "retry" ? "pending" : outcome,
            available_at: next,
          }).eq("id", job.id).eq("attempts", job.attempts);
          if (ack.error) counts.ackFailed++;
        }),
      );
    }
    if (deliveries.length) console.info("BRO push batch", counts);
    return Response.json(counts);
  } catch (_) {
    console.error("BRO push worker unavailable");
    return Response.json({ error: "Worker unavailable" }, { status: 503 });
  }
});
