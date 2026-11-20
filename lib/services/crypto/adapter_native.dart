import 'package:flutter/services.dart';

Future<String> runCrypto(String input) async =>
    (await const MethodChannel('bro/openpgp')
        .invokeMethod<String>('run', input))!;
