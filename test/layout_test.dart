import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moonveil/main.dart';
import 'package:moonveil/game/engine.dart';
import 'package:moonveil/game/roles.dart';
import 'package:moonveil/services/audio_director.dart';
import 'package:moonveil/ui/game_screen.dart';

void main() {
  for (final size in [
    const Size(320, 700),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1360, 900),
  ]) {
    testWidgets('home and lobby fit ${size.width}x${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: GameShell(audio: AudioDirector(silent: true)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('踏入月夜'));
      await tester.tap(find.text('踏入月夜'));
      await tester.pumpAndSettle();
      expect(find.text('02  选择村庄'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
  for (final size in [
    const Size(320, 700),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1360, 900),
  ]) {
    testWidgets('board and controls fit ${size.width}x${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final g = GameEngine.create(preferred: Role.seer, seed: 7);
      g.continueFlow();
      g.continueFlow();
      final audio = AudioDirector(silent: true);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: GameScreen(
            game: g,
            audio: audio,
            onLeave: () async {},
            onSettings: () {},
            onRestart: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      g.dispose();
      audio.dispose();
    });
  }
  testWidgets('tabletop identity is sealed, and hidden again for next player', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final g = GameEngine.create(count: 9, local: true, seed: 3);
    final audio = AudioDirector(silent: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: GameScreen(
          game: g,
          audio: audio,
          onLeave: () async {},
          onSettings: () {},
          onRestart: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('独自查看'), findsOneWidget);
    expect(find.text(g.players.first.role.title), findsNothing);
    await tester.tap(find.text('独自查看'));
    await tester.pumpAndSettle();
    expect(find.text(g.players.first.role.title), findsOneWidget);
    await tester.ensureVisible(find.text('隐藏身份 · 传给下一位'));
    await tester.tap(find.text('隐藏身份 · 传给下一位'));
    await tester.pumpAndSettle();
    expect(find.text('独自查看'), findsOneWidget);
    expect(g.dealIndex, 1);
    expect(find.text(g.players[1].role.title), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    g.dispose();
    audio.dispose();
  });
}
