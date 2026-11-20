import { deliver } from "./delivery.ts";
Deno.test("bounded retry, terminal errors and invalid registrations", async () => {
  for (
    const [statuses, outcome, attempts] of [
      [[503, 429, 200], "sent", 3],
      [[400], "permanent", 1],
      [[500, 500, 500], "transient", 3],
      [[404], "invalid", 1],
    ] as const
  ) {
    let n = 0;
    const result = await deliver(
      async () =>
        new Response(
          JSON.stringify({
            error: {
              details: statuses[n] === 404
                ? [{ errorCode: "UNREGISTERED" }]
                : [],
            },
          }),
          { status: statuses[n++] },
        ),
      () => Promise.resolve(),
    );
    if (result !== outcome || n !== attempts) {
      throw Error("Incorrect classification");
    }
  }
});
