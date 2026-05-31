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

/// Initialize Firebase only on Android and iOS.
/// Other platforms continue using in-app API polling for notifications.
Future<void> initFirebaseIfSupported() async {
  if (kIsWeb) {
    if (kDebugMode) {
      debugPrint('[Firebase] Skipped - mobile push is Android/iOS only');
    }
    return;
  }

  try {
    if (!Platform.isAndroid && !Platform.isIOS) {
      if (kDebugMode) {
        debugPrint('[Firebase] Skipped - using API polling on this platform');
      }
      return;
    }
  } catch (_) {
    return;
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
