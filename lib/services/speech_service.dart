import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

class SpeechService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isInitialized = false;
  String? get _apiKey => dotenv.env['ELEVEN_LABS_API_KEY'];
  static const String _baseUrl = 'https://api.elevenlabs.io/v1';
  static const String _defaultVoiceId =
      'IKne3meq5aSn9XLyUdCD'; // Meditation Lady voice
  File? _currentAudioFile;
  String? _selectedModelId;
  final Map<String, String> _audioCache = {};
  VoidCallback? _onPlaybackComplete;

  Future<void> initialize() async {
    if (!_isInitialized) {
      if (_apiKey == null) {
        throw Exception(
            'ELEVEN_LABS_API_KEY not found in environment variables');
      }
      await _fetchAvailableModels();
      await _initializeCache();

      _audioPlayer.processingStateStream.listen((state) {
        if (state == ProcessingState.completed) {
          print('Audio playback completed naturally');
          _onPlaybackComplete?.call();
        }
      });

      _isInitialized = true;
    }
  }

  Future<void> _initializeCache() async {
    final cacheDir = await _getCacheDirectory();
    if (await cacheDir.exists()) {
      final files = await cacheDir.list().toList();
      for (var file in files) {
        if (file is File && file.path.endsWith('.mp3')) {
          final hash = file.path.split('/').last.replaceAll('.mp3', '');
          _audioCache[hash] = file.path;
        }
      }
    }
  }

  Future<Directory> _getCacheDirectory() async {
    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory('${tempDir.path}/audio_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  String _generateHash(String text) {
    return md5.convert(utf8.encode(text)).toString();
  }

  Future<String?> _getCachedAudioPath(String text) async {
    final hash = _generateHash(text);
    return _audioCache[hash];
  }

  Future<void> _cacheAudio(String text, List<int> audioBytes) async {
    final hash = _generateHash(text);
    final cacheDir = await _getCacheDirectory();
    final audioFile = File('${cacheDir.path}/$hash.mp3');
    await audioFile.writeAsBytes(audioBytes);
    _audioCache[hash] = audioFile.path;
  }

  Future<void> _fetchAvailableModels() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/models'),
        headers: {
          'xi-api-key': _apiKey!,
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final models = json.decode(response.body);
        if (models is List && models.isNotEmpty) {
          _selectedModelId = models[0]['model_id'];
          print('Selected model: $_selectedModelId');
        }
      } else {
        print('Failed to fetch models: ${response.body}');
        _selectedModelId = 'eleven_multilingual_v2';
      }
    } catch (e) {
      print('Error fetching models: $e');
      _selectedModelId = 'eleven_multilingual_v2';
    }
  }

  Future<void> speak(String text, {String? preGeneratedMp3Url}) async {
    try {
      await initialize();

      if (preGeneratedMp3Url != null && preGeneratedMp3Url.isNotEmpty) {
        print('Using pre-generated MP3 URL: $preGeneratedMp3Url');
        await _audioPlayer.setUrl(preGeneratedMp3Url);
        await _audioPlayer.play();
        return;
      }

      final cachedPath = await _getCachedAudioPath(text);
      if (cachedPath != null) {
        print('Using cached audio file: $cachedPath');
        await _audioPlayer.setFilePath(cachedPath);
        await _audioPlayer.play();
        return;
      }

      if (_selectedModelId == null) {
        throw Exception('No text-to-speech model available');
      }

      print('Generating new audio from Eleven Labs API');
      final url = Uri.parse('$_baseUrl/text-to-speech/$_defaultVoiceId');
      final response = await http.post(
        url,
        headers: {
          'xi-api-key': _apiKey!,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'text': text,
          'model_id': _selectedModelId,
          'voice_settings': {
            'stability': 0.5,
            'similarity_boost': 0.75,
            'style': 0.0,
            'use_speaker_boost': true
          }
        }),
      );

      if (response.statusCode != 200) {
        print('API Response: ${response.body}');
        throw Exception('Failed to generate speech: ${response.body}');
      }

      await _cacheAudio(text, response.bodyBytes);

      final audioPath = await _getCachedAudioPath(text);
      if (audioPath == null) {
        throw Exception('Failed to cache audio file');
      }

      await _audioPlayer.setFilePath(audioPath);
      await _audioPlayer.play();
    } catch (e) {
      print('Error in speak: $e');
      rethrow;
    }
  }

  Future<void> stop() async {
    await _audioPlayer.stop();
  }

  Future<void> pause() async {
    await _audioPlayer.pause();
  }

  Future<void> resume() async {
    await _audioPlayer.play();
  }

  Future<void> dispose() async {
    await stop();
    await _audioPlayer.dispose();
  }

  bool get isPlaying => _audioPlayer.playing;

  set onPlaybackComplete(VoidCallback? callback) {
    _onPlaybackComplete = callback;
  }
}
