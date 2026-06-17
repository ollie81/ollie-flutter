import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/api_service.dart';
import 'dart:math';

class ChatMessage {
  final String text;
  final bool isOllie;
  final DateTime time;
  ChatMessage({required this.text, required this.isOllie, required this.time});
}

class ChatScreen extends StatefulWidget {
  final String phoneNumber;
  const ChatScreen({super.key, required this.phoneNumber});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ApiService _api = ApiService();

  List<ChatMessage> _messages = [];
  bool _isTyping = false;
  bool _isListening = false;
  String _emotionalHeader = "hey there 😊";

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
      CurvedAnimation(parent: _gradientAnimationController, curve: Curves.linear),
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
    if (message.contains("sad") || message.contains("bad") || message.contains("cry")) {
      setState(() => _emotionalHeader = "im here 🤗");
    } else if (message.contains("happy") || message.contains("good") || message.contains("great")) {
      setState(() => _emotionalHeader = "let's gooo 🎉");
    } else if (message.contains("love") || message.contains("crush")) {
      setState(() => _emotionalHeader = "awww 💕");
    } else if (message.isEmpty) {
      setState(() => _emotionalHeader = "hey there 😊");
    } else {
      setState(() => _emotionalHeader = "always listening 💡");
    }
  }

  Future<void> _sendMessage() async {
    if (_controller.text.trim().isEmpty) return;

    final userMessage = _controller.text.trim();
    _updateEmotionalHeader(userMessage);
    _controller.clear();

    setState(() {
      _messages.add(ChatMessage(text: userMessage, isOllie: false, time: DateTime.now()));
      _isTyping = true;
    });
    _scrollToBottom();

    try {
      final response = await _api.sendMessage(
  message: userMessage,
);

      setState(() => _isTyping = false);
      _updateEmotionalHeader(response['reply']);

      setState(() {
        _messages.add(ChatMessage(text: response['reply'], isOllie: true, time: DateTime.now()));
      });
      _scrollToBottom();
    } catch (e) {
      setState(() => _isTyping = false);
      _showError(e.toString());
    }
  }

  // FIX 3 — Voice button now works
  Future<void> _sendVoiceMessage() async {
    setState(() => _isListening = true);

    await Future.delayed(const Duration(seconds: 2));

    setState(() => _isListening = false);
    setState(() => _isTyping = true);

    try {
    final response = await _api.sendMessage(
  message: "hey",
);
      setState(() {
        _isTyping = false;
        _messages.add(ChatMessage(
          text: response['reply'],
          isOllie: true,
          time: DateTime.now(),
        ));
      });
      _scrollToBottom();
    } catch (e) {
      setState(() => _isTyping = false);
      _showError(e.toString());
    }
  }

  Future<void> _speakMessage(String message) async {
    try {
      final audioFile = await _api.sendVoiceMessage(
  message: message,
);
      if (audioFile != null) {
        await _audioPlayer.play(DeviceFileSource(audioFile.path));
      }
    } catch (e) {
      _showError(e.toString());
    }
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
                painter: ParticlePainter(particles: _particles, time: _particleController.value),
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
                      Color.lerp(const Color(0xFF0D0F1A), const Color(0xFF1A1035), _gradientAnimation.value)!,
                      Color.lerp(const Color(0xFF151829), const Color(0xFF2D1B4E), _gradientAnimation.value)!,
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
                    child: Text('O', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ollie', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              Text('always here', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
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
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
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
        return AnimatedOpacity(
          opacity: 1,
          duration: const Duration(milliseconds: 400),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: message.isOllie ? MainAxisAlignment.start : MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Ollie avatar
                if (message.isOllie) ...[
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [Color(0xFFFF8C6B), Color(0xFFE86B4A)]),
                    ),
                    child: const Center(child: Text('O', style: TextStyle(color: Colors.white, fontSize: 13))),
                  ),
                  const SizedBox(width: 8),
                ],
                // Message bubble
                Flexible(
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20),
                        topRight: const Radius.circular(20),
                        bottomLeft: message.isOllie ? const Radius.circular(4) : const Radius.circular(20),
                        bottomRight: message.isOllie ? const Radius.circular(20) : const Radius.circular(4),
                      ),
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
                      border: message.isOllie
                          ? Border.all(color: Colors.white.withOpacity(0.08))
                          : null,
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
                    child: Text(
                      message.text,
                      style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                    ),
                  ),
                ),
                // Speaker only on Ollie messages
                if (message.isOllie) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _speakMessage(message.text),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFFF8C6B).withOpacity(0.15),
                        border: Border.all(color: const Color(0xFFFF8C6B).withOpacity(0.3)),
                      ),
                      child: const Icon(Icons.volume_up_rounded, color: Color(0xFFFF8C6B), size: 14),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
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
                      gradient: const LinearGradient(colors: [Color(0xFFFF8C6B), Color(0xFFE86B4A)]),
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
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'How are you feeling?',
            style: TextStyle(color: Colors.grey.withOpacity(0.7), fontSize: 14),
          ),
        ],
      ),
    );
  }

  // FIX 2 — Beautiful glowing dots
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
              gradient: LinearGradient(colors: [Color(0xFFFF8C6B), Color(0xFFE86B4A)]),
            ),
            child: const Center(child: Text('O', style: TextStyle(color: Colors.white, fontSize: 13))),
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
      child: Row(
        children: [
          // FIX 3 — Voice button works on tap
          GestureDetector(
            onTap: () => _sendVoiceMessage(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isListening
                    ? const Color(0xFFFF8C6B)
                    : Colors.white.withOpacity(0.07),
                border: Border.all(
                  color: _isListening
                      ? const Color(0xFFFF8C6B)
                      : Colors.white.withOpacity(0.1),
                ),
                boxShadow: _isListening
                    ? [
                        BoxShadow(
                          color: const Color(0xFFFF8C6B).withOpacity(0.5),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                _isListening ? Icons.mic : Icons.mic_none,
                color: _isListening ? Colors.white : const Color(0xFFFF8C6B),
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 10),
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
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
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
    _audioPlayer.dispose();
    _controller.dispose();
    _scrollController.dispose();
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
