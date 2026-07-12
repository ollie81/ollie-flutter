import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
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

    // Handle the case where the user taps a notification and it
    // opens/resumes the app.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      // TODO: navigate to a relevant screen if needed, e.g. based
      // on message.data.
      print('Notification tapped: ${message.data}');
    });
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
}
