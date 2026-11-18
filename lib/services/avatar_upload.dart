import 'dart:typed_data';
import 'dart:ui' as ui;

/// Portable image formats supported for profile photos on Android and web.
enum AvatarFormat {
  jpeg('jpg', 'image/jpeg'),
  png('png', 'image/png'),
  webp('webp', 'image/webp'),
  gif('gif', 'image/gif');

  const AvatarFormat(this.extension, this.contentType);

  final String extension;
  final String contentType;
}

const maxAvatarBytes = 5 * 1024 * 1024;

/// Determine the content type from bytes rather than the picker filename.
AvatarFormat avatarFormat(Uint8List bytes) {
  if (bytes.length > maxAvatarBytes) {
    throw ArgumentError('Profile photos must be 5 MB or smaller.');
  }

  bool matches(int offset, List<int> signature) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  if (matches(0, const [0xff, 0xd8, 0xff])) return AvatarFormat.jpeg;
  if (matches(0, const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    return AvatarFormat.png;
  }
  if (matches(0, const [0x52, 0x49, 0x46, 0x46]) &&
      matches(8, const [0x57, 0x45, 0x42, 0x50])) {
    return AvatarFormat.webp;
  }
  if (matches(0, const [0x47, 0x49, 0x46, 0x38, 0x37, 0x61]) ||
      matches(0, const [0x47, 0x49, 0x46, 0x38, 0x39, 0x61])) {
    return AvatarFormat.gif;
  }
  throw ArgumentError('Choose a JPEG, PNG, WebP, or GIF profile photo.');
}

/// Reject corrupt image files before writing to Storage or updating a profile.
Future<AvatarFormat> validateAvatarImage(Uint8List bytes) async {
  final format = avatarFormat(bytes);
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1);
    try {
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
  } catch (_) {
    throw ArgumentError("That photo couldn't be opened. Try another image.");
  }
  return format;
}

/// Resolve only avatar filenames managed by this app, in the user's own
/// bucket folder. Never remove a status upload, external URL or nested path.
String? managedAvatarPath(String? url, String folderUrl, String userId) {
  if (url == null) return null;
  final avatar = Uri.tryParse(url);
  final folder = Uri.parse(folderUrl);
  final prefix = folder.path.endsWith('/') ? folder.path : '${folder.path}/';
  if (avatar == null ||
      avatar.scheme != folder.scheme ||
      avatar.authority != folder.authority ||
      !avatar.path.startsWith(prefix)) {
    return null;
  }
  final filename = avatar.path.substring(prefix.length);
  if (!RegExp(
          r'^avatar(?:-[0-9a-f-]{36})?\.(?:jpg|jpeg|png|webp|gif|heic|heif)$')
      .hasMatch(filename)) {
    return null;
  }
  return '$userId/$filename';
}
