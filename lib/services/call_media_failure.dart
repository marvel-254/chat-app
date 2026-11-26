/// Typed classification of getUserMedia failures so call screens can show a
/// precise recovery action instead of a generic "could not start call".
library;

enum CallMediaFailureKind {
  permissionDenied,
  deviceNotFound,
  deviceBusy,
  unsupported,
  unknown,
}

class CallMediaFailure implements Exception {
  const CallMediaFailure(this.kind, this.message);

  final CallMediaFailureKind kind;
  final String message;

  @override
  String toString() => 'CallMediaFailure($kind): $message';
}

CallMediaFailureKind classifyMediaError(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('notallowed') ||
      text.contains('permission') ||
      text.contains('denied') ||
      text.contains('securityerror')) {
    return CallMediaFailureKind.permissionDenied;
  }
  if (text.contains('notfound') ||
      text.contains('devicesnotfound') ||
      text.contains('no device') ||
      text.contains('enodev')) {
    return CallMediaFailureKind.deviceNotFound;
  }
  if (text.contains('notreadable') ||
      text.contains('trackstart') ||
      text.contains('busy') ||
      text.contains('ebusy')) {
    return CallMediaFailureKind.deviceBusy;
  }
  if (text.contains('notsupported') ||
      text.contains('typeerror') ||
      text.contains('unsupported')) {
    return CallMediaFailureKind.unsupported;
  }
  return CallMediaFailureKind.unknown;
}

CallMediaFailure describeMediaError(Object error, {required bool video}) {
  final kind = classifyMediaError(error);
  final device = video ? 'camera and microphone' : 'microphone';
  switch (kind) {
    case CallMediaFailureKind.permissionDenied:
      return CallMediaFailure(
        kind,
        'Access to your $device was denied. Allow it in your browser or system settings, then try again.',
      );
    case CallMediaFailureKind.deviceNotFound:
      return CallMediaFailure(
        kind,
        'No $device was found. Connect a device or use audio only, then try again.',
      );
    case CallMediaFailureKind.deviceBusy:
      return CallMediaFailure(
        kind,
        'Your $device is in use by another app. Close it and try again.',
      );
    case CallMediaFailureKind.unsupported:
      return CallMediaFailure(
        kind,
        'This browser does not support the required call hardware.',
      );
    case CallMediaFailureKind.unknown:
      return CallMediaFailure(
        kind,
        'Could not start your $device. Check the connection and try again.',
      );
  }
}
