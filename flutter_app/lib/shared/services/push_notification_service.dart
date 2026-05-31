import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  bool _initialized = false;

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

      SupabaseConfig.client.auth.onAuthStateChange.listen((event) async {
        if (event.session == null) return;
        await syncTokenForCurrentUser();
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
