import 'package:flutter/material.dart';

// Reporting an Ollie reply. Google Play requires apps that generate
// content with AI to let people report offensive output without
// leaving the app; reports go to the backend's POST /chat/report and
// are reviewed from the moderation_flags table.

const _accent = Color(0xFFFF8C6B);

/// The reasons offered, keyed exactly as the backend expects
/// (chat.py's REPORT_REASONS).
const reportReasons = <String, String>{
  'offensive': 'Offensive or hateful',
  'sexual': 'Sexual or inappropriate',
  'harmful': 'Harmful or dangerous',
  'false': 'False or misleading',
  'other': 'Something else',
};

class ReportChoice {
  final String reason;
  final String? details;
  const ReportChoice(this.reason, this.details);
}

/// Small flag button shown beside every Ollie reply. Same 40px tap
/// target and 32px circle as the speaker button next to it.
class ReportFlagButton extends StatelessWidget {
  final bool reported;
  final VoidCallback onTap;

  const ReportFlagButton({super.key, required this.reported, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: !reported,
      label: reported ? 'Reply reported' : 'Report this reply',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: reported ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Icon(
              reported ? Icons.flag_rounded : Icons.outlined_flag_rounded,
              color: reported ? _accent : Colors.white.withValues(alpha: 0.45),
              size: 15,
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks what's wrong with a reply. Returns null if dismissed.
Future<ReportChoice?> showReportReplySheet(BuildContext context) {
  return showModalBottomSheet<ReportChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const ReportReplySheet(),
  );
}

class ReportReplySheet extends StatefulWidget {
  const ReportReplySheet({super.key});

  @override
  State<ReportReplySheet> createState() => _ReportReplySheetState();
}

class _ReportReplySheetState extends State<ReportReplySheet> {
  String? _reason;
  final TextEditingController _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  void _send() {
    final reason = _reason;
    if (reason == null) return;
    final details = _details.text.trim();
    Navigator.pop(context, ReportChoice(reason, details.isEmpty ? null : details));
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1035),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + keyboard),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Report this reply',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              "What's wrong with it? Reports are private and help make Ollie safer.",
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
            ),
            const SizedBox(height: 16),
            for (final entry in reportReasons.entries)
              _ReasonTile(
                key: Key('report-reason-${entry.key}'),
                label: entry.value,
                selected: _reason == entry.key,
                onTap: () => setState(() => _reason = entry.key),
              ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.white.withValues(alpha: 0.07),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: TextField(
                key: const Key('report-details'),
                controller: _details,
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                cursorColor: _accent,
                decoration: InputDecoration(
                  hintText: 'Add details (optional)',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                  border: InputBorder.none,
                  counterStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                  contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const Key('report-send'),
                onPressed: _reason == null ? null : _send,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  disabledBackgroundColor: _accent.withValues(alpha: 0.3),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.6),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
                child: const Text('Send report', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ReasonTile({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                color: selected ? _accent : Colors.white.withValues(alpha: 0.4),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 15)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
