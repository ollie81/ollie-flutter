import 'package:flutter/material.dart';

const _accent = Color(0xFFFF8C6B);
const _recordingRed = Color(0xFFE53935);

/// The hold-to-talk mic in the chat input bar: hold to record a voice
/// message, release to send.
///
/// With [comingSoon] (the Play Store build -- see
/// config/store_build.dart) it never records: a tap or a hold calls
/// [onComingSoon] instead, and a small "soon" tag sits on the button,
/// so people can see voice is on its way.
class VoiceRecordButton extends StatelessWidget {
  final bool comingSoon;
  final bool isListening;
  final bool isTranscribing;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final VoidCallback onComingSoon;

  const VoiceRecordButton({
    super.key,
    required this.comingSoon,
    required this.isListening,
    required this.isTranscribing,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onComingSoon,
  });

  @override
  Widget build(BuildContext context) {
    final listening = isListening && !comingSoon;
    final circle = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: listening ? _recordingRed.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.07),
        border: Border.all(color: listening ? _recordingRed : Colors.white.withValues(alpha: 0.1)),
      ),
      child: isTranscribing && !comingSoon
          ? const Padding(
              padding: EdgeInsets.all(14),
              child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
            )
          : Icon(
              listening ? Icons.mic_rounded : Icons.mic_none_rounded,
              color: listening
                  ? _recordingRed
                  : Colors.white.withValues(alpha: comingSoon ? 0.35 : 0.7),
              size: 22,
            ),
    );

    if (comingSoon) {
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Semantics(
          button: true,
          label: 'Voice messages, coming soon',
          excludeSemantics: true,
          child: GestureDetector(
            key: const Key('voice-coming-soon'),
            onTap: onComingSoon,
            onLongPress: onComingSoon,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                circle,
                Positioned(
                  top: -6,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'soon',
                      style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        key: const Key('voice-record'),
        onLongPressStart: (_) => onStartRecording(),
        onLongPressEnd: (_) => onStopRecording(),
        onLongPressCancel: onStopRecording,
        child: circle,
      ),
    );
  }
}
