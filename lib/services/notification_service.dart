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
    // Flutter doesn't show a system banner for foreground FCM
    // messages the way it does for background/terminated ones, so
    // without this a foreground push was silently invisible: saved
    // to the in-app notifications list, but nothing on-screen ever
    // told the user it arrived.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      final context = navigatorKey.currentContext;
      if (notification == null || context == null) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            notification.body?.isNotEmpty == true
                ? notification.body!
                : (notification.title ?? 'New message from Ollie'),
          ),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Open',
            onPressed: openChatFromNotification,
          ),
        ),
      );
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
