// Retry only transient transport/provider failures. Never log a provider body.
export async function deliver(
  send: () => Promise<Response>,
  wait = (ms: number) => new Promise((r) => setTimeout(r, ms)),
) {
  for (let attempt = 0; attempt < 3; attempt++) {
    let delay = 500 * 2 ** attempt + Math.random() * 250;
    try {
      const response = await send();
      if (response.ok) return "sent";
      const body = await response.json().catch(() => ({}));
      if (
        body.error?.details?.some((d: { errorCode?: string }) =>
          d.errorCode === "UNREGISTERED"
        )
      ) return "invalid";
      if (
        response.status !== 429 && response.status !== 408 &&
        response.status < 500
      ) return "permanent";
      const retry = Number(response.headers.get("retry-after")) * 1000;
      if (retry > 5000) return "transient";
      delay = Math.max(delay, retry || 0);
    } catch { /* timeout or network failure */ }
    if (attempt < 2) await wait(delay);
  }
  return "transient";
}
