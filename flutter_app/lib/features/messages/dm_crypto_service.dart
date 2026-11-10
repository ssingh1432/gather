import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the device's X25519 private key lives. Abstracted so tests can use
/// an in-memory store instead of platform secure storage.
abstract class DmKeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureDmKeyStore implements DmKeyStore {
  SecureDmKeyStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemoryDmKeyStore implements DmKeyStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
}

class DmCipher {
  const DmCipher({required this.ciphertext, required this.nonce});
  final String ciphertext; // base64(cipherText || 16-byte GCM tag)
  final String nonce; // base64(12-byte nonce)
}

/// End-to-end encryption for DM text bodies.
///
/// Scheme: each account has one X25519 key pair. The private key is created
/// on the device and never leaves it; the public key is registered with the
/// server (`register_dm_public_key`). For a conversation, both sides derive
/// the same secret via X25519 ECDH, run it through HKDF-SHA256 (bound to the
/// conversation id), and use the result as an AES-256-GCM key. The
/// conversation id is also bound as AAD so ciphertext cannot be replayed into
/// another conversation.
///
/// Known limits (documented in docs/): one key per account, so a second
/// device must either hold the same key or explicitly reset it (old encrypted
/// messages then become unreadable); no forward secrecy (no ratchet); media
/// files are not end-to-end encrypted.
class DmCryptoService {
  DmCryptoService({DmKeyStore? store}) : _store = store ?? SecureDmKeyStore();

  final DmKeyStore _store;

  static final X25519 _x25519 = X25519();
  static final AesGcm _aes = AesGcm.with256bits();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static const int _macLength = 16;

  String _privKey(String userId) => 'gather_dm_x25519_private_v1_$userId';

  /// Returns this device's base64 public key, creating the key pair on first
  /// use.
  Future<String> ensureLocalPublicKey(String userId) async {
    final pair = await _loadOrCreate(userId);
    final pub = await pair.extractPublicKey();
    return base64.encode(pub.bytes);
  }

  /// Discards the local key pair and creates a new one. Old encrypted
  /// messages can no longer be decrypted on this account after a reset.
  Future<String> resetLocalKey(String userId) async {
    await _store.delete(_privKey(userId));
    return ensureLocalPublicKey(userId);
  }

  Future<SimpleKeyPairData> _loadOrCreate(String userId) async {
    final stored = await _store.read(_privKey(userId));
    if (stored != null) {
      final priv = base64.decode(stored);
      final pair = SimpleKeyPairData(
        priv,
        publicKey: await _publicFromPrivate(priv),
        type: KeyPairType.x25519,
      );
      return pair;
    }
    final fresh = await _x25519.newKeyPair();
    final data = await fresh.extract();
    await _store.write(_privKey(userId), base64.encode(await fresh.extractPrivateKeyBytes()));
    return data;
  }

  Future<SimplePublicKey> _publicFromPrivate(List<int> priv) async {
    final pair = await _x25519.newKeyPairFromSeed(priv);
    return pair.extractPublicKey();
  }

  /// Derives the per-conversation AES key shared by both participants.
  Future<SecretKey> deriveConversationKey({
    required String userId,
    required String conversationId,
    required String otherPublicKeyB64,
  }) async {
    final pair = await _loadOrCreate(userId);
    final shared = await _x25519.sharedSecretKey(
      keyPair: pair,
      remotePublicKey: SimplePublicKey(base64.decode(otherPublicKeyB64), type: KeyPairType.x25519),
    );
    return _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode('gather-dm-v1'),
      info: utf8.encode(conversationId),
    );
  }

  Future<DmCipher> encryptText({
    required SecretKey key,
    required String conversationId,
    required String plaintext,
  }) async {
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      aad: utf8.encode(conversationId),
    );
    return DmCipher(
      ciphertext: base64.encode([...box.cipherText, ...box.mac.bytes]),
      nonce: base64.encode(box.nonce),
    );
  }

  /// Returns null if the message can't be decrypted (wrong/rotated key,
  /// tampered data, malformed input) rather than throwing, so one bad
  /// message never breaks the whole chat.
  Future<String?> decryptText({
    required SecretKey key,
    required String conversationId,
    required String ciphertextB64,
    required String nonceB64,
  }) async {
    try {
      final all = base64.decode(ciphertextB64);
      if (all.length < _macLength) return null;
      final box = SecretBox(
        all.sublist(0, all.length - _macLength),
        nonce: base64.decode(nonceB64),
        mac: Mac(all.sublist(all.length - _macLength)),
      );
      final clear = await _aes.decrypt(box, secretKey: key, aad: utf8.encode(conversationId));
      return utf8.decode(clear);
    } catch (_) {
      return null;
    }
  }
}
