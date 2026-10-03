import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonveil/game/engine.dart';
import 'package:moonveil/game/roles.dart';
import 'package:moonveil/services/audio_director.dart';
import 'package:moonveil/ui/game_screen.dart';

class RecordingAudio extends AudioDirector {
  RecordingAudio() : super(silent: true);
  final List<List<String>> narration = [];
  @override
  Future<void> narrateSequence(List<String> keys) async {
    narration.add(List.of(keys));
  }
}

Future<void> showGame(
  WidgetTester tester,
  GameEngine game,
  RecordingAudio audio,
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: GameScreen(
        game: game,
        audio: audio,
        onLeave: () async {},
        onSettings: () {},
        onRestart: () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
  await skipCinematics(tester);
  expect(tester.takeException(), isNull);
}

Future<void> skipCinematics(WidgetTester tester) async {
  for (var i = 0; i < 12 && find.text('跳过演出').evaluate().isNotEmpty; i++) {
    await tester.tap(find.text('跳过演出'));
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final size in [const Size(320, 700), const Size(390, 844)]) {
    testWidgets(
      'social profiles show score, temperament and actual vote memory at $size',
      (tester) async {
        final g = GameEngine.create(seed: 7);
        g.relationship(2)!.change(-12, '你在第 1 天投了我', 1);
        g.relationship(3)!.change(5, '第 1 天我们同投 4 号', 1);
        g.phase = Phase.dawn;
        g.continueFlow();
        final audio = RecordingAudio();
        await showGame(tester, g, audio, size);
        await tester.ensureVisible(find.byTooltip('村庄关系'));
        await tester.tap(find.byTooltip('村庄关系'));
        await tester.pumpAndSettle();
        expect(find.text('-12'), findsOneWidget);
        expect(find.text('+5'), findsOneWidget);
        expect(find.text('你在第 1 天投了我 · -12'), findsOneWidget);
        expect(find.text('第 1 天我们同投 4 号 · +5'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        g.dispose();
        audio.dispose();
      },
    );
  }
  for (final size in [
    const Size(320, 700),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1360, 900),
  ]) {
    testWidgets('dead solo player has read-only ballots at $size', (
      tester,
    ) async {
      final g = GameEngine.create(preferred: Role.villager, seed: 4);
      g.me.alive = false;
      g.phase = Phase.vote;
      final audio = RecordingAudio();
      await showGame(tester, g, audio, size);
      expect(find.text('弃票'), findsNothing);
      expect(find.text('确认投票'), findsNothing);
      expect(find.text('确认放逐投票'), findsNothing);
      final seat = find.text(g.player(2).name);
      await tester.ensureVisible(seat);
      await tester.tap(seat, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.textContaining('已选择'), findsNothing);
      expect(g.votes, isEmpty);
      await tap(tester, '查看投票结果');
      expect(g.votes.containsKey(g.me.id), false);
      await tester.pumpWidget(const SizedBox());
      g.dispose();
      audio.dispose();
    });

    for (final deaths in [
      <int>[],
      <int>[1, 7],
    ]) {
      testWidgets('dawn announces $deaths in the center at $size', (
        tester,
      ) async {
        final g = GameEngine.create(seed: 7);
        g.phase = Phase.dawn;
        g.nightResultPending = true;
        g.lastDeaths = deaths;
        for (final id in deaths) {
          g.player(id).alive = false;
        }
        final audio = RecordingAudio();
        await showGame(tester, g, audio, size);
        final announcement = find.byKey(const ValueKey('night-result'));
        expect(announcement, findsOneWidget);
        final center = tester.getCenter(announcement);
        expect(center.dx, closeTo(size.width / 2, 1));
        expect(center.dy, closeTo((size.height + 72) / 2, 40));
        if (deaths.isEmpty) {
          expect(find.text('昨夜平安夜'), findsOneWidget);
          expect(audio.narration.last, ['dawn', 'peace']);
        } else {
          final number = tester.widget<Text>(find.text('7 号'));
          expect(
            number.style!.fontSize,
            greaterThanOrEqualTo(size.height < 600 ? 36 : 42),
          );
          expect(audio.narration.last, [
            'dawn',
            'deaths_intro',
            'seat_1',
            'seat_7',
            'deaths_outro',
          ]);
        }
        expect(find.text(g.player(2).name), findsNothing);
        await tap(tester, '开始白天发言');
        expect(g.phase, Phase.discussion);
        expect(g.nightResultPending, false);
        expect(announcement, findsNothing);
        await tester.pumpWidget(const SizedBox());
        g.dispose();
        audio.dispose();
      });
    }
  }

  testWidgets(
    'local seer must acknowledge private result before witch opens eyes',
    (tester) async {
      final g = GameEngine.create(local: true, seed: 8);
      while (g.phase == Phase.deal) {
        g.continueFlow();
      }
      g.continueFlow();
      g.act(null);
      g.confirmNightAction();
      g.act(g.targets.first.id);
      g.confirmNightAction();
      expect(g.phase, Phase.seer);
      final audio = RecordingAudio();
      await showGame(tester, g, audio, const Size(390, 844));
      await tap(tester, '独自查看');
      final checked = g.targets.first;
      await tap(tester, checked.name);
      await tap(tester, '查验身份');
      expect(g.phase, Phase.seer);
      expect(find.text('水晶中的真相 · 仅你可见'), findsOneWidget);
      expect(find.text(g.privateResult!), findsOneWidget);
      expect(find.text('女巫，请选择'), findsNothing);
      expect(audio.narration.last, ['night_done']);
      expect(audio.narration.any((keys) => keys.contains('witch')), false);
      await tap(tester, '确认行动完成 · 闭眼');
      expect(g.phase, Phase.witch);
      expect(g.privateResult, isNull);
      expect(find.text('独自查看'), findsOneWidget);
      expect(find.textContaining('今晚'), findsNothing);
      expect(audio.narration.last, ['witch']);
      await tester.pumpWidget(const SizedBox());
      g.dispose();
      audio.dispose();
    },
  );
}
