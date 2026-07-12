import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService  {
  static Future<void> init() async {}
  static Future<void> setupFirebase() async {}
  static Future<String?> getFCMToken() async {
    return await FirebaseMessaging.instance.getToken();
  }
}
