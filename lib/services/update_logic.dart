import 'dart:typed_data';

/// ABI identifiers (Application Binary Interface) for which this app ships
/// split APKs. Kept in sync with the `--split-per-abi` CI build.
enum ApkAbi {
  arm64V8a,
  armeabiV7a,
  x8664,
}

extension ApkAbiX on ApkAbi {
  /// The ABI tag as it appears in a split-APK filename, e.g. `arm64-v8a`.
  String get tag => switch (this) {
        ApkAbi.arm64V8a => 'arm64-v8a',
        ApkAbi.armeabiV7a => 'armeabi-v7a',
        ApkAbi.x8664 => 'x86_64',
      };
}

/// An update discovered on the GitHub release channel.
class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.versionCode,
    required this.versionName,
    required this.notes,
    required this.assets,
    required this.mandatory,
    required this.publishedAt,
  });

  final String tag;
  final int versionCode;
  final String versionName;
  final String notes;
  final List<ApkAsset> assets;
  final bool mandatory;
  final String? publishedAt;

  ApkAsset? selectFor(ApkAbi abi) => ApkSelector.select(assets, abi);
}

/// A downloadable APK asset inside a release.
class ApkAsset {
  const ApkAsset({
    required this.name,
    required this.url,
    required this.sizeBytes,
  });

  final String name;
  final String url;
  final int sizeBytes;

  /// Human-friendly size, e.g. `12.5 MB`.
  String get sizeLabel {
    if (sizeBytes <= 0) return 'unknown size';
    const mb = 1024 * 1024;
    const kb = 1024;
    if (sizeBytes >= mb) return '${(sizeBytes / mb).toStringAsFixed(1)} MB';
    if (sizeBytes >= kb) return '${(sizeBytes / kb).toStringAsFixed(0)} KB';
    return '$sizeBytes B';
  }
}

/// Pure, deterministic ABI selection so it can be unit-tested in isolation.
class ApkSelector {
  const ApkSelector._();

  static ApkAsset? select(List<ApkAsset> assets, ApkAbi abi) {
    if (assets.isEmpty) return null;
    final tag = abi.tag;
    for (final a in assets) {
      if (_nameContains(a.name, tag)) return a;
    }
    // Fall back to a universal/untagged APK rather than returning nothing.
    for (final a in assets) {
      if (!_hasAnyAbiTag(a.name) && a.name.endsWith('.apk')) return a;
    }
    return null;
  }

  static bool _hasAnyAbiTag(String name) =>
      ApkAbi.values.any((a) => _nameContains(name, a.tag));

  static bool _nameContains(String name, String tag) =>
      name.toLowerCase().contains(tag.toLowerCase());
}

/// Parses the `.apk` assets out of a GitHub Release API `assets` array.
class ApkAssetParser {
  const ApkAssetParser._();

  static List<ApkAsset> fromApi(List<dynamic> rawAssets) {
    final out = <ApkAsset>[];
    for (final raw in rawAssets) {
      if (raw is! Map) continue;
      final name = raw['name'];
      if (name is! String || !name.endsWith('.apk')) continue;
      final url = raw['browser_download_url'];
      if (url is! String || url.isEmpty) continue;
      final size = raw['size'];
      out.add(ApkAsset(
        name: name,
        url: url,
        sizeBytes: size is int && size > 0 ? size : 0,
      ));
    }
    return out;
  }
}

/// Extracts the numeric version code from a version string, tolerating common
/// prefixes: `149`, `v149`, `Release 149`, `1.0.0 (149)` (first numeric run).
///
/// Returns `null` when the string isn't a version at all.
class VersionParser {
  const VersionParser._();

  static int? toCode(String? versionName) {
    final v = versionName;
    if (v == null || v.trim().isEmpty) return null;
    final stripped = v
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
        .replaceAll(RegExp(r'\+.*'), '')
        .replaceAll(RegExp(r'^[a-z\s]*'), '');
    final m = RegExp(r'(\d[\d_.]*)').firstMatch(stripped);
    if (m == null) return null;
    final digits = m.group(1)!.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  /// The trailing integer of a release tag such as `v149`.
  static int? fromTag(String tag) {
    final m = RegExp(r'(\d+)$').firstMatch(tag);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }
}

/// How a remote release relates to the installed version.
enum UpdatePriority {
  /// Remote is older than or equal to installed — no update.
  none,

