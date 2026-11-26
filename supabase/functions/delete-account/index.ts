import {
  createClient,
  type SupabaseClient,
} from "npm:@supabase/supabase-js@2.89.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
};

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function deleteStoragePrefix(
  admin: SupabaseClient,
  bucketName: string,
  prefix: string,
): Promise<void> {
  const bucket = admin.storage.from(bucketName);
  const folders = [prefix];
  const files: string[] = [];
  while (folders.length) {
    const folder = folders.pop()!;
    let offset = 0;
    while (true) {
      const { data, error } = await bucket.list(folder, { limit: 100, offset });
      if (error) throw new Error(`Could not clean ${bucketName} storage.`);
      for (const entry of data ?? []) {
        const path = `${folder}/${entry.name}`;
        if (entry.id == null && entry.metadata == null) folders.push(path);
        else files.push(path);
      }
      if ((data?.length ?? 0) < 100) break;
      offset += data!.length;
    }
  }
  for (let index = 0; index < files.length; index += 100) {
    const { error } = await bucket.remove(files.slice(index, index + 100));
    if (error) throw new Error(`Could not clean ${bucketName} storage.`);
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (request.method !== "POST") return json({ error: "Method not allowed." }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = request.headers.get("Authorization");
  if (!url || !anonKey || !serviceKey || !authorization?.startsWith("Bearer ")) {
    return json({ error: "Sign in again before deleting your account." }, 401);
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch (_) {
    return json({ error: "Account deletion confirmation is required." }, 400);
  }
  if (
    typeof body !== "object" ||
    body === null ||
    !("confirmation" in body) ||
    body.confirmation !== "DELETE"
  ) {
    return json({ error: "Account deletion confirmation is required." }, 400);
  }

  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await caller.auth.getUser();
  const user = userData.user;
  if (userError || !user) return json({ error: "Your session has expired. Sign in again." }, 401);

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  try {
    const { data: memberships, error: membershipError } = await admin
      .from("conversation_participants")
      .select("conversation_id")
      .eq("user_id", user.id);
    if (membershipError) throw new Error("Could not clean account data.");

    const conversationIds = [...new Set(
      (memberships ?? []).map((row) => row.conversation_id as string),
    )];
    await Promise.all([
      deleteStoragePrefix(admin, "avatars", user.id),
      deleteStoragePrefix(admin, "profile-media", user.id),
      deleteStoragePrefix(admin, "chat-backgrounds", user.id),
      ...conversationIds.map((id) =>
        deleteStoragePrefix(admin, "chat-files", `${id}/${user.id}`)
      ),
    ]);

    const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
    if (deleteError) throw new Error("Account deletion could not be completed.");
    return json({ deleted: true });
  } catch (error) {
    console.error("Account deletion failed", error);
    return json({ error: error instanceof Error ? error.message : "Account deletion could not be completed." }, 500);
  }
});
