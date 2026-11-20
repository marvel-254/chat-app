export async function coturnCredential(
  secret: string,
  username: string,
): Promise<string> {
  const encoder = new TextEncoder();
  // coturn TURN REST authentication specifies base64(HMAC-SHA1(secret, username)).
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, encoder.encode(username)),
  );
  return btoa(String.fromCharCode(...signature));
}
