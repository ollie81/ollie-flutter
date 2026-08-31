import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/api_service.dart';
import 'paywall_screen.dart';
import 'notifications_screen.dart';
import 'chat_search_screen.dart';

// The message an earlier bubble is quoting, shown as a small
// preview inside it -- resolved server-side (see /history), so it
// still renders even when the original message is outside whatever
// page of history is currently loaded.
class ReplyPreview {
  final String sender;
  final String text;
  const ReplyPreview({required this.sender, required this.text});
}

class ChatMessage {
  final String text;
  final bool isOllie;
  final DateTime time;
  // Only ever set on a message the user just sent this session --
  // the photo itself isn't persisted server-side (same principle
  // as voice messages only keeping the transcript), so it won't
  // reappear after a reload from history.
  final File? imageFile;
  // Server-assigned once the save round-trips -- null for the brief
  // window between an optimistically-shown bubble and its response
  // (see _sendMessage). Reply/search-jump are unavailable on a
  // message until this is set; copy never needs it.
  String? id;
  final ReplyPreview? replyTo;
  ChatMessage({
    required this.text,
    required this.isOllie,
    required this.time,
    this.imageFile,
    this.id,
    this.replyTo,
  });
}

class ChatScreen extends StatefulWidget {
  final String phoneNumber;
  // "Do It With Me" -- when set, Ollie opens the conversation
  // itself in this mode instead of waiting for the user to type
  // first, and stays in it (guiding step-by-step, asking what
  // you're working on) for the rest of this chat session.
  final String? initialMode;
  final String? initialModeLabel;
  // Set only right after onboarding -- Ollie's personalized first
  // message uses this name, generated once then never again (see
  // _startWelcomeMessage).
  final String? initialWelcomeName;
  const ChatScreen({
    super.key,
    required this.phoneNumber,
    this.initialMode,
    this.initialModeLabel,
    this.initialWelcomeName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ApiService _api = ApiService();
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final ImagePicker _imagePicker = ImagePicker();

  List<ChatMessage> _messages = [];
  // Set while composing a reply; cleared on send or cancel. Search-
  // jump highlight and per-bubble scroll targets (see
  // _scrollToMessage) are separate, keyed by message id.
  ChatMessage? _replyingTo;
  String? _highlightedMessageId;
  final Map<String, GlobalKey> _messageKeys = {};
  bool _isTyping = false;
  bool _isListening = false; // true while actively recording a voice message
  bool _isTranscribing =
      false; // true while a recorded message is uploading/processing
  bool _recorderInitialized = false;
  DateTime? _recordingStartedAt;
  String _emotionalHeader = "hey there 😊";
  int _currentStreak = 0;
  int _unreadNotifications = 0;
  late String? _activeMode = widget.initialMode;

  // ============================================================
  // VOICE PLAYBACK STATE — elapsed seconds on whichever message is
  // currently playing, plus the free trial balance for non-premium
  // users (null once/if the user is premium -- unlimited, nothing
  // to count).
  // ============================================================
  ChatMessage? _playingMessage;
  int _playingElapsedSeconds = 0;
  Timer? _playbackTimer;
  int? _voiceTrialSecondsRemaining;
  // Gates auto-speaking Ollie's replies (see _maybeAutoSpeak) --
  // free/trial users keep manual tap-to-hear so their one-time
  // trial stays under their own control instead of being spent
  // automatically on every reply.
  bool _isPremium = false;

  // ============================================================
  // AD-REWARD STATE
  // ============================================================
  static const String _rewardedAdUnitId =
      'ca-app-pub-3940256099942544/5224354917';

  RewardedAd? _rewardedAd;

  late AnimationController _orbAnimationController;
  late AnimationController _gradientAnimationController;
  late AnimationController _waveAnimationController;
  late Animation<double> _orbBreathingAnimation;
  late Animation<double> _gradientAnimation;
  final Random _random = Random();

  List<Offset> _particles = [];
  late AnimationController _particleController;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _generateParticles();
    _loadRewardedAd();
    _initChat();
    _loadStreak();
    _loadUnreadCount();
    _audioPlayer.onPlayerComplete.listen((_) => _stopPlaybackTimer());
  }

  Future<void> _loadStreak() async {
    try {
      final usage = await _api.getUsage();
      final streak = usage['current_streak'];
      if (mounted && streak is int) setState(() => _currentStreak = streak);

      final remaining = usage['voice_trial_seconds_remaining'];
      if (mounted && remaining is int)
        setState(() => _voiceTrialSecondsRemaining = remaining);

      final isPremium = usage['is_premium'];
      if (mounted && isPremium is bool) setState(() => _isPremium = isPremium);
    } catch (e) {
      // Streak badge / trial balance / premium status just stay at
      // their defaults if this fails -- never block the chat.
    }
  }

  Future<void> _loadUnreadCount() async {
    try {
      final result = await _api.getNotifications();
      final count = result['unread_count'];
      if (mounted && count is int) setState(() => _unreadNotifications = count);
    } catch (e) {
      // Badge just stays hidden if this fails -- never block the chat.
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    _loadUnreadCount();
  }

  void _applyStreak(Map<String, dynamic> response) {
    final streak = response['streak'];
    if (streak is int) setState(() => _currentStreak = streak);
  }

  void _applyVoiceTrialRemaining(Map<String, dynamic> response) {
    // Absent for premium users (unlimited, nothing to count) --
    // same convention as sendVoiceMessage's header-based version.
    final remaining = response['voice_trial_seconds_remaining'];
    if (remaining is int)
      setState(() => _voiceTrialSecondsRemaining = remaining);
  }

  Future<void> _loadHistory() async {
    try {
      final history = await _api.getHistory();
      if (!mounted || history.isEmpty) return;
      setState(() {
        _messages = history.map((msg) {
          final replyToJson = msg['reply_to'];
          return ChatMessage(
            text: msg['message'] ?? '',
            isOllie: msg['sender'] == 'ollie',
            time: DateTime.tryParse(msg['created_at'] ?? '') ?? DateTime.now(),
            id: msg['id'] as String?,
            replyTo: replyToJson != null
                ? ReplyPreview(
                    sender: replyToJson['sender'] ?? '',
                    text: replyToJson['message'] ?? '',
                  )
                : null,
          );
        }).toList();
      });
      // Jump to the bottom once history has rendered.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    } catch (e) {
      // History load failing should never block the chat from opening.
    }
  }

  // History first, then (if a "Do It With Me" mode was picked, or
  // this is the personalized post-onboarding opener) the greeting
  // -- _loadHistory REPLACES _messages wholesale, so starting either
  // one before it finishes would risk it getting wiped out by the
  // history load landing after it. The two are mutually exclusive
  // entry points (mode vs. brand-new-user welcome), never both.
  Future<void> _initChat() async {
    await _loadHistory();
    if (_activeMode != null) {
      await _startModeSession();
    } else if (widget.initialWelcomeName != null) {
      await _startWelcomeMessage();
    }
  }

  Future<void> _startWelcomeMessage() async {
    if (!mounted) return;
    setState(() => _isTyping = true);
    try {
      final greeting = await _api.getChatWelcome(widget.initialWelcomeName!);
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _messages.add(
          ChatMessage(text: greeting, isOllie: true, time: DateTime.now()),
        );
      });
      _updateEmotionalHeader(greeting);
      _scrollToBottom();
    } catch (e) {
      // Falls back silently -- worst case the user just lands in an
      // empty chat and types first, same as before onboarding existed.
      if (!mounted) return;
      setState(() => _isTyping = false);
    }
  }

