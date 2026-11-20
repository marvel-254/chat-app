import { coturnCredential } from "./credential.ts";
import { createHmac } from "node:crypto";
import { strictEqual } from "node:assert";

Deno.test("coturn REST credentials match standard HMAC and bind the expiry", async () => {
  const user = "1234567890:test-user";
  const expected = createHmac("sha1", "fixture-secret").update(user).digest(
    "base64",
  );
  strictEqual(await coturnCredential("fixture-secret", user), expected);
  strictEqual(
    (await coturnCredential("fixture-secret", "1234567891:test-user")) ===
      expected,
    false,
  );
});
