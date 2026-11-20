const { test } = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const vm = require("node:vm");
for (const file of ["openpgp.min.js", "bridge.js"]) {
  vm.runInThisContext(readFileSync(`assets/crypto/${file}`, "utf8"));
}
const run = (args) => broCrypto(JSON.stringify(args));
test("v2: registered offline devices, authenticated contexts and no downgrade", async () => {
  const [alice, bob, tablet, stranger] = await Promise.all(
    Array.from(
      { length: 4 },
      async () => JSON.parse(await run({ op: "generate" })),
    ),
  );
  const ctx = {
    v: 2,
    id: "event",
    conversation: "conversation",
    reply: null,
    sender: "alice",
    purpose: "message",
    recipients: "device list",
    revision: 0,
  };
  const seal = (keys) =>
    run({
      op: "seal",
      secret: alice.privateKey,
      keys,
      body: { ...ctx, text: "private words" },
    });
  const keys = [alice.publicKey, bob.publicKey, tablet.publicKey];
  const packet = await seal(keys);
  assert.ok(!packet.includes("private words"));
  assert.notEqual(packet, await seal(keys));
  const open = (who, extra = {}) =>
    run({
      op: "open",
      secret: who.privateKey,
      signer: alice.publicKey,
      packet,
      context: ctx,
      ...extra,
    });
  for (const device of [alice, bob, tablet]) {
    assert.equal(await open(device), "private words");
  }
  await assert.rejects(open(stranger));
  await assert.rejects(open(bob, { signer: tablet.publicKey }));
  for (
    const k of [
      "id",
      "conversation",
      "reply",
      "purpose",
      "sender",
      "recipients",
      "revision",
    ]
  ) await assert.rejects(open(bob, { context: { ...ctx, [k]: "replay" } }));
  await assert.rejects(open(bob, { packet: "broken" }));
  await assert.rejects(
    open(bob, {
      packet: packet.replace(/(.{10})(?=\n-----END)/, "AAAAAAAAAA"),
    }),
  );
  await assert.rejects(seal([]));
  await assert.rejects(seal(["not a key"]));
  assert.notEqual(
    await run({ op: "fingerprint", key: bob.publicKey }),
    await run({ op: "fingerprint", key: stranger.publicKey }),
  );
});
test("vendored browser library matches the reviewed npm artifact", () => {
  const hash = require("node:crypto").createHash("sha256").update(
    readFileSync("assets/crypto/openpgp.min.js"),
  ).digest("hex");
  assert.equal(
    hash,
    "e19bf4f04f34f24caded3ff3f3643099538b2674a0a94221e2faca75ac3e4aa1",
  );
});
