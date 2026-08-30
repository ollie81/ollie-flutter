import 'package:flutter/material.dart';
import 'chat_screen.dart';

// "Do It With Me" -- picking one of these opens Ollie in that mode:
// it shapes HOW Ollie helps (guiding step-by-step, asking what
// you're working on) for the rest of that chat, and Ollie speaks
// first instead of waiting for you to explain. See the backend's
// modes.py for the matching keys/labels.
class DoItWithMeScreen extends StatelessWidget {
  final String phoneNumber;
  const DoItWithMeScreen({super.key, required this.phoneNumber});

  static const List<Map<String, String>> _modes = [
    {
      'key': 'study',
      'label': 'Study Together',
      'description': 'Break it into steps, quiz you along the way',
    },
    {
      'key': 'build',
      'label': 'Build Together',
      'description': 'Work through your project one step at a time',
    },
    {
      'key': 'plan_day',
      'label': 'Plan My Day',
      'description': 'Turn today into a short, realistic plan',
    },
    {
      'key': 'learn',
      'label': 'Learn Together',
      'description': 'Explain a topic interactively, piece by piece',
    },
    {
      'key': 'practice',
      'label': 'Practice',
      'description': 'Interview, presentation, hard conversation — run through it',
    },
    {
      'key': 'brainstorm',
      'label': 'Brainstorm',
      'description': 'Build ideas together, no generic suggestions',
    },
  ];

  static const List<IconData> _icons = [
    Icons.school_outlined,
    Icons.handyman_outlined,
    Icons.wb_sunny_outlined,
    Icons.auto_stories_outlined,
    Icons.mic_none_outlined,
    Icons.lightbulb_outline,
  ];

  void _startMode(BuildContext context, String mode, String label) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: ChatScreen(phoneNumber: phoneNumber, initialMode: mode, initialModeLabel: label),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF090B14),
              Color(0xFF12172A),
              Color(0xFF1A1035),
              Color(0xFF0F1B2D),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Text(
                      'Do It With Me',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Text(
                  "Let's do this together, not just talk about it",
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: _modes.length,
                  itemBuilder: (context, index) {
                    final mode = _modes[index];
                    return _modeCard(context, _icons[index], mode['label']!, mode['description']!, mode['key']!);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeCard(BuildContext context, IconData icon, String label, String description, String key) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _startMode(context, key, label),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFF8C6B).withOpacity(0.12),
                  ),
                  child: Icon(icon, color: const Color(0xFFFF8C6B), size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(description, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12.5, height: 1.3)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.25), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
