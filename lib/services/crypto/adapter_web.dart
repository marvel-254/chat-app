import 'dart:js_interop';

@JS('broCrypto')
external JSPromise<JSString> _crypto(JSString input);

Future<String> runCrypto(String input) async =>
    (await _crypto(input.toJS).toDart).toDart;
