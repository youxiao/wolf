import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonveil/game/engine.dart';
import 'package:moonveil/game/roles.dart';
import 'package:moonveil/services/audio_director.dart';
import 'package:moonveil/ui/game_screen.dart';
import 'package:moonveil/ui/kit.dart';

class DiscussionAudio extends AudioDirector {
  DiscussionAudio() : super(silent: true);
  String? playing;
  @override
  String? get activeNarrationKey => playing;
  @override
  String? get activeNarrationText =>
      playing == 'discussion' ? '现在开始白天发言。请倾听，也请谨慎判断。' : null;
  @override
  Future<void> narrate(String key) async {}
  void broadcast(String? key) {
    playing = key;
    notifyListeners();
  }
}

Future<void> fonts() async {
  await (FontLoader(
    serif,
  )..addFont(rootBundle.load('assets/fonts/NotoSerifSC.ttf'))).load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(320, 700),
    const Size(390, 844),
    const Size(568, 320),
    const Size(844, 390),
    const Size(768, 1024),
    const Size(1024, 600),
    const Size(1100, 500),
    const Size(1360, 900),
    const Size(1440, 700),
    const Size(1920, 1080),
  ]) {
    testWidgets(
      'reading, host narration and target selection share the viewport at $size',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await fonts();
        final g = GameEngine.create(preferred: Role.werewolf, seed: 7);
        g.phase = Phase.dawn;
        g.continueFlow();
        // Long statements must scroll inside the reader, rather than move seats.
        g.speeches[0] += ' 请结合公开发言与投票记录继续观察，每一个判断都需要线索。' * 8;
        final audio = DiscussionAudio();
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.dark,
              fontFamily: serif,
              scaffoldBackgroundColor: ink,
              colorScheme: const ColorScheme.dark(
                primary: gold,
                surface: panel,
                onSurface: cream,
              ),
            ),
            home: RepaintBoundary(
              key: boundary,
              child: GameScreen(
                game: g,
                audio: audio,
                onLeave: () async {},
                onSettings: () {},
                onRestart: () {},
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          final context = boundary.currentContext!;
          for (final path in [
            'assets/images/village.png',
            ...Role.values.map((r) => r.asset),
          ]) {
            await precacheImage(AssetImage(path), context);
          }
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final reader = find.byKey(const ValueKey('speech-focus-scroll'));
        final seats = find.byKey(const ValueKey('discussion-seats'));
        final initialSeats = tester.getRect(seats);
        final initialReader = tester.getRect(reader);
        final finish = find.byKey(const ValueKey('discussion-continue'));
        expect(initialSeats.top, greaterThanOrEqualTo(72));
        expect(initialSeats.bottom, lessThanOrEqualTo(size.height));
        expect(initialReader.top, greaterThanOrEqualTo(72));
        expect(initialReader.bottom, lessThanOrEqualTo(size.height));
        expect(tester.getRect(finish).bottom, lessThanOrEqualTo(size.height));
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('speech-focus-text')))
              .style!
              .fontSize,
          greaterThanOrEqualTo(16),
        );
        await tester.drag(reader, const Offset(0, -130));
        await tester.pumpAndSettle();
        expect(tester.getRect(seats), initialSeats);
        if (find
            .byKey(const ValueKey('speech-history'))
            .evaluate()
            .isNotEmpty) {
          await tester.drag(
            find.byKey(const ValueKey('speech-history')),
            const Offset(0, -100),
          );
          await tester.pumpAndSettle();
          expect(tester.getRect(seats), initialSeats);
        }
        audio.broadcast('discussion');
        await tester.pumpAndSettle();
        expect(find.text('主持播报'), findsOneWidget);
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('speech-focus-text')))
              .data,
          audio.activeNarrationText,
        );
        final target = find.byKey(const ValueKey('seat-12'));
        await tester.scrollUntilVisible(
          target,
          70,
          scrollable: find.descendant(
            of: seats,
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(find.text('指认 12 号'), findsOneWidget);
        expect(tester.getRect(seats), initialSeats);
        expect(tester.getRect(reader), initialReader);
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('speech-focus-text')))
              .data,
          audio.activeNarrationText,
        );

        Future<void> capture(String suffix) async {
          await tester.runAsync(() async {
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await render.toImage(pixelRatio: 1);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
              'output/screenshots/discussion$suffix-${size.width.toInt()}x${size.height.toInt()}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('');
        await tester.tap(find.byKey(const ValueKey('speech-next')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('speech-focus-text')))
              .data,
          g.speeches[1].split('：').last,
        );
        audio.broadcast(null);
        await tester.pumpAndSettle();
        expect(find.text('主持播报'), findsNothing);
        await capture('-reading');
        expect(tester.getRect(seats), initialSeats);
        await tester.tap(find.byKey(const ValueKey('discussion-submit')));
        await tester.pumpAndSettle();
        expect(g.speeches.first, contains('12 号'));
        expect(g.speeches.first, startsWith('1号 · 你'));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        g.dispose();
        audio.dispose();
      },
    );
  }
  testWidgets(
    'portrait seer can reveal checks and dead players remain observers',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final g = GameEngine.create(preferred: Role.seer, seed: 11);
      g.checks[3] = false;
      g.phase = Phase.dawn;
      g.continueFlow();
      final audio = DiscussionAudio();
      Future<void> show() => tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: GameScreen(
            key: ValueKey(g.me.alive),
            game: g,
            audio: audio,
            onLeave: () async {},
            onSettings: () {},
            onRestart: () {},
          ),
        ),
      );
      await show();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('更多发言方式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('公开我的查验'));
      await tester.pumpAndSettle();
      expect(g.speeches.first, contains('3号是好人'));
      g.me.alive = false;
      await show();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('seat-3')));
      await tester.pumpAndSettle();
      expect(find.text('指认 3 号'), findsNothing);
      expect(
        tester
            .widget<GameButton>(find.byKey(const ValueKey('discussion-submit')))
            .onTap,
        isNull,
      );
      expect(find.text('观看投票'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      g.dispose();
      audio.dispose();
    },
  );

  testWidgets(
    'resizing preserves the reading focus and chosen target; party discussion keeps roles private',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetPadding);
      final g = GameEngine.create(preferred: Role.werewolf, seed: 7);
      g.phase = Phase.dawn;
      g.continueFlow();
      final audio = DiscussionAudio();
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
      await tester.tap(find.byKey(const ValueKey('seat-3')));
      await tester.tap(find.byKey(const ValueKey('speech-next')));
      await tester.pumpAndSettle();
      final focused = tester
          .widget<Text>(find.byKey(const ValueKey('speech-focus-text')))
          .data;
      for (final size in [
        const Size(1360, 900),
        const Size(844, 390),
        const Size(768, 1024),
        const Size(320, 700),
        const Size(1920, 1080),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(find.text('指认 3 号'), findsOneWidget);
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('speech-focus-text')))
              .data,
          focused,
        );
        expect(tester.takeException(), isNull);
      }
      tester.view.physicalSize = const Size(390, 844);
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
      await tester.pumpAndSettle();
      expect(
        tester
            .getRect(find.byKey(const ValueKey('discussion-continue')))
            .bottom,
        lessThanOrEqualTo(810),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('speech-focus-scroll'))).top,
        greaterThanOrEqualTo(116),
      );
      expect(tester.takeException(), isNull);
      final party = GameEngine.create(local: true, seed: 7);
      party.phase = Phase.dawn;
      party.continueFlow();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: GameScreen(
            key: const ValueKey('party'),
            game: party,
            audio: audio,
            onLeave: () async {},
            onSettings: () {},
            onRestart: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('discussion-submit')), findsNothing);
      expect(find.text('狼人'), findsNothing);
      expect(find.byKey(const ValueKey('discussion-seats')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      party.dispose();
      g.dispose();
      audio.dispose();
    },
  );
}
