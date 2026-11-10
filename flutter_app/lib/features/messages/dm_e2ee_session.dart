import 'package:cryptography/cryptography.dart';

import 'dm_crypto_service.dart';
import 'dm_models.dart';
import 'dm_repository.dart';

enum DmKeyState {
  /// Local key matches the key registered on the server.
  ready,

  /// The server holds a different key (registered from another device).
  /// Encrypted messages can't be read or sent from here until keys are reset.
  mismatch,

  /// Key setup failed (offline, server error). Chat still works unencrypted.
  unavailable,
}

/// Glue between [DmCryptoService] and the server key registry. One instance
/// per signed-in user session; safe to share between the inbox and chats.
class DmE2eeSession {
  DmE2eeSession({DmRepository? repo, DmCryptoService? crypto})
      : _repo = repo ?? DmRepository(),
        _crypto = crypto ?? DmCryptoService();

  final DmRepository _repo;
  final DmCryptoService _crypto;

  final Map<String, String> _otherPublicKeys = {};
  final Map<String, SecretKey> _convKeys = {};
  DmKeyState? _state;

  DmKeyState? get state => _state;

  Future<DmKeyState> prepare(String userId) async {
    try {
      final local = await _crypto.ensureLocalPublicKey(userId);
      final server = await _repo.registerPublicKey(local);
      _state = server == local ? DmKeyState.ready : DmKeyState.mismatch;
    } catch (_) {
      _state = DmKeyState.unavailable;
    }
    return _state!;
  }

  /// Replaces this account's key with a fresh one generated on this device.
  /// Previously encrypted messages become unreadable.
  Future<DmKeyState> resetKeys(String userId) async {
    final local = await _crypto.resetLocalKey(userId);
    await _repo.registerPublicKey(local, replace: true);
    _convKeys.clear();
    _state = DmKeyState.ready;
    return _state!;
  }

  /// The AES key for a conversation, or null if the other person hasn't
  /// registered a key yet (messages then go out unencrypted, which the UI
  /// must make visible).
  Future<SecretKey?> keyFor({
    required String userId,
    required String conversationId,
    required String otherUserId,
  }) async {
    final cached = _convKeys[conversationId];
    if (cached != null) return cached;
    var otherKey = _otherPublicKeys[otherUserId];
    if (otherKey == null) {
      otherKey = await _repo.publicKeyOf(otherUserId);
      if (otherKey == null) return null;
      _otherPublicKeys[otherUserId] = otherKey;
    }
    final key = await _crypto.deriveConversationKey(
      userId: userId,
      conversationId: conversationId,
      otherPublicKeyB64: otherKey,
    );
    _convKeys[conversationId] = key;
    return key;
  }

  Future<DmCipher> encrypt({required SecretKey key, required String conversationId, required String plaintext}) =>
      _crypto.encryptText(key: key, conversationId: conversationId, plaintext: plaintext);

  Future<String?> decrypt({
    required SecretKey? key,
    required String conversationId,
    required String? ciphertext,
    required String? nonce,
  }) async {
    if (key == null || ciphertext == null || nonce == null) return null;
    return _crypto.decryptText(key: key, conversationId: conversationId, ciphertextB64: ciphertext, nonceB64: nonce);
  }
}
