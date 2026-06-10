import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class VoiceService {
  WebSocketChannel? _channel;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isConnected = false;
  bool _isRecording = false;
  bool _recorderInitialized = false;

  Function(String)? onPartialText;
  Function(String)? onFinalText;
  Function(List<int>)? onAudioChunk;
  Function(String)? onError;

  // ============================================================
  // CONNECT TO SERVER
  // ============================================================

  Future<void> connect(String phoneNumber) async {
    final serverUrl = Platform.isAndroid
        ? 'ws://10.0.2.2:8000'
        : 'ws://localhost:8000';

    final wsUrl = '$serverUrl/ollie/voice/$phoneNumber';

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;

      _channel!.stream.listen((dynamic message) {
        if (message is String) {
          final data = jsonDecode(message);
          final type = data['type'];

          if (type == 'partial') {
            onPartialText?.call(data['text']);
          } else if (type == 'final') {
            onFinalText?.call(data['text']);
          } else if (type == 'audio') {
            final audioBytes = base64Decode(data['audio']);
            _playAudioResponse(audioBytes);
            onAudioChunk?.call(audioBytes);
          }
        } else if (message is List<int>) {
          _playAudioResponse(message);
        }
      }, onError: (error) {
        _isConnected = false;
        onError?.call(error.toString());
      });
    } catch (e) {
      onError?.call(e.toString());
    }
  }

  // ============================================================
  // INITIALIZE RECORDER
  // ============================================================

  Future<bool> _initRecorder() async {
    if (_recorderInitialized) return true;

    try {
      // Request microphone permission
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        onError?.call('Microphone permission denied');
        return false;
      }

      await _recorder.openRecorder();
      _recorderInitialized = true;
      return true;
    } catch (e) {
      onError?.call('Recorder init error: $e');
      return false;
    }
  }

  // ============================================================
  // START RECORDING
  // ============================================================

  Future<void> startRecording() async {
    if (!_isConnected) {
      onError?.call('Not connected to server');
      return;
    }

    final initialized = await _initRecorder();
    if (!initialized) return;

    try {
      _isRecording = true;
      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/ollie_recording.aac';

      await _recorder.startRecorder(
        toFile: path,
        codec: Codec.aacADTS,
        sampleRate: 16000,
        numChannels: 1,
      );

      // Send chunks every 500ms
      _streamAudioChunks(path);
    } catch (e) {
      _isRecording = false;
      onError?.call('Recording error: $e');
    }
  }

  // ============================================================
  // STREAM AUDIO CHUNKS TO SERVER
  // ============================================================

  Future<void> _streamAudioChunks(String path) async {
    int lastSize = 0;

    while (_isRecording) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!_isRecording) break;

      try {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.length > lastSize) {
            final newBytes = bytes.sublist(lastSize);
            lastSize = bytes.length;
            _sendAudioChunk(newBytes);
          }
        }
      } catch (e) {
        // Keep going even if one chunk fails
      }
    }
  }

  // ============================================================
  // SEND AUDIO CHUNK
  // ============================================================

  void _sendAudioChunk(Uint8List bytes) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(bytes);
    }
  }

  // ============================================================
  // STOP RECORDING
  // ============================================================

  Future<void> stopRecording() async {
    _isRecording = false;
    try {
      await _recorder.stopRecorder();
    } catch (e) {
      // ignore
    }
    // Tell server user finished speaking
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode({'type': 'end'}));
    }
  }

  // ============================================================
  // PLAY AUDIO RESPONSE
  // ============================================================

  Future<void> _playAudioResponse(List<int> audioBytes) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File(
        
        '${tempDir.path}/ollie_response_${DateTime.now().millisecondsSinceEpoch}.mp3',
      );
      await file.writeAsBytes(audioBytes);
      await _audioPlayer.play(DeviceFileSource(file.path));
    } catch (e) {
      onError?.call('Error playing audio: $e');
    }
  }

  // ============================================================
  // DISCONNECT & DISPOSE
  // ============================================================

  void disconnect() {
    _isRecording = false;
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
  }

  Future<void> dispose() async {
    disconnect();
    if (_recorderInitialized) {
      await _recorder.closeRecorder();
      _recorderInitialized = false;
    }
    await _audioPlayer.dispose();
  }
}