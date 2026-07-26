import 'dart:async';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/router.dart';
import '../../core/supabase_client.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase can already be initialized in warm-started isolates.
  }
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final _secureStorage = const FlutterSecureStorage();
  bool _initialized = false;

  static const _deviceIdKey = 'gather_device_id';

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;

    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        await syncTokenForCurrentUser();
      }

      _messaging.onTokenRefresh.listen(
        (token) => _syncToken(token),
        onError: (Object error, StackTrace stackTrace) => debugPrint('FCM token refresh failed: $error'),
      );

      // Phase 9: the app's own notification row already arrives instantly
      // via the Realtime subscription in NotificationsScreen — this banner
      // is only for the case where the app is in the foreground and the
      // person isn't looking at that screen right now.
      FirebaseMessaging.onMessage.listen(_showForegroundBanner);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      SupabaseConfig.client.auth.onAuthStateChange.listen((event) async {
        if (event.session == null) return;
        await syncTokenForCurrentUser();
        unawaited(_recordLoginDevice());
      });

      _initialized = true;
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('Firebase Messaging unavailable: ${error.message ?? error.code}');
      debugPrintStack(stackTrace: stackTrace);
    } catch (error, stackTrace) {
      debugPrint('Push notification initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _showForegroundBanner(RemoteMessage message) {
    final title = message.notification?.title;
    final body = message.notification?.body;
    if (title == null && body == null) return;
    final text = [title, body].where((s) => s != null && s.isNotEmpty).join(' — ');

    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(text),
        action: SnackBarAction(label: 'View', onPressed: () => _handleNotificationTap(message)),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    final postId = message.data['post_id'];
    if (postId != null && postId.toString().isNotEmpty) {
      appRouter.push('/post?id=$postId');
    } else {
      appRouter.push('/notifications');
    }
  }

  /// Phase 9 login alerts: a stable-per-install random ID, persisted in
  /// secure storage, stands in for "device identity" here — good enough to
  /// tell "a device we've seen before" from "brand new device", without
  /// collecting any real fingerprinting data.
  Future<void> _recordLoginDevice() async {
    if (kIsWeb) return;
    try {
      var deviceId = await _secureStorage.read(key: _deviceIdKey);
      if (deviceId == null || deviceId.isEmpty) {
        deviceId = _generateDeviceId();
        await _secureStorage.write(key: _deviceIdKey, value: deviceId);
      }
      await SupabaseConfig.client.rpc(
        'record_login_device',
        params: {'p_device_hash': deviceId, 'p_device_label': defaultTargetPlatform.name},
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to record login device: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  String _generateDeviceId() {
    final rand = Random.secure();
    return List.generate(32, (_) => rand.nextInt(16).toRadixString(16)).join();
  }

  Future<void> syncTokenForCurrentUser() async {
    if (kIsWeb) return;

    final userId = SupabaseConfig.currentUserId;
    if (userId == null) return;

    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;
      await _syncToken(token);
    } catch (error, stackTrace) {
      debugPrint('Failed to read FCM token: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> clearTokenForCurrentUser() async {
    final userId = SupabaseConfig.currentUserId;
    if (userId == null) return;

    try {
      await SupabaseConfig.client.from('users').update({
        'fcm_token': null,
        'fcm_token_updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', userId);
    } catch (error, stackTrace) {
      debugPrint('Failed to clear FCM token: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _syncToken(String token) async {
    final userId = SupabaseConfig.currentUserId;
    if (userId == null) return;

    try {
      await SupabaseConfig.client.from('users').update({
        'fcm_token': token,
        'fcm_token_updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', userId);
    } on PostgrestException catch (error, stackTrace) {
      debugPrint('Failed to sync FCM token: ${error.message}');
      debugPrintStack(stackTrace: stackTrace);
    } catch (error, stackTrace) {
      debugPrint('Failed to sync FCM token: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
