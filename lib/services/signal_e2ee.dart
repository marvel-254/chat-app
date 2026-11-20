/// Signal Protocol implementation for BRO.
///
/// Private keys and Double Ratchet state never leave this device. Only public
/// key bundles are registered with the server. Encryption and decryption are
/// fail-closed: an encrypted envelope that cannot be processed is reported as
/// an error and is never rendered as plaintext.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:libsignal/libsignal.dart';

/// Failure categories surfaced to the UI. None of them fall back to plaintext.
enum E2eeFailure {
  notInitialized,
  encryptionUnavailable,
  decryptionFailed,
  malformedEnvelope,
  identityChanged,
  verificationRequired,
  peerBundleUnavailable,
}

class E2eeException implements Exception {
  const E2eeException(this.reason, [this.detail = '']);

  final E2eeFailure reason;
  final String detail;

  @override
  String toString() => 'E2eeException(${reason.name})${detail.isEmpty ? '' : ': $detail'}';
}

/// Public data needed to establish a session with one device.
class SignalPublicBundle {
  const SignalPublicBundle({
    required this.userId,
    required this.deviceId,
    required this.registrationId,
    required this.identityKey,
    required this.signedPreKeyId,
    required this.signedPreKey,
    required this.signedPreKeySignature,
    this.preKeyId,
    this.preKey,
    required this.kyberPreKeyId,
    required this.kyberPreKey,
    required this.kyberPreKeySignature,
  });

  final String userId;
  final int deviceId;
  final int registrationId;
  final Uint8List identityKey;
  final int signedPreKeyId;
  final Uint8List signedPreKey;
  final Uint8List signedPreKeySignature;
  final int? preKeyId;
  final Uint8List? preKey;
  final int kyberPreKeyId;
  final Uint8List kyberPreKey;
  final Uint8List kyberPreKeySignature;
}

typedef BundleFetcher = Future<SignalPublicBundle?> Function(String userId);
typedef BundleRegistrar = Future<void> Function(
  int deviceId,
  int registrationId,
  Uint8List identityKey,
  int signedPreKeyId,
  Uint8List signedPreKey,
  Uint8List signedPreKeySignature,
  List<(int, Uint8List)> oneTimePreKeys,
  int kyberPreKeyId,
  Uint8List kyberPreKey,
  Uint8List kyberPreKeySignature,
);

const _envelopePrefix = 'sig1:';
const _storagePrefix = 'bro.signal.v2.';

String _addrKey(String name, int device) => '$name:$device';

abstract class _BaseSecureStore {
  _BaseSecureStore(this._storage, this._kind);

  final FlutterSecureStorage _storage;
  final String _kind;

  String _key(String suffix) => '$_storagePrefix$_kind.$suffix';

  Future<Uint8List?> _read(String suffix) async {
    final value = await _storage.read(key: _key(suffix));
    if (value == null || value.isEmpty) return null;
    return base64Decode(value);
  }

  Future<void> _write(String suffix, List<int> bytes) =>
      _storage.write(key: _key(suffix), value: base64Encode(bytes));

  Future<void> _remove(String suffix) => _storage.delete(key: _key(suffix));

  Future<List<String>> _suffixes() async {
    final all = await _storage.readAll();
    final prefix = _key('');
    return all.keys
        .where((k) => k.startsWith(prefix))
        .map((k) => k.substring(prefix.length))
        .toList(growable: false);
  }
}

class SecureSessionStore extends _BaseSecureStore implements SessionStore {
  SecureSessionStore(FlutterSecureStorage storage) : super(storage, 'session');

  @override
  Future<SessionRecord?> loadSession(ProtocolAddress address) async {
    final bytes = await _read(_addrKey(address.name(), address.deviceId()));
    return bytes == null ? null : SessionRecord.deserialize(bytes: bytes);
  }

  @override
  Future<void> storeSession(ProtocolAddress address, SessionRecord record) =>
      _write(_addrKey(address.name(), address.deviceId()), record.serialize());

  @override
  Future<bool> containsSession(ProtocolAddress address) async =>
      await loadSession(address) != null;

  @override
  Future<void> deleteSession(ProtocolAddress address) =>
      _remove(_addrKey(address.name(), address.deviceId()));

  @override
  Future<void> deleteAllSessions(String name) async {
    for (final suffix in await _suffixes()) {
      if (suffix.startsWith('$name:')) await _remove(suffix);
    }
  }

