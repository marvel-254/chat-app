// Do not trust URLs from a push. Flutter validates the recipient AND live
// membership under its current auth session for both delivery and navigation.
globalThis.broListenForNotices = (callback) => {
  navigator.serviceWorker?.addEventListener("message", (event) => {
    if (event.origin === location.origin && event.data?.broNotice) {
      callback(JSON.stringify(event.data.broNotice));
    }
  });
  const url = new URL(location.href);
  if (url.searchParams.has("conversation_id")) {
    url.searchParams.delete("conversation_id");
    url.searchParams.delete("recipient_user_id");
    history.replaceState(history.state, "", url);
  }
};
