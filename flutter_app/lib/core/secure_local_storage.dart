import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists the Supabase session (access + refresh tokens) using
/// platform-native secure storage — Keychain on iOS/macOS, Keystore-backed
/// encrypted storage on Android, and WebCrypto-backed encrypted storage in
/// IndexedDB on web — instead of supabase_flutter's default, which is
/// plaintext SharedPreferences (plist/XML on mobile, plain localStorage on
/// web).
///
/// Note on web: browser "secure" storage still lives in the same origin as
/// the app, so it doesn't protect against a determined XSS attack the way
/// Keychain/Keystore do on mobile. It does protect against casual
/// inspection (devtools, browser profile extraction, shared-device
/// snooping), which is the realistic threat for this app today.
class SecureLocalStorage extends LocalStorage {
  const SecureLocalStorage();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: supabasePersistSessionKey);

  @override
  Future<String?> accessToken() => _storage.read(key: supabasePersistSessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: supabasePersistSessionKey, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: supabasePersistSessionKey);
}
