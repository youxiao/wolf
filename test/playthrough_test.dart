import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moonveil/main.dart';
import 'package:moonveil/game/engine.dart';
import 'package:moonveil/game/roles.dart';
import 'package:moonveil/services/audio_director.dart';
import 'package:moonveil/ui/game_screen.dart';

void main() {
  testWidgets(
    'portrait player can start, inspect, discuss, vote, save and resume',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final audio = AudioDirector(silent: true);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: GameShell(audio: audio),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(String label) async {
        final finder = label.startsWith('结束发言')
            ? find.byKey(const ValueKey('discussion-continue'))
            : find.text(label);
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
        for (
          var i = 0;
          i < 12 && find.text('跳过演出').evaluate().isNotEmpty;
          i++
        ) {
          await tester.tap(find.text('跳过演出'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      }

      await tap('踏入月夜');
      await tap('预言家');
      await tap('开启 12 人历练');
      var g = tester.widget<GameScreen>(find.byType(GameScreen)).game;
      expect(g.me.role, Role.seer);
      await tap('铭记使命 · 进入黑夜');
      await tap('进入夜间行动');
      expect(g.phase, Phase.seer);
      final inspected = g.targets.first;
      await tap(inspected.name);
      await tap('查验身份');
      expect(find.text('水晶中的真相 · 仅你可见'), findsOneWidget);
      await tap('我已记住');
      expect(g.checks.containsKey(inspected.id), true);
      await tap('开始白天发言');
      expect(g.phase, Phase.discussion);
      if (g.me.alive) await tap('谨慎观望');
      await tap(g.me.alive ? '结束发言 · 开始投票' : '结束发言 · 观看投票');
      expect(g.phase, Phase.vote);
      if (g.me.alive) {
        await tap(g.targets.first.name);
        await tap('确认投票');
      } else {
        await tap('查看投票结果');
      }
      expect(g.day, 2);
      expect(g.lastVote, isNotEmpty);
      await tester.tap(find.byTooltip('保存并返回'));
      await tester.pumpAndSettle();
      await tap('保存并返回');
      await tap('继续旅程');
      g = tester.widget<GameScreen>(find.byType(GameScreen)).game;
      expect(g.day, 2);
      expect(g.me.role, Role.seer);
      expect(g.checks.containsKey(inspected.id), true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
