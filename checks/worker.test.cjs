const test = require("node:test"),
  assert = require("node:assert/strict"),
  vm = require("node:vm"),
  fs = require("node:fs");
const scope = "https://example.test/chat-app/app/",
  id = "5f2058ab-7650-4c28-96cb-c39317e02f4d";
function worker(hasTab) {
  const handlers = {}, shown = [], opened = [];
  let focused = false;
  const tab = {
    url: scope,
    postMessage: (m) => opened.push(m.broNotice.route.conversation_id),
    async navigate(u) {
      opened.push(u);
      return this;
    },
    async focus() {
      focused = true;
    },
  };
  const self = {
    addEventListener: (n, cb) => handlers[n] = cb,
    registration: {
      scope,
      async showNotification(title, options) {
        shown.push({ title, options });
      },
    },
    clients: {
      async matchAll() {
        return hasTab ? [tab] : [];
      },
      openWindow: (u) => opened.push(u),
    },
  };
  vm.runInNewContext(fs.readFileSync("web/service-worker.js", "utf8"), {
    self,
    URL,
    URLSearchParams,
  });
  return {
    shown,
    opened,
    focused: () => focused,
    async push(data) {
      let p;
      handlers.push({
        data: { json: () => ({ data }) },
        waitUntil: (v) => p = v,
      });
      await p;
    },
    async click(data) {
      let p;
      handlers.notificationclick({
        notification: { data, close() {} },
        waitUntil: (v) => p = v,
      });
      await p;
    },
  };
}
test("worker shows only generic text with a stable notification tag", async () => {
  const w = worker(false),
    data = {
      conversation_id: id,
      message_id: id,
      recipient_user_id: id,
      title: "private",
      url: "https://invalid.test",
    };
  await w.push(data);
  await w.push(data);
  assert.equal(w.shown.length, 2);
  assert.equal(w.shown[0].options.tag, w.shown[1].options.tag);
  assert.ok(!JSON.stringify(w.shown).includes("private"));
  await w.push({ conversation_id: "bad" });
  assert.equal(w.shown.length, 2);
});
for (const exists of [true, false]) {
  test(`click routes through app shell (existing tab=${exists})`, async () => {
    const w = worker(exists);
    await w.click({ conversation_id: "../private", recipient_user_id: id });
    assert.equal(w.opened.length, 0);
    await w.click({
      conversation_id: id,
      recipient_user_id: id,
      url: "https://invalid.test",
    });
    assert.equal(
      w.opened[0],
      exists ? id : `${scope}?conversation_id=${id}&recipient_user_id=${id}`,
    );
    assert.equal(w.focused(), exists);
  });
}
