import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioDirector extends ChangeNotifier {
  final bool silent;
  AudioDirector({this.silent = false});
  AudioPlayer? _musicPlayer;
  AudioPlayer? _voicePlayer;
  AudioPlayer? _effectPlayer;
  AudioPlayer get _music => _musicPlayer ??= AudioPlayer();
  AudioPlayer get _voice => _voicePlayer ??= AudioPlayer();
  bool musicEnabled = true;
  bool voiceEnabled = true;
  bool effectsEnabled = true;
  double musicVolume = .35;
  double voiceVolume = .85;
  bool _started = false;
  int _voiceToken = 0;
  Future<void> _voiceWork = Future<void>.value();
  String? error;
  String? _activeNarrationKey;
  Map<String, String>? _narrationTexts;
  String? get activeNarrationKey => _activeNarrationKey;
  String? get activeNarrationText => _narrationTexts?[_activeNarrationKey];
  void _setNarrationKey(String? key) {
    if (_activeNarrationKey == key) return;
    _activeNarrationKey = key;
    notifyListeners();
  }

  Completer<void>? _voiceCancelled;
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    musicEnabled = prefs.getBool('music') ?? true;
    voiceEnabled = prefs.getBool('voice') ?? true;
    effectsEnabled = prefs.getBool('effects') ?? true;
    musicVolume = prefs.getDouble('musicVolume') ?? .35;
    voiceVolume = prefs.getDouble('voiceVolume') ?? .85;
    notifyListeners();
  }

  Future<void> start() async {
    if (silent || _started) return;
    _started = true;
    try {
      await _music.setReleaseMode(ReleaseMode.loop);
      await _music.setVolume(musicVolume);
      if (musicEnabled) await _music.play(AssetSource('audio/ambience.mp3'));
    } catch (_) {
      error = '声音暂时无法播放，请检查设备音频设置。';
      notifyListeners();
    }
  }

  Future<void> narrate(String key) => narrateSequence([key]);

  Future<void> effect(String key) async {
    if (silent || !effectsEnabled) return;
    try {
      final player = _effectPlayer ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.stop);
      await player.pause();
      await player.setVolume(.65);
      await player.play(AssetSource('audio/fx_$key.wav'));
    } catch (_) {
      // A missed effect must never block the action or expose private state.
    }
  }

  Future<void> stopEffect() async {
    try {
      await _effectPlayer?.stop();
    } catch (_) {}
  }

  Future<void> narrateDawn(List<int> deaths) => narrateSequence([
    'dawn',
    if (deaths.isEmpty)
      'peace'
    else ...[
      'deaths_intro',
      for (final id in deaths) 'seat_$id',
      'deaths_outro',
    ],
  ]);

  Future<void> narrateSequence(List<String> keys) async {
    if (silent || !voiceEnabled) return;
    _voiceCancelled?.complete();
    final cancelled = Completer<void>();
    _voiceCancelled = cancelled;
    final token = ++_voiceToken;
    _setNarrationKey(null);
    await _serializeVoice(() async {
      if (token != _voiceToken || !voiceEnabled) return;
      try {
        if (_narrationTexts == null) {
          try {
            final decoded = jsonDecode(
              await rootBundle.loadString('assets/audio/transcripts.json'),
            ) as Map<String, dynamic>;
            _narrationTexts = decoded.map(
              (key, value) => MapEntry(key, value.toString()),
            );
          } catch (_) {
            // Missing display text must not prevent the recording from playing.
            _narrationTexts = {};
          }
        }
        if (token != _voiceToken || !voiceEnabled) return;
        await _voice.setReleaseMode(ReleaseMode.stop);
        await _voice.pause();
        if (token != _voiceToken || !voiceEnabled) return;
        await _music.setVolume(musicVolume * .28);
        await _voice.setVolume(voiceVolume);
        for (final key in keys) {
          if (token != _voiceToken || !voiceEnabled) return;
          final done = Completer<void>();
          final completion = _voice.onPlayerComplete.listen((_) {
            if (!done.isCompleted) done.complete();
          });
          try {
            await _voice.setSource(AssetSource('audio/$key.mp3'));
            if (token != _voiceToken || !voiceEnabled) return;
            await _voice.seek(Duration.zero);
            if (token != _voiceToken || !voiceEnabled) return;
            await _voice.resume();
            if (token == _voiceToken) _setNarrationKey(key);
            await Future.any([done.future, cancelled.future])
                .timeout(const Duration(seconds: 60));
          } finally {
            await completion.cancel();
            if (token == _voiceToken) _setNarrationKey(null);
          }
        }
      } catch (e) {
        if (token != _voiceToken) return;
        debugPrint('Moonveil narration error: $e');
        error = '中文主持音频播放失败，可在设置中重试。';
        notifyListeners();
      } finally {
        if (token == _voiceToken) {
          _setNarrationKey(null);
          _voiceCancelled = null;
          try {
            await _music.setVolume(musicVolume);
          } catch (_) {
            // A disconnected audio device must not interrupt game progression.
          }
        }
      }
    });
  }

  // Serializing native source preparation prevents rapid phase changes from
  // invalidating an AVPlayer item's pending preparation callback.
  Future<void> _serializeVoice(Future<void> Function() operation) {
    final next = _voiceWork.then((_) => operation());
    _voiceWork = next.catchError((Object _) {});
    return next;
  }

  Future<void> stopVoice() async {
    if (silent) return;
    final token = ++_voiceToken;
    _setNarrationKey(null);
    _voiceCancelled?.complete();
    _voiceCancelled = null;
    await _serializeVoice(() async {
      if (token != _voiceToken) return;
      try {
        await _voice.pause();
        await _music.setVolume(musicVolume);
      } catch (_) {
        // An unavailable audio device must not block gameplay.
      }
    });
  }

  Future<void> update({
    bool? music,
    bool? voice,
    bool? effects,
    double? musicLevel,
    double? voiceLevel,
  }) async {
    musicEnabled = music ?? musicEnabled;
    voiceEnabled = voice ?? voiceEnabled;
    effectsEnabled = effects ?? effectsEnabled;
    musicVolume = musicLevel ?? musicVolume;
    voiceVolume = voiceLevel ?? voiceVolume;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('music', musicEnabled);
    await prefs.setBool('voice', voiceEnabled);
    await prefs.setBool('effects', effectsEnabled);
    await prefs.setDouble('musicVolume', musicVolume);
    await prefs.setDouble('voiceVolume', voiceVolume);
    if (silent) return;
    try {
      await _music.setVolume(musicVolume);
      await _voice.setVolume(voiceVolume);
      if (musicEnabled) {
        if (_started && music == true) {
          await _music.play(AssetSource('audio/ambience.mp3'));
        }
      } else {
        await _music.pause();
      }
      if (!voiceEnabled) await stopVoice();
      if (!effectsEnabled) await stopEffect();
    } catch (_) {
      error = '音频设备暂时不可用。';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _voiceCancelled?.complete();
    _voiceCancelled = null;
    _voiceToken++;
    _musicPlayer?.dispose();
    _voicePlayer?.dispose();
    _effectPlayer?.dispose();
    super.dispose();
  }
}
