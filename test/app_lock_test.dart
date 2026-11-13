import 'package:bro_chat/services/app_lock.dart';
import 'package:bro_chat/ui/errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PIN hash is stable and not plaintext', () {
    expect(AppLock.hashPin('1234'), AppLock.hashPin('1234'));
    expect(AppLock.hashPin('1234'), isNot(AppLock.hashPin('1235')));
    expect(AppLock.hashPin('1234'), isNot('1234'));
  });

  test('schema-cache last_message_at errors are softened', () {
    expect(
      friendlyErrorMessage(
        'Could not find the \'last_message_at\' column of \'conversations\' in the schema cache',
      ),
      "That message didn't land cleanly. Try sending it once more.",
    );
  });
}
