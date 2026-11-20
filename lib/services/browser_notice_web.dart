import 'dart:js_interop';

@JS('broListenForNotices')
external void _listen(JSFunction callback);
void listenForBrowserNotices(void Function(String) receive) =>
    _listen(((JSString body) => receive(body.toDart)).toJS);