  /// Newer, can be postponed.
  optional,

  /// Newer and must be installed.
  mandatory,
}

class UpdateDecision {
  const UpdateDecision({required this.priority, this.reason});

  final UpdatePriority priority;
  final String? reason;

  bool get isUpdate => priority != UpdatePriority.none;
}

class UpdatePolicy {
  const UpdatePolicy({
    this.optionalWindow = 5,
    this.rememberPostponeVersionFor = 1,
  });

  /// A release newer than installed by more than this many version codes is
  /// forced even without the `## Mandatory` marker.
  final int optionalWindow;

  /// How many future releases a single "remind me later" suppresses.
  final int rememberPostponeVersionFor;

  UpdateDecision decide({
    required int installedVersionCode,
    required int remoteVersionCode,
    required bool releaseMandatory,
    required bool remindedToSkip,
  }) {
    if (remoteVersionCode <= installedVersionCode) {
      return const UpdateDecision(
        priority: UpdatePriority.none,
        reason: 'installed version is not older',
      );
    }
    if (releaseMandatory) {
      return const UpdateDecision(
        priority: UpdatePriority.mandatory,
        reason: 'release is marked mandatory',
      );
    }
    final delta = remoteVersionCode - installedVersionCode;
    if (delta > optionalWindow) {
      return const UpdateDecision(
        priority: UpdatePriority.mandatory,
        reason: 'version jump exceeds the optional window',
      );
    }
    if (remindedToSkip) {
      return const UpdateDecision(
        priority: UpdatePriority.none,
        reason: 'user postponed this release',
      );
    }
    return const UpdateDecision(
      priority: UpdatePriority.optional,
      reason: 'newer release within the optional window',
    );
  }
}

class ManifestInfo {
  const ManifestInfo({
    required this.packageName,
    required this.versionCode,
    required this.versionName,
  });

  final String? packageName;
  final int? versionCode;
  final String? versionName;
}

/// Parses the package/version attributes out of a binary APK
/// `AndroidManifest.xml` (the format AAPT emits inside the APK).
///
/// Hand-rolled implementation of the AOSP ResourceTypes binary-XML subset:
/// the chunk layout is:
///   resXMLTree_node            (every chunk)
///   resXMLTree_header (type 1) string pool
///   resXMLTree_node  (type 2)  resource map         (skipped)
///   resXMLTree_node  (type 3)  start element
///   resXMLTree_node  (type 4)  end element
///
/// A start element (type 3) payload is:
///   u32 ns        (-1 when absent)
///   u32 name      (string-pool index of the element name)
///   u16 attrStart (offset, 0x14 when there are no attrs)
///   u16 attrSize  (0x14 = 20 bytes per attribute)
///   u16 attrCount
///   u16 idIndex, u16 classIndex   (style vars; u32 style skipped)
///   attributes: attrs each 20 bytes:
///     u32 ns (-1), u32 name (pool idx), u32 rawValue (pool idx or -1),
///     u16 size, u8 res0, u8 dataType, u32 data
///
/// The string pool (type 1) is:
///   header (8) | u32 stringCount | u32 styleCount | u32 flags | u32
///   stringsStart | u32 stylesStart | offsets[stringCount] | styles |
///   string data. `stringsStart` is relative to the start of the chunk
///   (the top of the 8-byte header). flags bit 8 (0x100) = UTF-8 strings.
///   Each string length prefix is 1 byte, extended to 2 if the high bit is
///   set (0x8000 for UTF-16, 0x80 for UTF-8).
class ManifestParser {
  const ManifestParser._();

