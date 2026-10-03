import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:moonveil/services/audio_director.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native plugin decodes and plays bundled Chinese narration and music',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text('月隐 · 音频检查'))),
        ),
      );
      final voice = AudioPlayer();
      final music = AudioPlayer();
      await voice.setSource(AssetSource('audio/seer.mp3'));
      final duration = await voice.getDuration();
      expect(duration, isNotNull);
      expect(duration!.inMilliseconds, greaterThan(2000));
      await voice.resume();
      expect(voice.state, PlayerState.playing);
      await voice.stop();
      for (final key in [
        'dawn',
        'night_done',
        'guard_close',
        'wolves_close',
        'seer_close',
        'witch_close',
        'deaths_intro',
        'deaths_outro',
        for (int i = 1; i <= 12; i++) 'seat_$i',
      ]) {
        debugPrint('Decode announcement asset: $key');
        await voice.setSource(AssetSource('audio/$key.mp3'));
        expect(
          (await voice.getDuration())!.inMilliseconds,
          greaterThan(100),
          reason: '$key should decode on the native audio plugin',
        );
      }
      await music.setReleaseMode(ReleaseMode.loop);
      await music.setVolume(.1);
      await music.play(AssetSource('audio/ambience.mp3'));
      expect(music.state, PlayerState.playing);
      final ambience = await music.getDuration();
      expect(ambience!.inSeconds, greaterThanOrEqualTo(39));
      await music.stop();
      for (final effect in [
        'gunshot',
        'bite',
        'shield',
        'heal',
        'poison',
        'reveal',
        'out',
        'victory',
        'defeat',
      ]) {
        await voice.setSource(AssetSource('audio/fx_$effect.wav'));
        expect((await voice.getDuration())!.inMilliseconds, greaterThan(900));
      }
      await voice.dispose();
      await music.dispose();
      final director = AudioDirector();
      await director.load();
      director.voiceEnabled = true;
      director.voiceVolume = .2;
      await tester.runAsync(() async {
        debugPrint('Play sequential dawn announcement');
        await director.narrateDawn([1, 7]);
        expect(director.error, isNull);
        await director.effect('gunshot');
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        await director.stopEffect();
        debugPrint('Verify narration cancellation');
        final interrupted = director.narrateDawn([2, 12]);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await director.stopVoice();
        await interrupted.timeout(const Duration(seconds: 3));
        expect(director.error, isNull);
        debugPrint('Verify rapid phase changes and replay');
        final first = director.narrate('guard');
        final second = director.narrate('wolves');
        final last = director.narrate('dawn');
        await Future.wait([first, second, last]);
        await director.narrate('dawn');
        expect(director.error, isNull);
      });
      director.dispose();
    },
  );
}
