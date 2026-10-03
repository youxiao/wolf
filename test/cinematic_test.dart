import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonveil/game/cinematic_event.dart';
import 'package:moonveil/game/engine.dart';
import 'package:moonveil/game/roles.dart';
import 'package:moonveil/services/audio_director.dart';
import 'package:moonveil/ui/cinematic_overlay.dart';

class EffectAudio extends AudioDirector {
  EffectAudio() : super(silent: true);
  final effects = <String>[];
  @override
  Future<void> effect(String key) async => effects.add(key);
}

void main() {
  test('action portraits reveal only already public identities', () {
    final g = GameEngine.create(preferred: Role.seer, seed: 3);
    final witch = g.players.firstWhere((p) => p.role == Role.witch);
    expect(CinematicEvent.visibleRole(g, witch), Role.villager);
    expect(CinematicEvent.visibleRole(g, g.me), Role.seer);
    g.checks[witch.id] = false; // Alignment is not an exact role disclosure.
    expect(CinematicEvent.visibleRole(g, witch), Role.villager);
    final hunter = g.players.firstWhere((p) => p.role == Role.hunter);
    g.addEvent('${hunter.id} 号亮出猎人身份。');
    expect(CinematicEvent.visibleRole(g, hunter), Role.hunter);
    g.phase = Phase.ended;
    expect(CinematicEvent.visibleRole(g, witch), Role.witch);
    g.dispose();
  });
  test(
    'tabletop private potions and guarding cannot reveal choices by sound',
    () {
      final g = GameEngine.create(local: true, seed: 4);
      for (final kind in [
        CinematicKind.guard,
        CinematicKind.heal,
        CinematicKind.poison,
      ]) {
        final e = CinematicEvent.forTarget(kind, g, g.player(2));
        expect(e.muteEffect, true);
        expect(e.targetRole, Role.villager);
      }
      final attack = CinematicEvent.forTarget(
        CinematicKind.wolfAttack,
        g,
        g.player(2),
      );
      expect(attack.subtitle, contains('目标已锁定'));
      expect(
        attack.subtitle,
        isNot(contains('出局')),
      ); // Guard/save may still work.
      g.dispose();
    },
  );
  testWidgets('gunshot fires once at impact and completes its scene', (
    tester,
  ) async {
    await tester.runAsync(CinematicOverlay.preload);
    final audio = EffectAudio();
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CinematicOverlay(
          event: const CinematicEvent(
            CinematicKind.hunterShot,
            targetId: 2,
            targetName: '林间客',
          ),
          audio: audio,
          onComplete: () => finished++,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    expect(audio.effects, isEmpty);
    await tester.pump(const Duration(milliseconds: 1400));
    expect(audio.effects, ['gunshot']);
    await tester.pump(const Duration(milliseconds: 500));
    expect(audio.effects, ['gunshot']);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(finished, 1);
    await tester.pumpWidget(const SizedBox());
    audio.dispose();
  });
  testWidgets(
    'reduced motion is short and skipping never applies a skill twice',
    (tester) async {
      await tester.runAsync(CinematicOverlay.preload);
      final audio = EffectAudio();
      var finished = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: CinematicOverlay(
              event: const CinematicEvent(
                CinematicKind.heal,
                muteEffect: true,
                targetId: 2,
              ),
              audio: audio,
              onComplete: () => finished++,
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(finished, 1);
      expect(audio.effects, isEmpty);
      await tester.tap(find.text('跳过演出'));
      expect(finished, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      audio.dispose();
    },
  );
}
