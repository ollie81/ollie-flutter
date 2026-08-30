import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

// Searches the user's FULL message history server-side (not just
// the last 50 the chat screen keeps loaded) -- its own screen
// rather than an inline app-bar search field, same "each feature
// gets its own screen" approach as auth. Tapping a result pops back
// to the chat screen with that message's id, which scrolls to it if
// it's currently loaded there (see ChatScreen._scrollToMessage).
class ChatSearchScreen extends StatefulWidget {
  const ChatSearchScreen({super.key});

  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  List<dynamic> _results = [];
  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();
    setState(() {}); // refresh the clear (x) button's visibility
    if (trimmed.isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
        _isSearching = false;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _runSearch(trimmed),
    );
  }

  Future<void> _runSearch(String query) async {
    setState(() => _isSearching = true);
    try {
      final results = await _api.searchChat(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _hasSearched = true;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _hasSearched = true;
        _isSearching = false;
      });
    }
  }

  String _formatTimestamp(String? raw) {
    final time = DateTime.tryParse(raw ?? '');
    if (time == null) return '';
    final local = time.toLocal();
    final now = DateTime.now();
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    final time12 = '$hour:$minute $ampm';
    return sameDay ? time12 : '${local.month}/${local.day} · $time12';
  }

  List<TextSpan> _highlightedSpans(String text, String query) {
    if (query.isEmpty) return [TextSpan(text: text)];
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start)
        spans.add(TextSpan(text: text.substring(start, index)));
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: const TextStyle(
            color: Color(0xFFFF8C6B),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      start = index + query.length;
    }
    return spans;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              _buildSearchHeader(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: Colors.white.withOpacity(0.07),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: const TextStyle(color: Colors.white),
                onChanged: _onQueryChanged,
                decoration: InputDecoration(
                  hintText: 'Search your chats with Ollie...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
                  border: InputBorder.none,
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: Colors.white.withOpacity(0.4),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withOpacity(0.4),
                            size: 18,
                          ),
                          onPressed: () {
                            _controller.clear();
                            _onQueryChanged('');
                          },
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF8C6B)),
      );
    }
    if (!_hasSearched) {
      return _buildPlaceholder(
        Icons.search_rounded,
        "Search anything you or Ollie said",
      );
    }
    if (_results.isEmpty) {
      return _buildPlaceholder(Icons.search_off_rounded, "No messages found");
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _results.length,
      itemBuilder: (context, index) => _buildResultTile(_results[index]),
    );
  }

  Widget _buildPlaceholder(IconData icon, String label) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.15), size: 56),
          const SizedBox(height: 16),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultTile(dynamic result) {
    final isOllie = result['sender'] == 'ollie';
    final text = result['message'] as String? ?? '';
    final query = _controller.text.trim();
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.pop(context, result['id'] as String?),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withOpacity(0.05),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isOllie
                    ? const LinearGradient(
                        colors: [Color(0xFFFF8C6B), Color(0xFFE86B4A)],
                      )
                    : null,
                color: isOllie ? null : Colors.white.withOpacity(0.12),
              ),
              child: Center(
                child: isOllie
                    ? const Text(
                        'O',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : Icon(
                        Icons.person,
                        color: Colors.white.withOpacity(0.6),
                        size: 14,
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isOllie ? 'Ollie' : 'You',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTimestamp(result['created_at'] as String?),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.35),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  RichText(
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: 13,
                        height: 1.3,
                      ),
                      children: _highlightedSpans(text, query),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