  Future<void> _startModeSession() async {
    if (!mounted) return;
    setState(() => _isTyping = true);
    try {
      final opener = await _api.startMode(_activeMode!);
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _messages.add(
          ChatMessage(text: opener, isOllie: true, time: DateTime.now()),
        );
      });
      _updateEmotionalHeader(opener);
      _scrollToBottom();
    } catch (e) {
      // Falls back silently -- the mode still shapes the rest of the
      // conversation even without an opener; the user can just type.
      if (!mounted) return;
      setState(() => _isTyping = false);
    }
  }

  void _initAnimations() {
    _orbAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _orbBreathingAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _orbAnimationController, curve: Curves.easeInOut),
    );

    _gradientAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();

    _gradientAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _gradientAnimationController,
        curve: Curves.linear,
      ),
    );

    _waveAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  void _generateParticles() {
    for (int i = 0; i < 20; i++) {
      _particles.add(Offset(_random.nextDouble(), _random.nextDouble()));
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _updateEmotionalHeader(String message) {
    if (message.contains("sad") ||
        message.contains("bad") ||
        message.contains("cry")) {
      setState(() => _emotionalHeader = "im here 🤗");
    } else if (message.contains("happy") ||
        message.contains("good") ||
        message.contains("great")) {
      setState(() => _emotionalHeader = "let's gooo 🎉");
    } else if (message.contains("love") || message.contains("crush")) {
      setState(() => _emotionalHeader = "awww 💕");
    } else if (message.isEmpty) {
      setState(() => _emotionalHeader = "hey there 😊");
    } else {
      setState(() => _emotionalHeader = "always listening 💡");
    }
  }

  // ============================================================
  // SEND MESSAGE
  // ============================================================

  Future<void> _sendMessage() async {
    // Guards against a rapid double-tap (or Enter held down) firing
    // a second /chat request while the first is still in flight --
    // the backend's daily-cap check isn't safe against that race,
    // so this is the first line of defense against it.
    if (_isTyping || _controller.text.trim().isEmpty) return;

    final userMessage = _controller.text.trim();
    _updateEmotionalHeader(userMessage);
    _controller.clear();
    final replyTarget = _replyingTo;
    _cancelReply();

    final sentMessage = ChatMessage(
      text: userMessage,
      isOllie: false,
      time: DateTime.now(),
      replyTo: replyTarget != null
          ? ReplyPreview(
              sender: replyTarget.isOllie ? 'ollie' : 'user',
              text: replyTarget.text,
            )
          : null,
    );
    setState(() {
      _messages.add(sentMessage);
      _isTyping = true;
    });
    _scrollToBottom();

    await _requestOllieReply(
      userMessage,
      sentMessage: sentMessage,
      replyToId: replyTarget?.id,
    );
  }

  Future<void> _requestOllieReply(
    String userMessage, {
    ChatMessage? sentMessage,
    String? replyToId,
  }) async {
    try {
      final response = await _api.sendMessage(
        message: userMessage,
        mode: _activeMode,
        replyToId: replyToId,
      );

      setState(() => _isTyping = false);
      _updateEmotionalHeader(response['reply']);

      sentMessage?.id = response['user_message_id'] as String?;
      final ollieMessage = ChatMessage(
        text: response['reply'],
        isOllie: true,
        time: DateTime.now(),
        id: response['message_id'] as String?,
      );
      setState(() {
        _messages.add(ollieMessage);
      });
      _applyStreak(response);
      _scrollToBottom();
      _maybeAutoSpeak(ollieMessage);
    } catch (e) {
      setState(() => _isTyping = false);

      if (e.toString().contains('Daily limit reached')) {
        _showLimitReachedSheet(userMessage);
      } else {
        _showError(e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  // ============================================================
  // MESSAGE ACTIONS — reply, copy, and jumping to a message found
  // via search. Reply needs a real id (nothing to attach reply_to_id
  // to before the save round-trips -- see ChatMessage.id); copy
  // never does, it only ever touches local text.
  // ============================================================

  void _startReply(ChatMessage message) {
    if (message.id == null) return;
    setState(() => _replyingTo = message);
  }

  void _cancelReply() {
    if (_replyingTo == null) return;
    setState(() => _replyingTo = null);
  }

  Future<void> _copyMessage(ChatMessage message) async {
    await Clipboard.setData(ClipboardData(text: message.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Copied to clipboard'),
        backgroundColor: const Color(0xFF1A1035),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showMessageActions(ChatMessage message) {
    final canReply = message.id != null;
    final canCopy = message.text.trim().isNotEmpty;
    if (!canReply && !canCopy) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1035),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                if (canReply)
                  _buildAttachmentOption(
                    icon: Icons.reply_rounded,
                    label: 'Reply',
                    onTap: () {
                      Navigator.pop(context);
                      _startReply(message);
                    },
                  ),
                if (canReply && canCopy) const SizedBox(height: 10),
                if (canCopy)
                  _buildAttachmentOption(
                    icon: Icons.copy_rounded,
                    label: 'Copy',
                    onTap: () {
                      Navigator.pop(context);
                      _copyMessage(message);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSearch() async {
    final targetId = await Navigator.push<String?>(
      context,
      MaterialPageRoute(builder: (_) => const ChatSearchScreen()),
    );
    if (targetId != null) _scrollToMessage(targetId);
  }

  GlobalKey _keyFor(String id) =>
      _messageKeys.putIfAbsent(id, () => GlobalKey());

  void _scrollToMessage(String id) {
    final ctx = _messageKeys[id]?.currentContext;
    if (ctx == null) {
      _showError("That message isn't loaded in this chat right now");
      return;
    }
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      alignment: 0.5,
    );
    setState(() => _highlightedMessageId = id);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _highlightedMessageId == id)
        setState(() => _highlightedMessageId = null);
    });
  }

  // ============================================================
  // AD-REWARD FLOW
  // ============================================================

  void _loadRewardedAd() {
    RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
        },
        onAdFailedToLoad: (error) {
          _rewardedAd = null;
        },
      ),
    );
  }

  void _openPaywall() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PaywallScreen()),
    );
  }

  void _showLimitReachedSheet(String pendingMessage) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1035),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "you're out of free messages for today",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "watch a quick ad for 10 more minutes with ollie",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8C6B),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _watchAdForBonus(pendingMessage);
                  },
                  child: const Text(
                    'watch ad for 10 more minutes',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _openPaywall();
                },
                child: Text(
                  'or subscribe for unlimited messages',
                  style: TextStyle(color: Colors.white.withOpacity(0.7)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _watchAdForBonus(String pendingMessage) {
    if (_rewardedAd == null) {
      _showError("ad not ready yet — try again in a moment");
      _loadRewardedAd();
      return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewardedAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _loadRewardedAd();
        _showError("couldn't show ad, try again");
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (ad, reward) async {
        try {
          await _api.watchAdBonus();
          setState(() => _isTyping = true);
          await _requestOllieReply(pendingMessage);
        } catch (e) {
          _showError("couldn't unlock bonus messages, try again");
        }
      },
    );
  }

  // ============================================================
  // IMAGE INPUT — share a photo, get a real reaction to it. Free
  // tier, same daily cap as text (see /chat/image on the backend).
  // ============================================================

  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1035),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                _buildAttachmentOption(
                  icon: Icons.camera_alt_rounded,
                  label: 'Take a photo',
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndPreviewImage(ImageSource.camera);
                  },
                ),
                const SizedBox(height: 10),
                _buildAttachmentOption(
                  icon: Icons.photo_library_rounded,
                  label: 'Choose from gallery',
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndPreviewImage(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF8C6B).withOpacity(0.15),
              ),
              child: Icon(icon, color: const Color(0xFFFF8C6B), size: 20),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndPreviewImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (picked == null || !mounted) return;
      _showImagePreviewSheet(File(picked.path));
    } catch (e) {
      _showError(
        'Could not access ${source == ImageSource.camera ? 'the camera' : 'your photos'}',
      );
    }
  }

  void _showImagePreviewSheet(File imageFile) {
    final captionController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1035),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.file(
                      imageFile,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 260,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white.withOpacity(0.07),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: TextField(
                      controller: captionController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Add a caption (optional)',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.35),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8C6B),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _sendImageMessage(imageFile, captionController.text);
                      },
                      child: const Text(
                        'Send to Ollie',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _sendImageMessage(File imageFile, String? caption) async {
    if (_isTyping) return;
    final trimmedCaption = caption?.trim();

    final sentMessage = ChatMessage(
      text: trimmedCaption ?? '',
      isOllie: false,
      time: DateTime.now(),
      imageFile: imageFile,
    );
    setState(() {
      _messages.add(sentMessage);
    });
    if (trimmedCaption != null && trimmedCaption.isNotEmpty) {
      _updateEmotionalHeader(trimmedCaption);
    }
    _scrollToBottom();
    await _requestImageReaction(
      imageFile,
      trimmedCaption,
      sentMessage: sentMessage,
    );
  }

  Future<void> _requestImageReaction(
    File imageFile,
    String? caption, {
    ChatMessage? sentMessage,
  }) async {
    setState(() => _isTyping = true);
    try {
      final response = await _api.sendImageMessage(imageFile, caption: caption);
      setState(() => _isTyping = false);

      final reply = response['reply'] as String?;
      if (reply == null) {
        _showError("couldn't get a reply for that photo");
        return;
      }

      sentMessage?.id = response['user_message_id'] as String?;
      final ollieMessage = ChatMessage(
        text: reply,
        isOllie: true,
        time: DateTime.now(),
        id: response['message_id'] as String?,
      );
      setState(() => _messages.add(ollieMessage));
      _applyStreak(response);
      _updateEmotionalHeader(reply);
      _scrollToBottom();
      _maybeAutoSpeak(ollieMessage);
    } catch (e) {
      setState(() => _isTyping = false);
      if (e.toString().contains('Daily limit reached')) {
        _showImageLimitReachedSheet(imageFile, caption);
      } else {
        _showError(e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  void _showImageLimitReachedSheet(File imageFile, String? caption) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1035),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "you're out of free messages for today",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "watch a quick ad for 10 more minutes with ollie",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8C6B),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _watchAdForImageBonus(imageFile, caption);
                  },
                  child: const Text(
                    'watch ad for 10 more minutes',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _openPaywall();
                },
                child: Text(
                  'or subscribe for unlimited messages',
                  style: TextStyle(color: Colors.white.withOpacity(0.7)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _watchAdForImageBonus(File imageFile, String? caption) {
    if (_rewardedAd == null) {
      _showError("ad not ready yet — try again in a moment");
      _loadRewardedAd();
      return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewardedAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _loadRewardedAd();
        _showError("couldn't show ad, try again");
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (ad, reward) async {
        try {
          await _api.watchAdBonus();
          await _requestImageReaction(imageFile, caption);
        } catch (e) {
          _showError("couldn't unlock bonus messages, try again");
        }
      },
    );
  }

  // ============================================================
  // VOICE — OUTPUT (speaker, hits the backend TTS endpoint)
  // ============================================================

  Future<void> _speakMessage(ChatMessage message) async {
    try {
      final result = await _api.sendVoiceMessage(message: message.text);
      if (result.voiceTrialSecondsRemaining != null && mounted) {
        setState(
          () => _voiceTrialSecondsRemaining = result.voiceTrialSecondsRemaining,
        );
      }
      if (result.file != null) {
        _startPlaybackTimer(message);
        await _audioPlayer.play(DeviceFileSource(result.file!.path));
      }
    } catch (e) {
      final text = e.toString().replaceFirst('Exception: ', '');
      if (text.contains('Premium')) {
        _showVoicePremiumSheet();
      } else {
        _showError(text);
      }
    }
  }

  // Premium hears every reply automatically, no tap needed --
  // free/trial users keep the manual speaker icon (see _isPremium)
  // so their one-time trial isn't spent without them choosing to.
  // Not awaited -- playback runs in the background, callers don't
  // wait on it before moving on.
  void _maybeAutoSpeak(ChatMessage message) {
    if (_isPremium) _speakMessage(message);
  }

  void _startPlaybackTimer(ChatMessage message) {
    _playbackTimer?.cancel();
    setState(() {
      _playingMessage = message;
      _playingElapsedSeconds = 0;
    });
    _playbackTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _playingElapsedSeconds++);
    });
  }

  void _stopPlaybackTimer() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    if (mounted) setState(() => _playingMessage = null);
  }

  // ============================================================
  // VOICE — INPUT (real mic recording + transcription). Hold the
  // mic button to record, release to send. Shares the same free
  // trial balance as the speaker icon — see /chat/voice on the
  // backend.
  // ============================================================

  Future<bool> _initRecorder() async {
    if (_recorderInitialized) return true;
    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        _showError('Microphone permission is needed to send a voice message');
        return false;
      }
      await _recorder.openRecorder();
      _recorderInitialized = true;
      return true;
    } catch (e) {
      _showError('Could not access the microphone');
      return false;
    }
  }

  Future<void> _startRecording() async {
    if (_isListening || _isTranscribing) return;

    final ready = await _initRecorder();
    if (!ready) return;

    try {
      final tempDir = await getTemporaryDirectory();
      final path =
          '${tempDir.path}/ollie_voice_message_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.startRecorder(
        toFile: path,
        codec: Codec.aacMP4,
        sampleRate: 16000,
        numChannels: 1,
      );
      _recordingStartedAt = DateTime.now();
      setState(() => _isListening = true);
    } catch (e) {
      _showError('Could not start recording');
    }
  }

  Future<void> _stopRecordingAndSend() async {
    if (!_isListening) return;

    setState(() => _isListening = false);

    String? path;
    try {
      path = await _recorder.stopRecorder();
    } catch (e) {
      _showError('Recording failed');
      return;
    }

    final startedAt = _recordingStartedAt;
    _recordingStartedAt = null;

    // Ignore accidental taps -- anything under half a second isn't
    // a real voice message.
    if (path == null ||
        startedAt == null ||
        DateTime.now().difference(startedAt) <
            const Duration(milliseconds: 500)) {
      return;
    }

    setState(() => _isTranscribing = true);

    try {
      final response = await _api.sendVoiceChat(File(path), mode: _activeMode);
      final transcribed = (response['transcribed_text'] as String?)?.trim();
      final reply = response['reply'] as String?;

      if (transcribed == null || transcribed.isEmpty || reply == null) {
        _showError("couldn't hear anything in that recording");
        return;
      }

      _updateEmotionalHeader(transcribed);
      final ollieMessage = ChatMessage(
        text: reply,
        isOllie: true,
        time: DateTime.now(),
        id: response['message_id'] as String?,
      );
      setState(() {
        _messages.add(
          ChatMessage(
            text: transcribed,
            isOllie: false,
            time: DateTime.now(),
            id: response['user_message_id'] as String?,
          ),
        );
        _messages.add(ollieMessage);
      });
      _applyStreak(response);
      _applyVoiceTrialRemaining(response);
      _updateEmotionalHeader(reply);
      _scrollToBottom();
      _maybeAutoSpeak(ollieMessage);
    } catch (e) {
      final text = e.toString().replaceFirst('Exception: ', '');
      if (text.contains('Premium')) {
        _showVoicePremiumSheet();
      } else {
        _showError(text);
      }
    } finally {
      if (mounted) setState(() => _isTranscribing = false);
    }
  }

  // ============================================================
  // VOICE PREVIEW — free, short, fixed sample so someone can
  // hear what Ollie sounds like before deciding to go premium.
  // ============================================================

  bool _isPreviewing = false;

  Future<void> _playVoicePreview() async {
    if (_isPreviewing) return;
    setState(() => _isPreviewing = true);
    try {
      final audioFile = await _api.getVoicePreview();
      if (audioFile != null) {
        await _audioPlayer.play(DeviceFileSource(audioFile.path));
      }
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isPreviewing = false);
    }
  }

  void _showVoicePremiumSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1035),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Icon(Icons.mic_rounded, color: Color(0xFFFF8C6B), size: 32),
              const SizedBox(height: 12),
              const Text(
                "talking with ollie is a premium thing",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "go premium to talk to ollie and hear him talk back, anytime",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8C6B),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _openPaywall();
                  },
                  child: const Text(
                    'go premium',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _playVoicePreview();
                },
                child: Text(
                  "hear a quick sample first",
                  style: TextStyle(color: Colors.white.withOpacity(0.7)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _particleController,
            builder: (context, child) {
              return CustomPaint(
                painter: ParticlePainter(
                  particles: _particles,
                  time: _particleController.value,
                ),
                size: Size.infinite,
              );
            },
          ),
          AnimatedBuilder(
            animation: _gradientAnimation,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(
                        const Color(0xFF0D0F1A),
                        const Color(0xFF1A1035),
                        _gradientAnimation.value,
                      )!,
                      Color.lerp(
                        const Color(0xFF151829),
                        const Color(0xFF2D1B4E),
                        _gradientAnimation.value,
                      )!,
                      const Color(0xFF1A1035),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      _buildHeader(),
                      _buildEmotionalHeader(),
                      Expanded(child: _buildMessageList()),
                      if (_isTyping) _buildTypingIndicator(),
                      _buildInputBar(),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          AnimatedBuilder(
            animation: _orbAnimationController,
            builder: (context, child) {
              return Transform.scale(
                scale: _orbBreathingAnimation.value,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF8C6B), Color(0xFFE86B4A)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF8C6B).withOpacity(0.5),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'O',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ollie',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                widget.initialModeLabel ?? 'always here',
                style: TextStyle(
                  color: widget.initialModeLabel != null
                      ? const Color(0xFFFF8C6B)
                      : Colors.grey,
                  fontSize: 12,
                  fontWeight: widget.initialModeLabel != null
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (_currentStreak > 0) ...[
            _buildStreakBadge(),
            const SizedBox(width: 4),
          ],
          IconButton(
            icon: const Icon(Icons.search_rounded, color: Colors.white),
            onPressed: _openSearch,
          ),
          _buildNotificationBell(),
        ],
      ),
    );
  }

  Widget _buildNotificationBell() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(
            Icons.notifications_none_rounded,
            color: Colors.white,
          ),
          onPressed: _openNotifications,
        ),
        if (_unreadNotifications > 0)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: const BoxDecoration(
                color: Color(0xFFFF8C6B),
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              child: Text(
                _unreadNotifications > 9 ? '9+' : '$_unreadNotifications',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStreakBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFFFF8C6B).withOpacity(0.15),
        border: Border.all(color: const Color(0xFFFF8C6B).withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔥', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(
            '$_currentStreak',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmotionalHeader() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFF8C6B).withOpacity(0.2),
            const Color(0xFFE86B4A).withOpacity(0.1),
          ],
        ),
        border: Border.all(color: const Color(0xFFFF8C6B).withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF8C6B).withOpacity(0.1),
            blurRadius: 15,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _emotionalHeader,
              key: ValueKey(_emotionalHeader),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatElapsed(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  Widget _buildSpeakerControl(ChatMessage message) {
    final isPlayingThis = identical(_playingMessage, message);

    if (!isPlayingThis) {
      return GestureDetector(
        onTap: () => _speakMessage(message),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFF8C6B).withOpacity(0.15),
            border: Border.all(color: const Color(0xFFFF8C6B).withOpacity(0.3)),
          ),
          child: const Icon(
            Icons.volume_up_rounded,
            color: Color(0xFFFF8C6B),
            size: 14,
          ),
        ),
      );
    }

    final trialSuffix = _voiceTrialSecondsRemaining != null
        ? ' · ${_voiceTrialSecondsRemaining}s left'
        : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFFFF8C6B).withOpacity(0.15),
        border: Border.all(color: const Color(0xFFFF8C6B).withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.graphic_eq_rounded,
            color: Color(0xFFFF8C6B),
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            '${_formatElapsed(_playingElapsedSeconds)}$trialSuffix',
            style: const TextStyle(
              color: Color(0xFFFF8C6B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return _buildEmptyState();
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final hasImage = message.imageFile != null;
        final hasCaption = message.text.trim().isNotEmpty;
        final isHighlighted =
            message.id != null && message.id == _highlightedMessageId;
        final bubbleRadius = BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: message.isOllie
              ? const Radius.circular(4)
              : const Radius.circular(20),
          bottomRight: message.isOllie
              ? const Radius.circular(20)
              : const Radius.circular(4),
        );
        return AnimatedOpacity(
          key: message.id != null ? _keyFor(message.id!) : null,
          opacity: 1,
          duration: const Duration(milliseconds: 400),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: message.isOllie
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Ollie avatar
                if (message.isOllie) ...[
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFFFF8C6B), Color(0xFFE86B4A)],
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        'O',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // Message bubble
                Flexible(
                  child: GestureDetector(
                    onLongPress: () => _showMessageActions(message),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      constraints: BoxConstraints(
                        maxWidth:
                            MediaQuery.of(context).size.width *
                            (hasImage ? 0.68 : 0.7),
                      ),
                      padding: hasImage
                          ? EdgeInsets.zero
                          : const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                      decoration: BoxDecoration(
                        borderRadius: bubbleRadius,
                        gradient: message.isOllie
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white.withOpacity(0.12),
                                  Colors.white.withOpacity(0.06),
                                ],
                              )
                            : const LinearGradient(
                                colors: [Color(0xFFFF8C6B), Color(0xFFE86B4A)],
                              ),
                        border: isHighlighted
                            ? Border.all(
                                color: const Color(0xFFFF8C6B),
                                width: 2,
                              )
                            : (message.isOllie
                                  ? Border.all(
                                      color: Colors.white.withOpacity(0.08),
                                    )
                                  : null),
                        boxShadow: [
                          BoxShadow(
                            color: message.isOllie
                                ? Colors.black.withOpacity(0.1)
                                : const Color(0xFFFF8C6B).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: hasImage
                          ? ClipRRect(
                              borderRadius: bubbleRadius,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxHeight: 260,
                                    ),
                                    child: Image.file(
                                      message.imageFile!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                    ),
                                  ),
                                  if (hasCaption)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      child: Text(
                                        message.text,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (message.replyTo != null)
                                  _buildReplyQuote(message.replyTo!),
                                Text(
                                  message.text.replaceAll(
                                    RegExp(r'\n{2,}'),
                                    '\n',
                                  ),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
                // Speaker only on Ollie messages
                if (message.isOllie) ...[
                  const SizedBox(width: 8),
                  _buildSpeakerControl(message),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReplyQuote(ReplyPreview reply) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: Colors.white.withOpacity(0.4), width: 3),
        ),
      ),
      child: Text(
        reply.text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white.withOpacity(0.7),
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _orbAnimationController,
            builder: (context, child) {
              return Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFFF8C6B).withOpacity(0.3),
                      const Color(0xFFFF8C6B).withOpacity(0),
                    ],
                  ),
                ),
                child: Transform.scale(
                  scale: _orbBreathingAnimation.value,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF8C6B), Color(0xFFE86B4A)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF8C6B).withOpacity(0.6),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'hey there 😊',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'How are you feeling?',
            style: TextStyle(color: Colors.grey.withOpacity(0.7), fontSize: 14),
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: _isPreviewing ? null : _playVoicePreview,
            icon: _isPreviewing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFFF8C6B),
                    ),
                  )
                : const Icon(
                    Icons.volume_up_rounded,
                    color: Color(0xFFFF8C6B),
                    size: 18,
                  ),
            label: Text(
              "hear what ollie sounds like",
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFFF8C6B), Color(0xFFE86B4A)],
              ),
            ),
            child: const Center(
              child: Text(
                'O',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.white.withOpacity(0.08),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildAnimatedDot(0),
                const SizedBox(width: 6),
                _buildAnimatedDot(1),
                const SizedBox(width: 6),
                _buildAnimatedDot(2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedDot(int index) {
    return AnimatedBuilder(
      animation: _waveAnimationController,
      builder: (context, child) {
        final value = (_waveAnimationController.value + index / 3) % 1;
        final scale = 0.5 + 0.8 * sin(value * pi).abs();
        final opacity = 0.4 + 0.6 * sin(value * pi).abs();
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFFF8C6B), Color(0xFFE86B4A)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF8C6B).withOpacity(opacity * 0.8),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withOpacity(0.3)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyingTo != null) _buildReplyingToBar(),
          Row(
            children: [
              // Share a photo with Ollie.
              GestureDetector(
                onTap: _showAttachmentSheet,
                child: Container(
                  width: 44,
                  height: 44,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.07),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Icon(
                    Icons.camera_alt_rounded,
                    color: Colors.white.withOpacity(0.7),
                    size: 20,
                  ),
                ),
              ),
              // Hold to record a voice message, release to send.
              GestureDetector(
                onLongPressStart: (_) => _startRecording(),
                onLongPressEnd: (_) => _stopRecordingAndSend(),
                onLongPressCancel: () => _stopRecordingAndSend(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 48,
                  height: 48,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isListening
                        ? const Color(0xFFE53935).withOpacity(0.25)
                        : Colors.white.withOpacity(0.07),
                    border: Border.all(
                      color: _isListening
                          ? const Color(0xFFE53935)
                          : Colors.white.withOpacity(0.1),
                    ),
                  ),
                  child: _isTranscribing
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFFF8C6B),
                          ),
                        )
                      : Icon(
                          _isListening
                              ? Icons.mic_rounded
                              : Icons.mic_none_rounded,
                          color: _isListening
                              ? const Color(0xFFE53935)
                              : Colors.white.withOpacity(0.7),
                          size: 22,
                        ),
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    color: Colors.white.withOpacity(0.07),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    maxLines: null,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.3),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _sendMessage,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF8C6B), Color(0xFFE86B4A)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF8C6B).withOpacity(0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReplyingToBar() {
    final target = _replyingTo!;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: const Color(0xFFFF8C6B), width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target.isOllie ? 'Replying to Ollie' : 'Replying to yourself',
                  style: const TextStyle(
                    color: Color(0xFFFF8C6B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  target.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _cancelReply,
            child: Icon(
              Icons.close_rounded,
              color: Colors.white.withOpacity(0.5),
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _orbAnimationController.dispose();
    _gradientAnimationController.dispose();
    _waveAnimationController.dispose();
    _particleController.dispose();
    _playbackTimer?.cancel();
    _audioPlayer.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _rewardedAd?.dispose();
    if (_recorderInitialized) {
      _recorder.closeRecorder();
    }
    super.dispose();
  }
}

class ParticlePainter extends CustomPainter {
  final List<Offset> particles;
  final double time;

  ParticlePainter({required this.particles, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFFF8C6B).withOpacity(0.05);

    for (int i = 0; i < particles.length; i++) {
      final offset = Offset(
        (particles[i].dx + time * 0.01) % 1 * size.width,
        (particles[i].dy + time * 0.005) % 1 * size.height,
      );
      canvas.drawCircle(offset, 2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