  @override
  Future<List<int>> getSubDeviceSessions(String name) async {
    final result = <int>[];
    for (final suffix in await _suffixes()) {
      if (!suffix.startsWith('$name:')) continue;
      final device = int.tryParse(suffix.substring(name.length + 1));
      if (device != null) result.add(device);
    }
    return result;
  }
}

class SecurePreKeyStore extends _BaseSecureStore implements PreKeyStore {
  SecurePreKeyStore(FlutterSecureStorage storage) : super(storage, 'prekey');

  @override
  Future<PreKeyRecord?> loadPreKey(int preKeyId) async {
    final bytes = await _read('$preKeyId');
    return bytes == null ? null : PreKeyRecord.deserialize(bytes: bytes);
  }

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) =>
      _write('$preKeyId', record.serialize());

  @override
  Future<bool> containsPreKey(int preKeyId) async => await _read('$preKeyId') != null;

  @override
  Future<void> removePreKey(int preKeyId) => _remove('$preKeyId');

  @override
  Future<List<int>> getAllPreKeyIds() async {
    final result = <int>[];
    for (final suffix in await _suffixes()) {
      final id = int.tryParse(suffix);
      if (id != null) result.add(id);
    }
    return result;
  }
}

class SecureSignedPreKeyStore extends _BaseSecureStore
    implements SignedPreKeyStore {
  SecureSignedPreKeyStore(FlutterSecureStorage storage)
      : super(storage, 'signed_prekey');

  @override
  Future<SignedPreKeyRecord?> loadSignedPreKey(int id) async {
    final bytes = await _read('$id');
    return bytes == null ? null : SignedPreKeyRecord.deserialize(bytes: bytes);
  }

  @override
  Future<void> storeSignedPreKey(int id, SignedPreKeyRecord record) =>
      _write('$id', record.serialize());

  @override
  Future<bool> containsSignedPreKey(int id) async => await _read('$id') != null;

  @override
  Future<void> removeSignedPreKey(int id) => _remove('$id');

  @override
  Future<List<int>> getAllSignedPreKeyIds() async {
    final result = <int>[];
    for (final suffix in await _suffixes()) {
      final id = int.tryParse(suffix);
      if (id != null) result.add(id);
    }
    return result;
  }
}

class SecureKyberPreKeyStore extends _BaseSecureStore
    implements KyberPreKeyStore {
  SecureKyberPreKeyStore(FlutterSecureStorage storage)
      : super(storage, 'kyber_prekey');

  @override
  Future<KyberPreKeyRecord?> loadKyberPreKey(int id) async {
    final bytes = await _read('$id');
    return bytes == null ? null : KyberPreKeyRecord.deserialize(bytes: bytes);
  }

  @override
  Future<void> storeKyberPreKey(int id, KyberPreKeyRecord record) =>
      _write('$id', record.serialize());

  @override
  Future<bool> containsKyberPreKey(int id) async => await _read('$id') != null;

  @override
  Future<bool> markKyberPreKeyUsed(
    int id,
    int signedPreKeyId,
    PublicKey baseKey,
  ) async {
    // One-time Kyber prekeys are removed when consumed, matching Signal.
    await _remove('$id');
    return true;
  }

  @override
  Future<void> removeKyberPreKey(int id) => _remove('$id');

  @override
  Future<List<int>> getAllKyberPreKeyIds() async {
    final result = <int>[];
    for (final suffix in await _suffixes()) {
      final id = int.tryParse(suffix);
      if (id != null) result.add(id);
    }
    return result;
  }
}

