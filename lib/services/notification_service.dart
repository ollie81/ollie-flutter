import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/chat_screen.dart';

class NotificationService {
  // Lets openChatFromNotification navigate from outside the widget
  // tree (a push-notification callback has no BuildContext of its
  // own) -- attached to MaterialApp in main.dart.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static Future<void> init() async {
    final messaging = FirebaseMessaging.instance;

    // Ask the user for permission — required explicitly on iOS,
    // and on Android 13+ (API 33+). Without this, notifications
    // may silently never arrive on those platforms.
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Handle notifications that arrive while the app is open —
    // without this, foreground pushes are received but never
    // shown to the user.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification != null) {
        // TODO: hook this into your in-app UI (e.g. a snackbar,
        // or refresh a notifications badge/list) since Flutter
        // doesn't show a system banner for foreground messages
        // automatically the way background ones do.
        print('Foreground notification: ${notification.title} — ${notification.body}');
      }
    });

    // Tapped while the app was backgrounded (not fully closed).
    // Cold-start taps -- the app was terminated and this
    // notification is what launched it -- don't fire this; see
    // AuthWrapper in main.dart, which checks getInitialMessage()
    // once login state (and therefore navigatorKey) is ready.
    FirebaseMessaging.onMessageOpenedApp.listen((_) => openChatFromNotification());
  }

  static Future<void> setupFirebase() async {
    // Background/terminated-state notification taps are handled
    // automatically by the OS + Firebase once permission is
    // granted above — nothing additional required here unless
    // you need a background message handler for data-only
    // messages (would require a top-level function annotated
    // with @pragma('vm:entry-point')).
  }

  static Future<String?> getFCMToken() async {
    return await FirebaseMessaging.instance.getToken();
  }

  /// Every notification this app sends — morning check-in, nightly
  /// recap, a reminder, "you disappeared" — is Ollie saying
  /// something in chat, so there's no per-notification type to
  /// route on: a tap always means "open the conversation".
  static Future<void> openChatFromNotification() async {
    final prefs = await SharedPreferences.getInstance();
    final phoneNumber = prefs.getString('phoneNumber');
    if (phoneNumber == null) return;
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => ChatScreen(phoneNumber: phoneNumber)),
    );
  }
}
