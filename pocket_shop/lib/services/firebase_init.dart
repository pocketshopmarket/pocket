import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/constants/app_constants.dart';
import '../firebase_options.dart';
import 'api_service.dart';

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kDebugMode) debugPrint('[FCM] Background message: ${message.messageId}');
}

Future<void> initFirebaseIfSupported() async {
  if (kIsWeb) return;
  try {
    if (!Platform.isAndroid && !Platform.isIOS) return;
  } catch (_) {
    return;
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    await _initLocalNotifications();

    final fcm = FirebaseMessaging.instance;
    await fcm.requestPermission(alert: true, badge: true, sound: true);

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    // Registered before the initial getToken() attempt below so a failure
    // there (e.g. APNS token not ready yet on iOS) doesn't leave this
    // unregistered for the rest of the app session.
    fcm.onTokenRefresh.listen(_postFcmToken);

    if (Platform.isIOS) {
      await _waitForApnsToken(fcm);
    }

    try {
      final token = await fcm.getToken();
      if (token != null) {
        await _postFcmToken(token);
      }
      if (kDebugMode) debugPrint('[Firebase] Initialized. Token: $token');
    } catch (e) {
      // Non-fatal: onTokenRefresh (registered above) will pick up the
      // token once APNS registration actually completes.
      if (kDebugMode) debugPrint('[FCM] Initial getToken() failed (non-fatal): $e');
    }
  } catch (e) {
    if (kDebugMode) debugPrint('[Firebase] Init error (non-fatal): $e');
  }
}

/// Call this after a successful login so the token is always tied to the
/// current authenticated user.
Future<void> registerFcmTokenWithBackend() async {
  if (kIsWeb) return;
  try {
    if (!Platform.isAndroid && !Platform.isIOS) return;
  } catch (_) {
    return;
  }
  if (Firebase.apps.isEmpty) return;
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _postFcmToken(token);
  } catch (e) {
    if (kDebugMode) debugPrint('[FCM] Post-login token registration failed: $e');
  }
}

/// iOS can't mint an FCM token until APNS has handed the device an APNS
/// token, which happens asynchronously right after requestPermission().
/// Poll briefly rather than calling getToken() immediately, which is a
/// documented race that throws apns-token-not-set on a cold start.
Future<void> _waitForApnsToken(FirebaseMessaging fcm) async {
  for (var i = 0; i < 10; i++) {
    final apnsToken = await fcm.getAPNSToken();
    if (apnsToken != null) return;
    await Future.delayed(const Duration(milliseconds: 500));
  }
}

Future<void> _initLocalNotifications() async {
  const androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings();
  await _localNotifications.initialize(
    const InitializationSettings(android: androidSettings, iOS: iosSettings),
  );

  await _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          'pocket_shop_channel',
          'Pocket Shop',
          description: 'Pocket Shop order and payment updates',
          importance: Importance.high,
        ),
      );
}

Future<void> _handleForegroundMessage(RemoteMessage message) async {
  final notification = message.notification;
  if (notification == null) return;

  await _localNotifications.show(
    notification.hashCode,
    notification.title,
    notification.body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'pocket_shop_channel',
        'Pocket Shop',
        channelDescription: 'Pocket Shop order and payment updates',
        importance: Importance.high,
        priority: Priority.high,
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      ),
      iOS: DarwinNotificationDetails(),
    ),
  );
}

Future<void> _postFcmToken(String token) async {
  try {
    await ApiService().post(
      AppConstants.registerFcmTokenEndpoint,
      data: {'fcm_token': token},
    );
    if (kDebugMode) debugPrint('[FCM] Token registered with backend');
  } catch (e) {
    if (kDebugMode) debugPrint('[FCM] Token registration failed (non-fatal): $e');
  }
}