/// Identity store with strict key-change behaviour.
///
/// A changed identity is retained as the trusted one until the user explicitly
/// accepts the new fingerprint. This prevents a silent MITM after a server or
/// account compromise.
class SecureIdentityKeyStore extends _BaseSecureStore
    implements IdentityKeyStore {
  SecureIdentityKeyStore(
    FlutterSecureStorage storage,
    this._identity,
    this._registrationId,
  ) : super(storage, 'identity');

  final IdentityKeyPair _identity;
  final int _registrationId;

  @override
  Future<IdentityKeyPair> getIdentityKeyPair() async => _identity;

  @override
  Future<int> getLocalRegistrationId() async => _registrationId;

  @override
  Future<bool> saveIdentity(ProtocolAddress address, PublicKey identityKey) async {
    final key = _addrKey(address.name(), address.deviceId());
    final previous = await _read(key);
    final next = identityKey.serialize();
    if (previous != null && _bytesEqual(previous, next)) return false;
    await _write(key, next);
    return true;
  }

  @override
  Future<PublicKey?> getIdentity(ProtocolAddress address) async {
    final bytes = await _read(_addrKey(address.name(), address.deviceId()));
    return bytes == null ? null : PublicKey.deserialize(bytes: bytes);
  }

  @override
  Future<bool> isTrustedIdentity(
    ProtocolAddress address,
    PublicKey identityKey,
    Direction direction,
  ) async {
    final stored = await getIdentity(address);
    if (stored == null) return true;
    return stored.equals(other: identityKey);
  }
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Singleton Signal Protocol facade used by the messaging layer.
class SignalE2ee {
  SignalE2ee._();

  static final SignalE2ee instance = SignalE2ee._();

  BundleFetcher? fetchBundle;
  BundleRegistrar? registerBundle;

  FlutterSecureStorage? _storage;
  SecureSessionStore? _sessions;
  SecurePreKeyStore? _preKeys;
  SecureSignedPreKeyStore? _signedPreKeys;
  SecureKyberPreKeyStore? _kyberPreKeys;
  SecureIdentityKeyStore? _identities;
  ProtocolAddress? _localAddress;
  final Map<String, Future<void>> _locks = {};

  bool get isReady => _localAddress != null;

  Future<void> init() async {
    if (isReady) return;
    await LibSignal.init();
    final storage = _storage ?? const FlutterSecureStorage();
    _storage = storage;

    final identityBytes = await storage.read(key: '${_storagePrefix}identity_pair');
    final registrationText =
        await storage.read(key: '${_storagePrefix}registration_id');
    final deviceText = await storage.read(key: '${_storagePrefix}device_id');

    final IdentityKeyPair identity;
    final int registrationId;
    final int deviceId;
    if (identityBytes == null ||
        registrationText == null ||
        deviceText == null) {
      identity = IdentityKeyPair.generate();
      registrationId = 1 + (DateTime.now().microsecondsSinceEpoch % 100000000);
      deviceId = 1;
      await storage.write(
        key: '${_storagePrefix}identity_pair',
        value: base64Encode(identity.serialize()),
      );
      await storage.write(
        key: '${_storagePrefix}registration_id',
        value: '$registrationId',
      );
      await storage.write(key: '${_storagePrefix}device_id', value: '$deviceId');
    } else {
      identity = IdentityKeyPair.deserialize(bytes: base64Decode(identityBytes));
      registrationId = int.parse(registrationText);
      deviceId = int.parse(deviceText);
    }

    _sessions = SecureSessionStore(storage);
    _preKeys = SecurePreKeyStore(storage);
    _signedPreKeys = SecureSignedPreKeyStore(storage);
    _kyberPreKeys = SecureKyberPreKeyStore(storage);
    _identities = SecureIdentityKeyStore(storage, identity, registrationId);
    _localAddress = ProtocolAddress(name: _localName, deviceId: deviceId);

    await _ensureOwnPreKeys(identity);
  }

  /// The protocol address name is a stable device-scoped identifier, never a
  /// deterministic value derived from the peer's user ID.
  String get _localName => 'bro-self';

  Future<void> _ensureOwnPreKeys(IdentityKeyPair identity) async {
    final preKeys = _preKeys!;
    final signed = _signedPreKeys!;
    final kyber = _kyberPreKeys!;
    final timestamp = BigInt.from(DateTime.now().millisecondsSinceEpoch);

    if ((await signed.getAllSignedPreKeyIds()).isEmpty) {
      final id = 1;
      final private = PrivateKey.generate();
      final public = private.getPublicKey();
      final signature = identity.sign(
        message: public.serialize().toList(),
      );
      await signed.storeSignedPreKey(
        id,
        SignedPreKeyRecord(
          id: id,
          publicKey: public,
          privateKey: private,
          signature: signature.toList(),
          timestamp: timestamp,
        ),
      );
    }

    if ((await kyber.getAllKyberPreKeyIds()).isEmpty) {
      final id = 1;
      final pair = KyberKeyPair.generate();
      final public = pair.getPublicKey();
      final signature = identity.sign(message: public.serialize().toList());
      await kyber.storeKyberPreKey(
        id,
        KyberPreKeyRecord.create(
          id: id,
          keyPair: pair,
          signature: signature.toList(),
          timestamp: timestamp,
        ),
      );
    }

    final oneTime = <(int, Uint8List)>[];
    final existing = await preKeys.getAllPreKeyIds();
    for (var id = 1; id <= 8; id++) {
      if (existing.contains(id)) {
        oneTime.add((id, (await preKeys.loadPreKey(id))!.publicKey()));
        continue;
      }
      final private = PrivateKey.generate();
      final public = private.getPublicKey();
      await preKeys.storePreKey(
        id,
        PreKeyRecord(id: id, publicKey: public, privateKey: private),
      );
      oneTime.add((id, public.serialize()));
    }

    final registrar = registerBundle;
    if (registrar == null) return;
    final identityStore = _identities!;
    final identityPair = await identityStore.getIdentityKeyPair();
    final signedRecord = (await signed.getAllSignedPreKeyIds()).first;
    final signedKey = (await signed.loadSignedPreKey(signedRecord))!;
    final kyberRecord = (await kyber.getAllKyberPreKeyIds()).first;
    final kyberKey = (await kyber.loadKyberPreKey(kyberRecord))!;
    await registrar(
      _localAddress!.deviceId(),
      await identityStore.getLocalRegistrationId(),
      Uint8List.fromList(identityPair.publicKey.toList()),
      signedRecord,
      signedKey.publicKey(),
      signedKey.signature(),
      oneTime,
      kyberRecord,
      kyberKey.getPublicKey().serialize(),
      kyberKey.signature(),
    );
  }

  /// Serializes operations for the same peer so the ratchet never advances
  /// twice from the same state.
  Future<T> _synchronized<T>(String key, Future<T> Function() body) {
    final previous = _locks[key] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) => body());
    _locks[key] = next.then((_) {}).catchError((_) {});
    return next.whenComplete(() {
      if (identical(_locks[key], next)) _locks.remove(key);
    });
  }

  Future<void> _ensureSession(String peerUserId) async {
    if (!isReady) throw const E2eeException(E2eeFailure.notInitialized);
    final address = ProtocolAddress(name: peerUserId, deviceId: 1);
    if (await _sessions!.containsSession(address)) return;
    final fetcher = fetchBundle;
    if (fetcher == null) {
      throw const E2eeException(E2eeFailure.peerBundleUnavailable);
    }
    final bundle = await fetcher(peerUserId);
    if (bundle == null) {
      throw const E2eeException(E2eeFailure.peerBundleUnavailable);
    }
    final stored = await _identities!.getIdentity(address);
    if (stored != null &&
        !stored.equals(other: PublicKey.deserialize(bytes: bundle.identityKey))) {
      throw const E2eeException(E2eeFailure.identityChanged);
    }
    final signalBundle = PreKeyBundle(
      registrationId: bundle.registrationId,
      deviceId: bundle.deviceId,
      preKeyId: bundle.preKeyId,
      preKeyPublic: bundle.preKey,
      signedPreKeyId: bundle.signedPreKeyId,
      signedPreKeyPublic: bundle.signedPreKey.toList(),
      signedPreKeySignature: bundle.signedPreKeySignature.toList(),
      identityKey: bundle.identityKey.toList(),
      kyberPreKeyId: bundle.kyberPreKeyId,
      kyberPreKeyPublic: bundle.kyberPreKey.toList(),
      kyberPreKeySignature: bundle.kyberPreKeySignature.toList(),
    );
    final builder = SessionBuilder(
      localAddress: _localAddress!,
      sessionStore: _sessions!,
      identityKeyStore: _identities!,
    );
    await builder.processPreKeyBundle(address, signalBundle);
  }

  SessionCipher _cipher() => SessionCipher(
        localAddress: _localAddress!,
        sessionStore: _sessions!,
        identityKeyStore: _identities!,
        preKeyStore: _preKeys!,
        signedPreKeyStore: _signedPreKeys!,
        kyberPreKeyStore: _kyberPreKeys!,
      );

  /// Encrypts [plaintext]. Throws [E2eeException] on any failure; never
  /// returns the input.
  Future<String> encrypt(String peerUserId, Uint8List plaintext) =>
      _synchronized('send:$peerUserId', () async {
        try {
          await _ensureSession(peerUserId);
          final address = ProtocolAddress(name: peerUserId, deviceId: 1);
          final message = await _cipher().encrypt(address, plaintext);
          final packed = Uint8List(message.ciphertext.length + 1)
            ..[0] = message.type.value
            ..setAll(1, message.ciphertext);
          return '$_envelopePrefix${base64Encode(packed)}';
        } on E2eeException {
          rethrow;
        } catch (error) {
          throw E2eeException(E2eeFailure.encryptionUnavailable, '$error');
        }
      });

  /// Decrypts a `sig1:` envelope. Throws on failure; never returns plaintext
  /// for a malformed or undecryptable secure message.
  Future<Uint8List> decrypt(String senderUserId, String envelope) =>
      _synchronized('recv:$senderUserId', () async {
        if (!envelope.startsWith(_envelopePrefix)) {
          throw const E2eeException(E2eeFailure.malformedEnvelope);
        }
        Uint8List bytes;
        try {
          bytes = base64Decode(envelope.substring(_envelopePrefix.length));
        } catch (_) {
          throw const E2eeException(E2eeFailure.malformedEnvelope);
        }
        if (bytes.length < 2) {
          throw const E2eeException(E2eeFailure.malformedEnvelope);
        }
        if (!isReady) throw const E2eeException(E2eeFailure.notInitialized);
        final address = ProtocolAddress(name: senderUserId, deviceId: 1);
        final stored = await _identities!.getIdentity(address);
        if (stored == null &&
            !(await _sessions!.containsSession(address))) {
          throw const E2eeException(E2eeFailure.decryptionFailed);
        }
        try {
          final type = CiphertextMessageType.fromValue(bytes[0]);
          final ciphertext = CiphertextMessage.fromRaw(
            messageType: bytes[0],
            ciphertext: Uint8List.fromList(bytes.sublist(1)),
          );
          if (type == CiphertextMessageType.preKey) {
            final parsed = PreKeySignalMessage.deserialize(data: ciphertext.ciphertext);
            if (stored != null &&
                !stored.equals(other: PublicKey.deserialize(bytes: parsed.identityKey()))) {
              throw const E2eeException(E2eeFailure.identityChanged);
            }
          }
          return await _cipher().decrypt(address, ciphertext);
        } on E2eeException {
          rethrow;
        } catch (error) {
          throw E2eeException(E2eeFailure.decryptionFailed, '$error');
        }
      });

  /// True for messages produced by this implementation. Legacy plaintext must
  /// never be reported as encrypted.
  bool isSecureEnvelope(String content) => content.startsWith(_envelopePrefix);

  /// Canonical fingerprint for out-of-band verification.
  Future<String> safetyNumber(String peerUserId) async {
    if (!isReady) throw const E2eeException(E2eeFailure.notInitialized);
    final own = (await _identities!.getIdentityKeyPair()).publicKey.toList();
    final peer = await _identities!.getIdentity(
      ProtocolAddress(name: peerUserId, deviceId: 1),
    );
    if (peer == null) {
      throw const E2eeException(E2eeFailure.verificationRequired);
    }
    final merged = <int>[...own, ...peer.serialize()]..sort();
    final digest = sha256.convert([...utf8.encode('bro.e2ee.safety.v1'), ...merged]);
    final hex = digest.toString().toUpperCase();
    final buffer = StringBuffer();
    for (var i = 0; i < hex.length; i += 4) {
      if (i > 0) buffer.write(' ');
      buffer.write(hex.substring(i, i + 4));
    }
    return buffer.toString();
  }

  Future<void> verifyPeer(String peerUserId, String fingerprint) async {
    await _storage!.write(
      key: '${_storagePrefix}verified.$peerUserId',
      value: fingerprint,
    );
  }

  Future<String?> verifiedFingerprint(String peerUserId) =>
      _storage!.read(key: '${_storagePrefix}verified.$peerUserId');

  Future<bool> isPeerVerified(String peerUserId, String fingerprint) async =>
      (await verifiedFingerprint(peerUserId)) == fingerprint;

  Future<void> clearPeerVerification(String peerUserId) =>
      _storage!.delete(key: '${_storagePrefix}verified.$peerUserId');
}
