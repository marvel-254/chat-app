export type Delivery = {
  id: string;
  attempts: number;
  token: string;
  platform: string;
  device_id: string;
  recipient_id: string;
  conversation_id: string;
  source_id: string;
  kind: "message" | "incoming_call" | "missed_call" | "friendship_reminder";
  expires_at: string;
};
export function classify(
  status: number,
  body: unknown,
): "sent" | "retry" | "invalid" | "discarded" {
  if (status >= 200 && status < 300) return "sent";
  const error =
    (body as { error?: { details?: { errorCode?: string }[] } } | null)?.error;
  if (
    Array.isArray(error?.details) &&
    error.details.some((d) => d?.errorCode === "UNREGISTERED")
  ) return "invalid";
  if ([401, 408, 429].includes(status) || status >= 500) return "retry";
  return "discarded";
}
export function retryDelay(
  attempt: number,
  retryAfter: string | null,
  now = Date.now(),
  jitter = Math.random(),
): number {
  const seconds = retryAfter !== null && /^\d+$/.test(retryAfter)
    ? Number(retryAfter) * 1000
    : retryAfter
    ? Date.parse(retryAfter) - now
    : 0;
  return Math.max(
    Math.min(900_000, 30_000 * 2 ** (attempt - 1)) + Math.floor(5000 * jitter),
    seconds || 0,
  );
}
const messages = {
  message: "You have a new message.",
  incoming_call: "You have an incoming call.",
  missed_call: "You missed a call.",
  friendship_reminder: "A friendship anniversary is today.",
};
export function payload(job: Delivery, now = Date.now()) {
  const call = job.kind === "incoming_call" || job.kind === "missed_call";
  const eventTag = `${job.kind}-${job.source_id}`;
  const body = messages[job.kind];
  const ttl = Math.max(0, Math.ceil((Date.parse(job.expires_at) - now) / 1000));
  return {
    token: job.token,
    data: {
      kind: job.kind,
      conversation_id: job.conversation_id,
      recipient_user_id: job.recipient_id,
      event_id: eventTag,
      ...(call ? { call_id: job.source_id } : { message_id: job.source_id }),
      expires_at: job.expires_at,
    },
    ...(job.platform === "web"
      ? { webpush: { headers: { TTL: String(ttl) } } }
      : {
        notification: { title: "BRO", body },
        android: {
          priority: call ? "HIGH" : "NORMAL",
          ttl: `${ttl}s`,
          notification: {
            tag: eventTag,
            visibility: "PRIVATE",
            ...(call ? { channel_id: "bro_calls", sound: "default" } : {}),
          },
        },
        apns: {
          headers: {
            "apns-expiration": String(
              Math.floor(Date.parse(job.expires_at) / 1000),
            ),
            "apns-collapse-id": eventTag,
          },
        },
      }),
  };
}
