import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/api_service.dart';

// "Our Space" -- the shared history between Ollie and the user.
// Shows the relationship stage (never a streak -- see the backend's
// relationship.py for why) plus goals worked on, accomplishments,
// and moments worth looking back on. stage_label comes straight from
// the backend and isn't localized here (same scoping as the web
// app's OurSpace.tsx port).
class OurSpaceScreen extends StatefulWidget {
  const OurSpaceScreen({super.key});

  @override
  State<OurSpaceScreen> createState() => _OurSpaceScreenState();
}

class _OurSpaceScreenState extends State<OurSpaceScreen> {
  final ApiService _api = ApiService();

  bool _loading = true;
  // The localized error message is built in _buildBody (from this
  // flag), not stored here -- AppLocalizations.of(context) isn't
  // safe to call from initState's synchronous call into _loadJourney.
  bool _hasError = false;
  Map<String, dynamic>? _journey;

  @override
  void initState() {
    super.initState();
    _loadJourney();
  }

  Future<void> _loadJourney() async {
    setState(() {
      _loading = true;
      _hasError = false;
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
        _hasError = true;
        _loading = false;
      });
    }
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
            children: [
              _buildAppBar(l10n),
              Expanded(child: _buildBody(l10n)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            l10n.ourSpaceTitle,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFF8C6B)));
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.ourSpaceLoadError, style: TextStyle(color: Colors.white.withOpacity(0.6))),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loadJourney,
              child: Text(l10n.commonRetry, style: const TextStyle(color: Color(0xFFFF8C6B))),
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
          _stageHero(l10n, journey),
          const SizedBox(height: 24),
          if (isEmpty)
            _emptyState(l10n)
          else ...[
            if (activeGoals.isNotEmpty) ...[
              _sectionHeader(l10n.ourSpaceWorkingTogether),
              ...activeGoals.map((g) => _goalTile(g, done: false)),
            ],
            if (completedGoals.isNotEmpty) ...[
              const SizedBox(height: 16),
              _sectionHeader(l10n.ourSpaceAccomplished),
              ...completedGoals.map((g) => _goalTile(g, done: true)),
            ],
            if (highlights.isNotEmpty) ...[
              const SizedBox(height: 16),
              _sectionHeader(l10n.ourSpaceMoments),
              ...highlights.map((m) => _highlightTile(m)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _stageHero(AppLocalizations l10n, Map<String, dynamic> journey) {
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
            activeDays == 0 ? l10n.ourSpaceStoryStarting : l10n.ourSpaceDaysTogether(activeDays, memoryCount),
            style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _emptyState(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.auto_awesome_outlined, color: Colors.white.withOpacity(0.25), size: 44),
          const SizedBox(height: 16),
          Text(
            l10n.ourSpaceNothingYet,
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.ourSpaceNothingYetDescription,
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
