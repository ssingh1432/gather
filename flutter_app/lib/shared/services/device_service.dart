import 'dart:math';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/supabase_client.dart';

/// One row from `list_my_devices()`.
class UserDevice {
  const UserDevice({
    required this.id,
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.lastSeenAt,
    required this.trusted,
    required this.revoked,
  });

  factory UserDevice.fromJson(Map<String, dynamic> j) => UserDevice(
        id: j['id'] as String,
        deviceId: j['device_id'] as String,
        name: j['device_name'] as String,
        platform: j['platform'] as String,
        lastSeenAt: DateTime.parse(j['last_seen_at'] as String).toLocal(),
        trusted: j['trusted'] == true,
        revoked: j['revoked'] == true,
      );

  final String id;
  final String deviceId;
  final String name;
  final String platform;
  final DateTime lastSeenAt;
  final bool trusted;
  final bool revoked;
}

/// Identifies this install to the backend (login alerts, trusted devices).
///
/// The id is a random value generated once and kept in secure storage. It is
/// NOT a hardware identifier and is not a secret: it only groups sessions
/// from the same install. Clearing app data creates a new device.
class DeviceService {
  DeviceService._();
  static final DeviceService instance = DeviceService._();

  static const _storage = FlutterSecureStorage();
  static const _key = 'gather_device_id';
  String? _cached;

  Future<String> deviceId() async {
    if (_cached != null) return _cached!;
    var id = await _storage.read(key: _key);
    if (id == null || id.length < 16) {
      final rnd = Random.secure();
      id = List.generate(32, (_) => rnd.nextInt(16).toRadixString(16)).join();
      await _storage.write(key: _key, value: id);
    }
    return _cached = id;
  }

  String get platform {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      default:
        return 'unknown';
    }
  }

  String get deviceName {
    switch (platform) {
      case 'web':
        return 'Web browser';
      case 'android':
        return 'Android device';
      case 'ios':
        return 'iPhone / iPad';
      case 'macos':
        return 'Mac';
      case 'windows':
        return 'Windows PC';
      case 'linux':
        return 'Linux PC';
      default:
        return 'Unknown device';
    }
  }

  /// Call after every successful sign-in. Never throws: a registry failure
  /// must not block login. Returns true when this is a new device.
  Future<bool> registerCurrentDevice() async {
    try {
      final res = await SupabaseConfig.client.rpc('register_device', params: {
        'p_device_id': await deviceId(),
        'p_device_name': deviceName,
        'p_platform': platform,
      });
      return res is Map && res['is_new'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isCurrentDeviceTrusted() async {
    try {
      final res = await SupabaseConfig.client.rpc('is_device_trusted', params: {'p_device_id': await deviceId()});
      return res == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<UserDevice>> listDevices() async {
    final res = await SupabaseConfig.client.rpc('list_my_devices') as List;
    return res.map((e) => UserDevice.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<void> setTrust(String deviceId, bool trusted, {int days = 30}) =>
      SupabaseConfig.client.rpc('set_device_trust', params: {
        'p_device_id': deviceId,
        'p_trusted': trusted,
        'p_days': days,
      });

  Future<void> revoke(String rowId) => SupabaseConfig.client.rpc('revoke_device', params: {'p_id': rowId});
}
