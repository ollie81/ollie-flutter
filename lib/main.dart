import 'package:flutter/material.dart';
import 'screens/welcome_screen.dart';
void main() {
  runApp(const OllieApp());
}

class OllieApp extends StatelessWidget {
  const OllieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ollie',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0F1A),
        fontFamily: 'SF Pro Display',
      ),
      home: const WelcomeScreen(),
    );
  }
}