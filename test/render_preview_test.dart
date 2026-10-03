import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moonveil/main.dart';
import 'package:moonveil/game/engine.dart';
import 'package:moonveil/game/roles.dart';
import 'package:moonveil/services/audio_director.dart';
import 'package:moonveil/ui/game_screen.dart';
import 'package:moonveil/ui/hero_selector.dart';
import 'package:moonveil/ui/cinematic_overlay.dart';
import 'package:moonveil/game/cinematic_event.dart';

void main() {
  testWidgets('render actual Flutter desktop, mobile and game previews', (
    tester,
  ) async {
    final loader = FontLoader('NotoSerifSC')
      ..addFont(rootBundle.load('assets/fonts/NotoSerifSC.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    SharedPreferences.setMockInitialValues({});
    final boundary = GlobalKey();
    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        final ctx = boundary.currentContext!;
        for (final asset in [
          'assets/images/village.png',
          'assets/images/hero-figures.png',
          ...Role.values.map((r) => r.asset),
        ]) {
          await precacheImage(AssetImage(asset), ctx);
        }
        await CinematicOverlay.preload();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = File('output/screenshots/$name.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1360, 920);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final audio = AudioDirector(silent: true);
    Widget wrap(Widget child) => RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF0A1016),
          textTheme: ThemeData.dark().textTheme.apply(
            fontFamily: 'NotoSerifSC',
          ),
        ),
        home: child,
      ),
    );
    await tester.pumpWidget(wrap(GameShell(audio: audio)));
    await tester.pumpAndSettle();
    await capture('home-desktop');
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await capture('home-mobile');
    await tester.tap(find.text('踏入月夜'));
    await tester.pumpAndSettle();
    await capture('lobby-mobile');
    await tester.ensureVisible(find.byType(HeroSelector));
    await tester.pumpAndSettle();
    await capture('heroes-mobile');
    tester.view.physicalSize = const Size(1360, 920);
    await tester.pumpAndSettle();
    await capture('lobby-desktop');
    await tester.ensureVisible(find.byType(HeroSelector));
    await tester.pumpAndSettle();
    await capture('heroes-desktop');
    final g = GameEngine.create(preferred: Role.seer, seed: 11);
    g.continueFlow();
    g.continueFlow();
    final gameAudio = AudioDirector(silent: true);
    await tester.pumpWidget(
      wrap(
        GameScreen(
          game: g,
          audio: gameAudio,
          onLeave: () async {},
          onSettings: () {},
          onRestart: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture('game-desktop');
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await capture('game-mobile');
    g.relationship(2)!.change(-12, '你在第 1 天投了我', 1);
    g.relationship(3)!.change(5, '第 1 天我们同投 4 号', 1);
    g.day = 2;
    g.phase = Phase.dawn;
    g.continueFlow();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('村庄关系'));
    await tester.tap(find.byTooltip('村庄关系'));
    await tester.pumpAndSettle();
    await capture('relationships-mobile');
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    g.phase = Phase.dawn;
    g.lastDeaths = [1, 7];
    g.player(1).alive = false;
    g.player(7).alive = false;
    g.nightResultPending = true;
    await tester.pumpWidget(
      wrap(
        GameScreen(
          key: const ValueKey('dawn-preview'),
          game: g,
          audio: gameAudio,
          onLeave: () async {},
          onSettings: () {},
          onRestart: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture('dawn-mobile');
    tester.view.physicalSize = const Size(1360, 920);
    await tester.pumpAndSettle();
    await capture('dawn-desktop');
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    await capture('dawn-landscape');
    for (final size in [
      const Size(390, 844),
      const Size(1360, 900),
      const Size(844, 390),
    ]) {
      tester.view.physicalSize = size;
      for (final kind in [
        CinematicKind.wolfAttack,
        CinematicKind.hunterShot,
        CinematicKind.guard,
        CinematicKind.goodWin,
        CinematicKind.out,
      ]) {
        await tester.pumpWidget(
          wrap(
            CinematicOverlay(
              key: ValueKey('$kind-$size'),
              event: CinematicEvent(
                kind,
                targetRole: Role.villager,
                actorRole: Role.guard,
                targetId: 7,
                targetName: '暮山',
              ),
              audio: gameAudio,
              onComplete: () {},
              previewProgress: kind == CinematicKind.out ? .38 : .55,
            ),
          ),
        );
        await capture('scene-${kind.name}-${size.width.toInt()}');
        expect(tester.takeException(), isNull);
      }
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    g.dispose();
    gameAudio.dispose();
  });
}
