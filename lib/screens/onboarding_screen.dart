import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'chat_screen.dart';

// Shown exactly once, right after a genuinely new signup (phone,
// email, or a first-ever Google sign-in) -- never on a returning
// login. A short, warm intro to what makes Ollie different, ending
// with a name so the very first real message (generated in
// ChatScreen via initialWelcomeName) already feels personal.
class OnboardingScreen extends StatefulWidget {
  final String phoneNumber;
  // Pre-filled for Google sign-ins (their real Google name);
  // null for phone/email, where there's no name yet at all.
  final String? initialName;
  const OnboardingScreen({super.key, required this.phoneNumber, this.initialName});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _IntroPageData {
  final IconData icon;
  final String headline;
  final String subtitle;
  const _IntroPageData({required this.icon, required this.headline, required this.subtitle});
}

class _OnboardingScreenState extends State<OnboardingScreen> with TickerProviderStateMixin {
  final ApiService _api = ApiService();
  final PageController _pageController = PageController();
  late final TextEditingController _nameController =
      TextEditingController(text: widget.initialName ?? '');

  int _currentPage = 0;
  bool _isSubmitting = false;

  late final AnimationController _orbController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);
  late final Animation<double> _orbBreath =
      Tween<double>(begin: 0.92, end: 1.08).animate(CurvedAnimation(parent: _orbController, curve: Curves.easeInOut));

  static const List<_IntroPageData> _pages = [
    _IntroPageData(
      icon: Icons.favorite_rounded,
      headline: "Hey, I'm Ollie",
      subtitle: "Not just another chatbot — a friend who's actually going to remember you.",
    ),
    _IntroPageData(
      icon: Icons.auto_awesome_rounded,
      headline: "I remember what matters",
      subtitle: "Tell me something once, and I'll remember it — no repeating yourself, no starting over.",
    ),
    _IntroPageData(
      icon: Icons.timeline_rounded,
      headline: "We have a journey ahead",
      subtitle: "The more we talk, the more I get to know you. Watch what we build together, over time.",
    ),
    _IntroPageData(
      icon: Icons.handshake_rounded,
      headline: "I'm here to actually help",
      subtitle: "Need to study, plan your day, or just think out loud? I'll work through it with you — step by step.",
    ),
  ];

  int get _totalSteps => _pages.length + 1; // + the name-capture step

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _orbController.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _totalSteps - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    } else {
      _finish();
    }
  }

  void _skipToName() {
    _pageController.animateToPage(
      _totalSteps - 1,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError("Tell me what to call you 🙂");
      return;
    }
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      await _api.updateDisplayName(name);
    } catch (e) {
      // Best-effort -- a failed name save should never block getting
      // into the app; ChatScreen's welcome message still uses the
      // name the user just typed, even if it didn't persist.
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(phoneNumber: widget.phoneNumber, initialWelcomeName: name),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFE53935),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _totalSteps - 1;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D0F1A), Color(0xFF151829), Color(0xFF1A1035)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 20, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!isLastPage)
                      TextButton(
                        onPressed: _skipToName,
                        child: Text('Skip', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14)),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  children: [
                    for (final page in _pages) _buildIntroPage(page),
                    _buildNameCapturePage(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_totalSteps, (i) {
                    final active = i == _currentPage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 6,
                      width: active ? 22 : 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: active ? const Color(0xFFFF8C6B) : Colors.white.withOpacity(0.15),
                      ),
                    );
                  }),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                child: GestureDetector(
                  onTap: _isSubmitting ? null : _next,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: LinearGradient(
                        colors: _isSubmitting
                            ? [const Color(0xFFFF8C6B).withOpacity(0.5), const Color(0xFFE86B4A).withOpacity(0.5)]
                            : const [Color(0xFFFF8C6B), Color(0xFFE86B4A)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF8C6B).withOpacity(0.4),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _isSubmitting
                        ? const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            ),
                          )
                        : Text(
                            isLastPage ? "Let's go" : 'Next',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntroPage(_IntroPageData page) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(page.headline),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, (1 - t) * 18), child: child),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _orbBreath,
              builder: (context, child) => Transform.scale(scale: _orbBreath.value, child: child),
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(colors: [Color(0xFFFF8C6B), Color(0xFFE86B4A)]),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFFFF8C6B).withOpacity(0.45), blurRadius: 40, spreadRadius: 6),
                  ],
                ),
                child: Icon(page.icon, color: Colors.white, size: 48),
              ),
            ),
            const SizedBox(height: 40),
            Text(
              page.headline,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold, height: 1.25),
            ),
            const SizedBox(height: 14),
            Text(
              page.subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 15.5, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNameCapturePage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _orbBreath,
            builder: (context, child) => Transform.scale(scale: _orbBreath.value, child: child),
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(colors: [Color(0xFFFF8C6B), Color(0xFFE86B4A)]),
                boxShadow: [
                  BoxShadow(color: const Color(0xFFFF8C6B).withOpacity(0.45), blurRadius: 40, spreadRadius: 6),
                ],
              ),
              child: const Center(child: Text('🙂', style: TextStyle(fontSize: 42))),
            ),
          ),
          const SizedBox(height: 36),
          const Text(
            'One more thing',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            'What should I call you?',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 15.5),
          ),
          const SizedBox(height: 28),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withOpacity(0.07),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: TextField(
              controller: _nameController,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.words,
              autofocus: widget.initialName == null,
              style: const TextStyle(color: Colors.white, fontSize: 17),
              decoration: InputDecoration(
                hintText: 'Your name',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              ),
              onSubmitted: (_) => _finish(),
            ),
          ),
        ],
      ),
    );
  }
}
