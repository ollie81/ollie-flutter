import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'screens/welcome_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'services/purchase_service.dart';

// Crash/error reporting. Empty until a real Sentry project exists --
// paste the DSN here once you have one (a DSN is meant to be public,
// it only lets events be submitted, not read, so it's fine to
// hardcode like baseUrl in api_service.dart is). Left empty, _initApp
// below just runs the app directly with no reporting, same "absent
// third-party service is a clean no-op" pattern as
// FIREBASE_CREDENTIALS_JSON on the backend.
const String _sentryDsn = '';

Future<void> _initApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();

  // Initialize notifications
  await NotificationService.init();
  await NotificationService.setupFirebase();

  // Initialize Google Ads
  await MobileAds.instance.initialize();

  // Start listening for purchase updates as early as possible, so a
  // purchase that resolves after the app was closed (or completes
  // outside the paywall screen) still gets activated on the backend.
  PurchaseService.instance.init();

  runApp(const OllieApp());
}

void main() async {
  if (_sentryDsn.isEmpty) {
    await _initApp();
    return;
  }
  await SentryFlutter.init(
    (options) {
      options.dsn = _sentryDsn;
      // No breadcrumbs/context beyond the crash itself -- chat
      // content and account details never touch this.
      options.sendDefaultPii = false;
    },
    appRunner: _initApp,
  );
}

class OllieApp extends StatelessWidget {
  const OllieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: NotificationService.navigatorKey,
      title: 'Ollie',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0F1A),
        fontFamily: 'SF Pro Display',
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  String? _phoneNumber;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
    _phoneNumber = prefs.getString('phoneNumber');
    
    if (isLoggedIn && _phoneNumber != null) {
      // Fire-and-forget -- saving the FCM token is best-effort and
      // must never block getting into the app. This used to be
      // awaited here, so a slow/hung Firebase or network call (e.g.
      // right after the phone wakes from sleep, before its radio has
      // fully reconnected) left the loading screen stuck forever on
      // every subsequent open, not just the first one.
      _refreshFcmToken();
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      if (isLoggedIn && _phoneNumber != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomeScreen(phoneNumber: _phoneNumber!)),
        );
        _openChatIfLaunchedFromNotification();
      }
    }
  }

  Future<void> _refreshFcmToken() async {
    final fcmToken = await NotificationService.getFCMToken();
    if (fcmToken != null) {
      await _api.saveFcmToken(fcmToken);
    }
  }

  // If the app was fully closed and a notification tap is what
  // launched it, NotificationService's onMessageOpenedApp listener
  // never fires for this specific case -- getInitialMessage() is
  // the separate check FCM provides for a cold start. Checked here,
  // after login state is confirmed, rather than in main() before
  // runApp() -- navigatorKey isn't attached to anything that early.
  Future<void> _openChatIfLaunchedFromNotification() async {
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      await NotificationService.openChatFromNotification();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    return const WelcomeScreen();
  }
}
