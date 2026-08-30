import 'package:flutter/material.dart';
import '../services/api_service.dart';

class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({super.key});

  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  final ApiService _api = ApiService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _memories = [];

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  Future<void> _loadMemories() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final memories = await _api.getMemories();
      if (!mounted) return;
      setState(() {
        _memories = memories;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load memories, try again';
        _loading = false;
      });
    }
  }

  Future<void> _editMemory(Map<String, dynamic> memory) async {
    final controller = TextEditingController(text: memory['memory_text'] ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1035),
        title: const Text('Edit memory', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFFF8C6B)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.6))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save', style: TextStyle(color: Color(0xFFFF8C6B), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) return;

    final newText = controller.text.trim();
    if (newText.isEmpty) return;

    try {
      await _api.updateMemory(memory['id'], memoryText: newText);
      if (!mounted) return;
      setState(() => memory['memory_text'] = newText);
    } catch (e) {
      if (!mounted) return;
      _showError('Could not update memory, try again');
    }
  }

  Future<void> _deleteMemory(Map<String, dynamic> memory) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1035),
        title: const Text('Delete this memory?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Ollie will forget this specific thing. This can\'t be undone.',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.6))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFE53935), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _api.deleteMemory(memory['id']);
      if (!mounted) return;
      setState(() => _memories.removeWhere((m) => m['id'] == memory['id']));
    } catch (e) {
      if (!mounted) return;
      _showError('Could not delete memory, try again');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: const Color(0xFFE53935)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Memories', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _buildBody(),
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
              onPressed: _loadMemories,
              child: const Text('Retry', style: TextStyle(color: Color(0xFFFF8C6B))),
            ),
          ],
        ),
      );
    }

    if (_memories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_stories_outlined, color: Colors.white.withOpacity(0.25), size: 48),
              const SizedBox(height: 16),
              Text(
                "Ollie hasn't saved anything yet",
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'As you talk, the things worth remembering will show up here.',
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFFFF8C6B),
      backgroundColor: const Color(0xFF1A1035),
      onRefresh: _loadMemories,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _memories.length,
        itemBuilder: (context, index) => _memoryCard(_memories[index]),
      ),
    );
  }

  Widget _memoryCard(Map<String, dynamic> memory) {
    final category = (memory['category'] as String?)?.trim();
    final text = (memory['memory_text'] as String?) ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (category != null && category.isNotEmpty) ...[
                  _categoryBadge(category),
                  const SizedBox(height: 6),
                ],
                Text(text, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _iconButton(Icons.edit_outlined, () => _editMemory(memory)),
          _iconButton(Icons.delete_outline, () => _deleteMemory(memory), color: const Color(0xFFE53935)),
        ],
      ),
    );
  }

  Widget _categoryBadge(String category) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFF8C6B).withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _categoryLabel(category),
        style: const TextStyle(
          color: Color(0xFFFF8C6B),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onTap, {Color? color}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: (color ?? Colors.white).withOpacity(0.5), size: 18),
      ),
    );
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'identity':
        return 'About you';
      case 'preference':
        return 'Preference';
      case 'accomplishment':
        return 'Accomplishment';
      case 'struggle':
        return 'Struggle';
      case 'person':
        return 'Person';
      case 'event':
        return 'Event';
      case 'promise':
        return 'Promise';
      default:
        return category;
    }
  }

  IconData _categoryIcon(String? category) {
    switch (category) {
      case 'identity':
        return Icons.person_outline;
      case 'preference':
        return Icons.favorite_border;
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
