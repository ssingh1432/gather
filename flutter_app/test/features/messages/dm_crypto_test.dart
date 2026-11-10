import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/features/messages/dm_crypto_service.dart';

void main() {
  group('DmCryptoService', () {
    late DmCryptoService alice;
    late DmCryptoService bob;

    setUp(() {
      alice = DmCryptoService(store: MemoryDmKeyStore());
      bob = DmCryptoService(store: MemoryDmKeyStore());
    });

    test('both sides derive the same key and can decrypt each other', () async {
      final aPub = await alice.ensureLocalPublicKey('alice');
      final bPub = await bob.ensureLocalPublicKey('bob');
      const conv = 'conv-1';

      final aKey = await alice.deriveConversationKey(userId: 'alice', conversationId: conv, otherPublicKeyB64: bPub);
      final bKey = await bob.deriveConversationKey(userId: 'bob', conversationId: conv, otherPublicKeyB64: aPub);

      final c = await alice.encryptText(key: aKey, conversationId: conv, plaintext: 'नमस्ते 👋');
      final out = await bob.decryptText(key: bKey, conversationId: conv, ciphertextB64: c.ciphertext, nonceB64: c.nonce);
      expect(out, 'नमस्ते 👋');
    });

    test('public key is stable across loads and changes after reset', () async {
      final first = await alice.ensureLocalPublicKey('alice');
      expect(await alice.ensureLocalPublicKey('alice'), first);
      expect(await alice.resetLocalKey('alice'), isNot(first));
    });

    test('ciphertext does not decrypt in a different conversation (AAD binding)', () async {
      final bPub = await bob.ensureLocalPublicKey('bob');
      final aPub = await alice.ensureLocalPublicKey('alice');
      final aKey = await alice.deriveConversationKey(userId: 'alice', conversationId: 'c1', otherPublicKeyB64: bPub);
      final bKey = await bob.deriveConversationKey(userId: 'bob', conversationId: 'c1', otherPublicKeyB64: aPub);
      final c = await alice.encryptText(key: aKey, conversationId: 'c1', plaintext: 'secret');
      expect(await bob.decryptText(key: bKey, conversationId: 'c2', ciphertextB64: c.ciphertext, nonceB64: c.nonce), isNull);
    });

    test('tampered or malformed ciphertext returns null instead of throwing', () async {
      final bPub = await bob.ensureLocalPublicKey('bob');
      final aKey = await alice.deriveConversationKey(userId: 'alice', conversationId: 'c1', otherPublicKeyB64: bPub);
      final c = await alice.encryptText(key: aKey, conversationId: 'c1', plaintext: 'hello');
      expect(await alice.decryptText(key: aKey, conversationId: 'c1', ciphertextB64: 'AAAA', nonceB64: c.nonce), isNull);
      expect(await alice.decryptText(key: aKey, conversationId: 'c1', ciphertextB64: '%%%', nonceB64: c.nonce), isNull);
    });

    test('a third party cannot decrypt', () async {
      final bPub = await bob.ensureLocalPublicKey('bob');
      final aKey = await alice.deriveConversationKey(userId: 'alice', conversationId: 'c1', otherPublicKeyB64: bPub);
      final c = await alice.encryptText(key: aKey, conversationId: 'c1', plaintext: 'hello');
      final eve = DmCryptoService(store: MemoryDmKeyStore());
      final aPub = await alice.ensureLocalPublicKey('alice');
      final eKey = await eve.deriveConversationKey(userId: 'eve', conversationId: 'c1', otherPublicKeyB64: aPub);
      expect(await eve.decryptText(key: eKey, conversationId: 'c1', ciphertextB64: c.ciphertext, nonceB64: c.nonce), isNull);
    });
  });
}
