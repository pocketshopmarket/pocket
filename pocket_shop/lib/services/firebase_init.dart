import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../firebase_options.dart';

/// Top-level FCM background handler (must be top-level function).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kDebugMode) debugPrint('[FCM] Background message: ${message.messageId}');
}

/// Initialize Firebase on platforms that support it (Android, iOS, Web).
/// On Windows/Linux desktop this is a no-op — notifications fall back to
/// pure API polling via the NotificationProvider.
Future<void> initFirebaseIfSupported() async {
  // Firebase C++ SDK does not support Windows/Linux desktop builds.
  if (!kIsWeb) {
    try {
      if (Platform.isWindows || Platform.isLinux) {
        if (kDebugMode) {
          debugPrint('[Firebase] Skipped — desktop platform (using API polling)');
        }
        return;
      }
    } catch (_) {
      // Platform detection may fail on web; kIsWeb check above handles it.
    }
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (kDebugMode) debugPrint('[Firebase] Core initialized');

    // Register background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Request notification permission (Android 13+)
    final fcm = FirebaseMessaging.instance;
    await fcm.requestPermission(alert: true, badge: true, sound: true);

    final token = await fcm.getToken();
    if (kDebugMode) debugPrint('[FCM] Token: $token');
  } catch (e) {
    if (kDebugMode) debugPrint('[Firebase] Init error (non-fatal): $e');
  }
}
