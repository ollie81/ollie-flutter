import 'package:flutter/material.dart';
import '../services/api_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final ApiService _api = ApiService();
  bool _loading = true;
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await _api.getNotifications();
    if (!mounted) return;
    setState(() {
      _notifications = List<Map<String, dynamic>>.from(result['notifications'] ?? []);
      _loading = false;
    });
  }

  Future<void> _onTapNotification(Map<String, dynamic> notification) async {
    if (notification['is_read'] == true) return;
    setState(() => notification['is_read'] = true);
    await _api.markNotificationRead(notification['id']);
  }

  String _relativeTime(String? createdAt) {
    final parsed = DateTime.tryParse(createdAt ?? '');
    if (parsed == null) return '';
    final diff = DateTime.now().difference(parsed);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${parsed.month}/${parsed.day}/${parsed.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Notifications', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: const Color(0xFFFF8C6B),
        backgroundColor: const Color(0xFF1A1D2E),
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF8C6B)))
            : _notifications.isEmpty
                ? _buildEmpty()
                : _buildList(),
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Center(
            child: Text(
              "nothing here yet — Ollie's messages will show up in this list",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _notifications.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final notification = _notifications[index];
        final isRead = notification['is_read'] == true;

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _onTapNotification(notification),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: isRead ? const Color(0xFF1A1D2E) : const Color(0xFFFF8C6B).withOpacity(0.1),
              border: Border.all(
                color: isRead ? Colors.white.withOpacity(0.06) : const Color(0xFFFF8C6B).withOpacity(0.3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isRead)
                  Container(
                    margin: const EdgeInsets.only(top: 6, right: 10),
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: Color(0xFFFF8C6B), shape: BoxShape.circle),
                  )
                else
                  const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notification['title'] ?? 'Ollie',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            _relativeTime(notification['created_at']),
                            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _buildBody(notification),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // The nightly recap ("Today with Ollie") sends its body as
  // "- line one\n- line two" -- render those as a small bulleted
  // list instead of a wall of dashes. Every other notification
  // (including the morning check-in) just renders as plain text.
  Widget _buildBody(Map<String, dynamic> notification) {
    final body = notification['body'] as String? ?? '';
    final lines = body.split('\n').map((l) => l.trim()).where((l) => l.startsWith('- ')).toList();

    if (notification['title'] != 'Today with Ollie' || lines.isEmpty) {
      return Text(
        body,
        style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 14, height: 1.4),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF8C6B).withOpacity(0.7),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  line.substring(2),
                  style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 14, height: 1.4),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
