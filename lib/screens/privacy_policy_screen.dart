import 'package:flutter/material.dart';

const String _lastUpdated = 'Not yet published — draft';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Privacy Policy', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _draftNotice(),
          const SizedBox(height: 24),
          _paragraph('Last updated: $_lastUpdated'),
          const SizedBox(height: 20),
          _paragraph(
            "This policy explains what Ollie collects, why, and how you can control it. "
            "Ollie is an AI companion app — it uses AI models to hold conversations, remember "
            "things you tell it, and reply as a real voice when you use voice features.",
          ),
          _section('Information we collect', [
            _bullet('Account info: your phone number, a hashed password (we never store your '
                'actual password), and optionally your date of birth (used only to confirm '
                'you meet the minimum age) and country.'),
            _bullet('Conversations: the messages you send Ollie, Ollie\'s replies, and things '
                'Ollie infers from those conversations to remember you better — interests, '
                'mood patterns, goals you mention, and events you ask to be reminded about.'),
            _bullet('Voice: if you use voice features, your recording is sent to our '
                'transcription and text-to-speech providers to process your message and '
                'generate Ollie\'s spoken reply. We don\'t keep a copy of the audio itself '
                'once it\'s processed.'),
            _bullet('Usage & subscription info: how many messages you\'ve sent, whether you '
                'have an active subscription, and — if you subscribe — the purchase '
                'information Google Play gives us to confirm and manage that subscription.'),
            _bullet('Device info: a push notification token, so we can send you '
                'notifications you\'ve opted into.'),
          ]),
          _section('Automatic safety checks', [
            _bullet('Messages are automatically screened for signs of self-harm, abuse, or '
                'other crisis situations, and for content that violates our usage policies. '
                'This happens on every message, whether or not anything is flagged.'),
            _bullet('If a message is flagged, that\'s recorded (the message and a timestamp) '
                'so it can be reviewed. Flagging never blocks your conversation — Ollie still '
                'replies normally, and (for crisis-related flags) includes a resource line '
                'alongside its normal reply.'),
          ]),
          _section('How we use this information', [
            _bullet('To run the core app: hold a conversation, remember context between '
                'sessions, and generate voice replies.'),
            _bullet('To personalize Ollie\'s responses based on what you\'ve told it.'),
            _bullet('To enforce free-tier limits and manage premium subscriptions.'),
            _bullet('To monitor for safety issues as described above.'),
            _bullet('To send you push notifications you\'ve opted into.'),
          ]),
          _section('Third parties we share data with', [
            _bullet('OpenAI — processes your messages to generate Ollie\'s replies, '
                'transcribes voice messages, and runs the automatic safety screening.'),
            _bullet('Papla Media — converts Ollie\'s replies to spoken audio for voice features.'),
            _bullet('Twilio — sends the one-time codes used to verify your phone number.'),
            _bullet('SendGrid — sends the one-time codes used to verify your email address, '
                'if you sign up or log in with email instead of phone.'),
            _bullet('Google — Play Billing (subscription purchases), Sign-In (if you use it '
                'to log in), Firebase (push notifications), and AdMob (the optional rewarded '
                'ads that unlock bonus messages).'),
            _bullet('Supabase and Railway — host our database and backend infrastructure.'),
            _bullet('Sentry — helps us catch and fix bugs when the app crashes or a request '
                'fails. It receives technical error details (like a stack trace), never your '
                'messages or account details.'),
            _bullet('We don\'t sell your data, and we don\'t share it for third-party advertising.'),
          ]),
          _section('Your choices', [
            _bullet('Clear Ollie\'s memory of you at any time from Settings — this erases '
                'what Ollie has learned about you (interests, patterns, things you\'ve shared).'),
            _bullet('Delete your account from Settings — this permanently removes your '
                'account and everything associated with it.'),
            _bullet('Turn push notifications on or off from Settings.'),
          ]),
          _section('Children\'s privacy', [
            _bullet('Ollie is not intended for children under 13, and we ask for a birthdate '
                'at signup to help enforce that minimum.'),
          ]),
          _section('Security', [
            _bullet('Passwords are hashed, not stored in plain text. Access tokens are stored '
                'securely on your device. We use industry-standard practices to protect your '
                'data, but no system is 100% secure.'),
          ]),
          _section('Changes to this policy', [
            _bullet('If this policy changes in a way that matters, we\'ll let you know in the app.'),
          ]),
          _section('Contact us', [
            _bullet('Questions about this policy or your data: [add a real contact email before publishing].'),
          ]),
          const SizedBox(height: 12),
          _draftNotice(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _draftNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB74D).withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFB74D).withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB74D), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "This is a draft that reflects what the app actually does, generated to give "
              "you a starting point — not legal advice. Have it reviewed by a lawyer before "
              "you publish the app, especially since Ollie is used by minors and handles "
              "sensitive topics like self-harm flagging.",
              style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> bullets) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          ...bullets,
        ],
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 14, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paragraph(String text) {
    return Text(
      text,
      style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 14, height: 1.5),
    );
  }
}
