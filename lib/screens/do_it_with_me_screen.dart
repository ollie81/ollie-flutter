import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import 'chat_screen.dart';

// "Do It With Me" -- picking one of these opens Ollie in that mode:
// it shapes HOW Ollie helps (guiding step-by-step, asking what
// you're working on) for the rest of that chat, and Ollie speaks
// first instead of waiting for you to explain. See the backend's
// modes.py for the matching keys/labels. Labels/descriptions are
// looked up by key at build time (via _modeLabel/_modeDescription)
// rather than stored in _modeKeys, since a static const list can't
// hold context-dependent localized strings.
class DoItWithMeScreen extends StatelessWidget {
  final String phoneNumber;
  const DoItWithMeScreen({super.key, required this.phoneNumber});

  static const List<String> _modeKeys = ['study', 'build', 'plan_day', 'learn', 'practice', 'brainstorm'];

  static const List<IconData> _icons = [
    Icons.school_outlined,
    Icons.handyman_outlined,
    Icons.wb_sunny_outlined,
    Icons.auto_stories_outlined,
    Icons.mic_none_outlined,
    Icons.lightbulb_outline,
  ];

  String _modeLabel(AppLocalizations l10n, String key) {
    switch (key) {
      case 'study':
        return l10n.doItModeStudyLabel;
      case 'build':
        return l10n.doItModeBuildLabel;
      case 'plan_day':
        return l10n.doItModePlanDayLabel;
      case 'learn':
        return l10n.doItModeLearnLabel;
      case 'practice':
        return l10n.doItModePracticeLabel;
      case 'brainstorm':
        return l10n.doItModeBrainstormLabel;
      default:
        return key;
    }
  }

  String _modeDescription(AppLocalizations l10n, String key) {
    switch (key) {
      case 'study':
        return l10n.doItModeStudyDescription;
      case 'build':
        return l10n.doItModeBuildDescription;
      case 'plan_day':
        return l10n.doItModePlanDayDescription;
      case 'learn':
        return l10n.doItModeLearnDescription;
      case 'practice':
        return l10n.doItModePracticeDescription;
      case 'brainstorm':
        return l10n.doItModeBrainstormDescription;
      default:
        return '';
    }
  }

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
    final l10n = AppLocalizations.of(context)!;
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
                    Text(
                      l10n.doItWithMeTitle,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Text(
                  l10n.doItWithMeSubtitle,
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: _modeKeys.length,
                  itemBuilder: (context, index) {
                    final key = _modeKeys[index];
                    return _modeCard(context, _icons[index], _modeLabel(l10n, key), _modeDescription(l10n, key), key);
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
