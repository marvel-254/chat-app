import 'package:intl/intl.dart';

/// A durable, user-visible installation entry from the linked device registry.
class LinkedDevice {
  const LinkedDevice({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.createdAt,
    required this.lastSeenAt,
    required this.revokedAt,
    required this.isCurrent,
  });

  final String id;
  final String deviceId;
  final String deviceName;
  final String platform;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final DateTime? revokedAt;
  final bool isCurrent;

  bool get isRevoked => revokedAt != null;

  factory LinkedDevice.fromJson(
    Map<String, dynamic> json, {
    String? currentDeviceId,
  }) {
    return LinkedDevice(
      id: json['id'] as String,
      deviceId: json['device_id'] as String,
      deviceName: json['device_name'] as String? ?? 'Unknown device',
      platform: json['platform'] as String? ?? 'Unknown platform',
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      lastSeenAt: DateTime.parse(json['last_seen_at'] as String).toLocal(),
      revokedAt: json['revoked_at'] == null
          ? null
          : DateTime.parse(json['revoked_at'] as String).toLocal(),
      isCurrent: currentDeviceId != null &&
          json['device_id'] as String == currentDeviceId,
    );
  }
}

String formatLinkedDeviceTimestamp(DateTime timestamp, {DateTime? now}) {
  final reference = (now ?? DateTime.now()).toLocal();
  final localTimestamp = timestamp.toLocal();
  final elapsed = reference.difference(localTimestamp);
  if (elapsed.isNegative || elapsed.inSeconds < 60) return 'Just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m ago';
  if (elapsed.inHours < 24) return '${elapsed.inHours}h ago';
  if (elapsed.inDays < 7) return '${elapsed.inDays}d ago';
  return DateFormat('MMM d, y').format(localTimestamp);
}
