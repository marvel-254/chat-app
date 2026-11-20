import 'package:bro_chat/services/app_lock.dart';
import 'package:bro_chat/ui/errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const salt = '00112233445566778899aabbccddeeff';

  test('PIN hash is salted, stable and not plaintext', () {
    expect(AppLock.hashPin('1234', salt: salt),
        AppLock.hashPin('1234', salt: salt));
    expect(AppLock.hashPin('1234', salt: salt),
        isNot(AppLock.hashPin('1234', salt: 'ffeeddccbbaa99887766554433221100')));
    expect(AppLock.hashPin('1234', salt: salt),
        isNot(AppLock.hashPin('1235', salt: salt)));
    expect(AppLock.hashPin('1234', salt: salt), isNot('1234'));
  });

  test('legacy hashes remain readable for migration', () {
    expect(AppLock.legacyHashPin('1234'), isNot('1234'));
    expect(AppLock.legacyHashPin('1234'),
        isNot(AppLock.legacyHashPin('1235')));
  });

  test('schema-cache last_message_at errors are softened', () {
    expect(
      friendlyErrorMessage(
        'Could not find the \'last_message_at\' column of \'conversations\' in the schema cache',
      ),
      "That didn't land cleanly. Try once more.",
    );
  });
}
