import { deepStrictEqual, strictEqual } from "node:assert";
import { classify, payload, retryDelay } from "./delivery.ts";

Deno.test("retry classification and capped attempt schedule", () => {
  deepStrictEqual(
    [200, 400, 403, 408, 429, 500, 503].map((status) => classify(status, null)),
    ["sent", "discarded", "discarded", "retry", "retry", "retry", "retry"],
  );
  strictEqual(
    classify(404, { error: { details: [{ errorCode: "UNREGISTERED" }] } }),
    "invalid",
  );
  strictEqual(classify(404, {}), "discarded");
  strictEqual(retryDelay(1, null, 0, 0), 30000);
  strictEqual(retryDelay(2, "120", 0, 0), 120000);
});
Deno.test("generic native alert and data-only browser alert have no content or sender", () => {
  const job = {
    id: "1",
    attempts: 1,
    token: "opaque",
    platform: "web",
    device_id: "device",
    recipient_id: "owner",
    conversation_id: "dm",
    source_id: "call",
    kind: "missed_call" as const,
    expires_at: "2030-01-01T00:00:10.000Z",
    content: "should never reach FCM",
    sender_id: "peer",
  };
  const time = Date.parse("2030-01-01T00:00:00.000Z");
  const web = payload(job, time);
  strictEqual("notification" in web, false);
  strictEqual("webpush" in web && web.webpush.headers.TTL, "10");
  strictEqual("call_id" in web.data && web.data.call_id, "call");
  strictEqual(web.data.event_id, "missed_call-call");
  strictEqual(JSON.stringify(web).includes(job.content), false);
  strictEqual(JSON.stringify(web).includes("sender_id"), false);
  const android = payload({ ...job, platform: "android" }, time);
  strictEqual(
    "notification" in android && android.notification.body,
    "You missed a call.",
  );
});
