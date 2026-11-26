import 'package:flutter_test/flutter_test.dart';
import 'package:bro_chat/services/call_media_failure.dart';

void main() {
  test('classifies browser getUserMedia errors', () {
    expect(classifyMediaError('NotAllowedError'), CallMediaFailureKind.permissionDenied);
    expect(classifyMediaError('NotFoundError'), CallMediaFailureKind.deviceNotFound);
    expect(classifyMediaError('NotReadableError: track start failed'), CallMediaFailureKind.deviceBusy);
    expect(classifyMediaError('TypeError'), CallMediaFailureKind.unsupported);
    expect(classifyMediaError('something odd'), CallMediaFailureKind.unknown);
  });

  test('messages point to a recovery action', () {
    final denied = describeMediaError('NotAllowedError', video: true);
    expect(denied.kind, CallMediaFailureKind.permissionDenied);
    expect(denied.message, contains('camera and microphone'));
    expect(denied.message, contains('browser or system settings'));

    final busy = describeMediaError('NotReadableError', video: false);
    expect(busy.kind, CallMediaFailureKind.deviceBusy);
    expect(busy.message, contains('another app'));
  });
}