  static ManifestInfo? parse(Uint8List bytes) {
    try {
      if (bytes.length < 8) return null;
      final r = _Reader(bytes);
      final headType = r.u16();
      final headSize = r.u16();
      final chunkSize = r.u32();
      if (headType != 0x0003 /* RES_XML_TYPE */ || headSize < 8) return null;
      if (chunkSize < 8 || chunkSize > bytes.length) return null;

      // --- string pool ---
      final poolStart = 8;
      final poolHeaderType = r.u16();
      final poolHeaderSize = r.u16();
      final poolChunkSize = r.u32();
      if (poolHeaderType != 0x0001 || poolHeaderSize < 28 || poolChunkSize < 28) {
        return null;
      }
      final stringCount = r.u32();
      final styleCount = r.u32();
      final flags = r.u32();
      final stringsStart = r.u32();
      r.u32(); // stylesStart
      final isUtf8 = (flags & 0x100) != 0;
      final utf16Flag = 0x8000;
      final utf8Flag = 0x80;

      List<int> offsets = [];
      for (var i = 0; i < stringCount; i++) {
        offsets.add(r.u32());
      }
      if (styleCount > 0) r.skip(styleCount * 4);

      // The pool header + offsets + string data + styles form one chunk.
      // Move the top-level reader past the whole chunk before walking nodes.
      final poolChunkEnd = poolStart + poolChunkSize;
      if (poolChunkEnd > bytes.length) return null;
      r.skip(poolChunkEnd - r._pos);

      // Absolute position of string data within `bytes`.
      final dataBase = poolStart + stringsStart;

      String readStringAt(int offset) {
        var p = dataBase + offset;
        int len = 0;
        if (isUtf8) {
          // UTF-8 pool stores two length prefixes: UTF-16 char length, then
          // UTF-8 byte length. Only the second is used to bound the bytes.
          int readVarlen(int flag) {
            var n = bytes[p++];
            if (n & flag != 0) {
              n = ((n & (flag - 1)) << 8) | bytes[p++];
            }
            return n;
          }

          readVarlen(utf8Flag); // UTF-16 char count (unused)
          len = readVarlen(utf8Flag); // UTF-8 byte count
          final end = p + len;
          if (end > bytes.length) return '';
          // ASCII fast path; decode multi-byte UTF-8 if present.
          final buffer = StringBuffer();
          var i = p;
          while (i < end) {
            final b = bytes[i];
            if (b < 0x80) {
              buffer.writeCharCode(b);
              i++;
            } else {
              int bytesNeeded = 0;
              if ((b & 0xE0) == 0xC0) {
                bytesNeeded = 1;
              } else if ((b & 0xF0) == 0xE0) {
                bytesNeeded = 2;
              } else if ((b & 0xF8) == 0xF0) {
                bytesNeeded = 3;
              }
              if (i + bytesNeeded >= end) break;
              var cp = b & (0x7F >> bytesNeeded);
              for (var k = 1; k <= bytesNeeded; k++) {
                cp = (cp << 6) | (bytes[i + k] & 0x3F);
              }
              buffer.writeCharCode(cp);
              i += bytesNeeded + 1;
            }
          }
          return buffer.toString();
        } else {
          len = (bytes[p] & 0xFF) | (bytes[p + 1] << 8);
          p += 2;
          if (len & utf16Flag != 0) {
            len = ((len & 0x7FFF) << 16) |
                ((bytes[p] & 0xFF) | (bytes[p + 1] << 8));
            p += 2;
          }
          final end = p + len * 2;
          if (end > bytes.length) return '';
          final buffer = StringBuffer();
          var i = p;
          while (i < end) {
            buffer.writeCharCode((bytes[i] & 0xFF) | (bytes[i + 1] << 8));
            i += 2;
          }
          return buffer.toString();
        }
      }

      String? poolString(int index) {
        if (index < 0 || index >= stringCount) return null;
        return readStringAt(offsets[index]);
      }

      String? shortName(int index) {
        final raw = poolString(index);
        if (raw == null) return null;
        final dot = raw.lastIndexOf('.');
        final short = dot >= 0 ? raw.substring(dot + 1) : raw;
        return short.isEmpty ? null : short.toLowerCase();
      }

      // --- remaining chunks: locate the start element of <manifest> ---
      String? packageName;
      int? versionCode;
      String? versionName;

      while (r.remaining >= 8) {
        final type = r.u16();
        final headerSize = r.u16();
        final size = r.u32();
        if (size < 8 || headerSize < 8 || size - 8 > r.remaining) break;
        final bodyLen = size - 8;
        if (type == 0x0102 /* RES_XML_START_ELEMENT */ && versionCode == null) {
          final elementStart = r._pos - 8; // node header (8) already consumed
          final e = _Reader(bytes.sublist(elementStart, elementStart + size));
          e.skip(8); // chunk header: type + headerSize + size
          e.skip(8); // lineNumber + comment
          e.u32(); // ns (-1 for a no-namespace element)
          e.u32(); // name
          final attrStart = e.u16();
          final attrSize = e.u16();
          final attrCount = e.u16();
          e.u16(); // idIndex
          e.u16(); // classIndex
          e.u32(); // style
          if (attrSize >= 20 && attrCount <= 200) {
            // Attributes live at (elementStart + 16 + attributeStart): the
            // ResXMLTree_node header is 16 bytes (chunk header + line + comment),
            // then the ResXMLTree_attrExt struct; attributeStart is relative to
            // that struct, not to the body we skipped.
            final attrBase = elementStart + 16 + attrStart;
            for (var i = 0; i < attrCount; i++) {
              final a = _Reader(bytes.sublist(
                  attrBase + i * attrSize, attrBase + (i + 1) * attrSize));
              final aNs = a.u32();
              final aName = a.u32();
              final rawValue = a.u32();
              a.u16(); // size
              a.u8(); // res0
              a.u8(); // dataType
              final data = a.u32();
              final key = shortName(aName);
              switch (key) {
                case 'package':
                  if (aNs == 0xFFFFFFFF && rawValue != 0xFFFFFFFF) {
                    packageName ??= poolString(rawValue);
                  }
                  break;
                case 'versioncode':
                  versionCode ??= data.toInt();
                  break;
                case 'versionname':
                  if (rawValue != 0xFFFFFFFF) {
                    versionName ??= poolString(rawValue);
                  } else {
                    versionName ??= '$data';
                  }
                  break;
              }
            }
          }
          if (versionCode != null) break;
        }
        r.skip(bodyLen);
      }

      return ManifestInfo(
        packageName: packageName,
        versionCode: versionCode,
        versionName: versionName ?? (versionCode?.toString() ?? ''),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Sequential big-endian reader with bounds checking that throws on underflow
/// (caught by [ManifestParser.parse]).
class _Reader {
  _Reader(List<int> bytes) : _bytes = bytes;

  final List<int> _bytes;
  int _pos = 0;

  int get remaining => _bytes.length - _pos;

  int u8() {
    if (_pos + 1 > _bytes.length) throw _underflow();
    return _bytes[_pos++] & 0xFF;
  }

  int u16() {
    if (_pos + 2 > _bytes.length) throw _underflow();
    final v = (_bytes[_pos] & 0xFF) | (_bytes[_pos + 1] << 8);
    _pos += 2;
    return v & 0xFFFF;
  }

  int u32() {
    if (_pos + 4 > _bytes.length) throw _underflow();
    final v = _bytes[_pos] & 0xFF |
        (_bytes[_pos + 1] & 0xFF) << 8 |
        (_bytes[_pos + 2] & 0xFF) << 16 |
        (_bytes[_pos + 3] & 0xFF) << 24;
    _pos += 4;
    return v & 0xFFFFFFFF;
  }

  void skip(int n) {
    if (n < 0 || _pos + n > _bytes.length) throw _underflow();
    _pos += n;
  }

  List<int> readBytes(int n) {
    if (n < 0 || _pos + n > _bytes.length) throw _underflow();
    final out = _bytes.sublist(_pos, _pos + n);
    _pos += n;
    return out;
  }

  Exception _underflow() => const FormatException('binary xml underflow');
}
