import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyx_chat/services/update_logic.dart';

void main() {
  test('ManifestParser parses real AAPT binary manifest', () async {
    final file = File('test/fixtures/real_manifest.bin');
    final bytes = await file.readAsBytes();
    final info = ManifestParser.parse(bytes);
    expect(info, isNotNull);
    expect(info!.versionCode, 149);
    expect(info.versionName, '1.0.0 (149)');
  });
}
