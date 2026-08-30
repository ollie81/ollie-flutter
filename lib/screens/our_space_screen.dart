import 'package:flutter/material.dart';
import '../services/api_service.dart';

// "Our Space" -- the shared history between Ollie and the user.
// Shows the relationship stage (never a streak -- see the backend's
// relationship.py for why) plus goals worked on, accomplishments,
// and moments worth looking back on.
class OurSpaceScreen extends StatefulWidget {
  const OurSpaceScreen({super.key});

  @override
  State<OurSpaceScreen> createState() => _OurSpaceScreenState();
}

class _OurSpaceScreenState extends State<OurSpaceScreen> {
  final ApiService _api = ApiService();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _journey;

  @override
  void initState() {
    super.initState();
    _loadJourney();
  }

  Future<void> _loadJourney() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final journey = await _api.getJourney();
      if (!mounted) return;
      setState(() {
        _journey = journey;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your journey, try again';
        _loading = false;
      });
    }
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
            children: [
              _buildAppBar(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const Text(
            'Our Space',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFF8C6B)));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: Colors.white.withOpacity(0.6))),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loadJourney,
              child: const Text('Retry', style: TextStyle(color: Color(0xFFFF8C6B))),
            ),
          ],
        ),
      );
    }

    final journey = _journey!;
    final activeGoals = List<Map<String, dynamic>>.from(journey['active_goals'] ?? []);
    final completedGoals = List<Map<String, dynamic>>.from(journey['completed_goals'] ?? []);
    final highlights = List<Map<String, dynamic>>.from(journey['highlights'] ?? []);
    final isEmpty = activeGoals.isEmpty &&
        completedGoals.isEmpty &&
        highlights.isEmpty &&
        (journey['memory_count'] ?? 0) == 0;

    return RefreshIndicator(
      color: const Color(0xFFFF8C6B),
      backgroundColor: const Color(0xFF1A1035),
      onRefresh: _loadJourney,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _stageHero(journey),
          const SizedBox(height: 24),
          if (isEmpty)
            _emptyState()
          else ...[
            if (activeGoals.isNotEmpty) ...[
              _sectionHeader("Working on together"),
              ...activeGoals.map((g) => _goalTile(g, done: false)),
            ],
            if (completedGoals.isNotEmpty) ...[
              const SizedBox(height: 16),
              _sectionHeader("What you've accomplished"),
              ...completedGoals.map((g) => _goalTile(g, done: true)),
            ],
            if (highlights.isNotEmpty) ...[
              const SizedBox(height: 16),
              _sectionHeader('Moments'),
              ...highlights.map((m) => _highlightTile(m)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _stageHero(Map<String, dynamic> journey) {
    final emoji = journey['stage_emoji'] ?? '🌱';
    final label = journey['stage_label'] ?? 'New';
    final activeDays = journey['active_days'] ?? 0;
    final memoryCount = journey['memory_count'] ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFF8C6B).withOpacity(0.16),
            const Color(0xFFFF8C6B).withOpacity(0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            activeDays == 0
                ? 'Your story with Ollie is just getting started'
                : '$activeDays ${activeDays == 1 ? 'day' : 'days'} together · $memoryCount things Ollie remembers',
            style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.auto_awesome_outlined, color: Colors.white.withOpacity(0.25), size: 44),
          const SizedBox(height: 16),
          Text(
            'Nothing here yet',
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Keep talking to Ollie — your memories, goals, and\nmilestones together will start showing up here.',
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: Colors.white.withOpacity(0.4),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _goalTile(Map<String, dynamic> goal, {required bool done}) {
    final title = (goal['title'] as String?) ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Icon(
            done ? Icons.emoji_events_outlined : Icons.flag_outlined,
            color: done ? const Color(0xFFFFC65C) : const Color(0xFFFF8C6B).withOpacity(0.8),
            size: 20,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white.withOpacity(done ? 0.6 : 1),
                fontSize: 14,
                decoration: done ? TextDecoration.lineThrough : null,
                decorationColor: Colors.white.withOpacity(0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _highlightTile(Map<String, dynamic> memory) {
    final text = (memory['memory_text'] as String?) ?? '';
    final category = (memory['category'] as String?) ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_categoryIcon(category), color: const Color(0xFFFF8C6B).withOpacity(0.8), size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35)),
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'accomplishment':
        return Icons.emoji_events_outlined;
      case 'struggle':
        return Icons.cloud_outlined;
      case 'person':
        return Icons.people_outline;
      case 'event':
        return Icons.event_outlined;
      case 'promise':
        return Icons.handshake_outlined;
      default:
        return Icons.auto_awesome_outlined;
    }
  }
}
