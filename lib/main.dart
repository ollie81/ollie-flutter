import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/welcome_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'services/purchase_service.dart';

void main() async {
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
      // Save FCM token
      final fcmToken = await NotificationService.getFCMToken();
      if (fcmToken != null) {
        await _api.saveFcmToken(fcmToken);
      }
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
