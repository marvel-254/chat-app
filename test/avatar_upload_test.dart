import 'dart:typed_data';

import 'package:bro_chat/services/avatar_upload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recognizes portable photo formats from their byte signatures', () {
    expect(avatarFormat(Uint8List.fromList([0xff, 0xd8, 0xff])),
        AvatarFormat.jpeg);
    expect(
      avatarFormat(
          Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10])),
      AvatarFormat.png,
    );
    expect(
        avatarFormat(Uint8List.fromList('GIF89a'.codeUnits)), AvatarFormat.gif);
    expect(avatarFormat(Uint8List.fromList('RIFF0000WEBP'.codeUnits)),
        AvatarFormat.webp);
  });

  test('rejects empty, unknown, and oversized photos', () {
    expect(() => avatarFormat(Uint8List(0)), throwsArgumentError);
    expect(() => avatarFormat(Uint8List.fromList('not an image'.codeUnits)),
        throwsArgumentError);
    expect(
        () => avatarFormat(Uint8List(maxAvatarBytes + 1)), throwsArgumentError);
  });

  test('a matching signature alone does not pass image validation', () async {
    await expectLater(
      validateAvatarImage(Uint8List.fromList('GIF89a'.codeUnits)),
      throwsArgumentError,
    );
  });

  test('cleanup is limited to managed avatars in the same bucket and folder',
      () {
    const folder =
        'https://img.example/storage/v1/object/public/avatars/alice/';
    expect(managedAvatarPath('${folder}avatar.jpg?v=1', folder, 'alice'),
        'alice/avatar.jpg');
    const file = 'avatar-12345678-1234-1234-1234-123456789abc.webp';
    expect(managedAvatarPath('$folder$file', folder, 'alice'), 'alice/$file');
    expect(managedAvatarPath('${folder}status/a.png', folder, 'alice'), isNull);
    expect(
        managedAvatarPath('${folder}my-status.png', folder, 'alice'), isNull);
    expect(
        managedAvatarPath(
            folder.replaceFirst('alice', 'bob') + file, folder, 'alice'),
        isNull);
    expect(
        managedAvatarPath(
            folder.replaceFirst('img.example', 'outside.example') + file,
            folder,
            'alice'),
        isNull);
  });
}
