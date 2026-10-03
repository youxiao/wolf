import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonveil/game/roles.dart';
import 'package:moonveil/main.dart';
import 'package:moonveil/services/audio_director.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moonveil/ui/hero_selector.dart';
import 'package:moonveil/ui/kit.dart';

void main() {
  for (final size in [
    const Size(320, 700),
    const Size(390, 844),
    const Size(844, 390),
    const Size(568, 320),
    const Size(768, 1024),
    const Size(1024, 600),
    const Size(1360, 900),
    const Size(1440, 700),
    const Size(1920, 1080),
  ]) {
    testWidgets('complete portrait and reachable choices at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final loader = FontLoader(serif)
        ..addFont(rootBundle.load('assets/fonts/NotoSerifSC.ttf'));
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      Role? selected = Role.witch;
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: ink,
            textTheme: ThemeData.dark().textTheme.apply(fontFamily: serif),
          ),
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1280),
                    child: StatefulBuilder(
                      builder: (context, update) => HeroSelector(
                        selected: selected,
                        count: 12,
                        onSelect: (role) => update(() => selected = role),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        final context = boundary.currentContext!;
        for (final asset in [
          'assets/images/hero-figures.png',
          ...Role.values.map((r) => r.asset),
        ]) {
          await precacheImage(AssetImage(asset), context);
        }
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final image = tester.widget<Art>(
        find.byKey(const ValueKey('hero-preview-art')),
      );
      expect(image.fit, BoxFit.contain);
      final imageRect = tester.getRect(
        find.byKey(const ValueKey('hero-preview-art')),
      );
      final preview = tester.getRect(
        find.byKey(const ValueKey('hero-preview')),
      );
      expect(imageRect.width / imageRect.height, closeTo(2 / 3, .001));
      expect(imageRect.left, greaterThanOrEqualTo(preview.left));
      expect(imageRect.right, lessThanOrEqualTo(preview.right));
      expect(imageRect.top, greaterThanOrEqualTo(preview.top));
      expect(imageRect.bottom, lessThanOrEqualTo(preview.bottom));
      expect(preview.bottom, lessThan(size.height));

      if (find.byKey(const ValueKey('hero-role-strip')).evaluate().isEmpty) {
        final rectangles = [
          for (final role in Role.values)
            tester.getRect(find.byKey(ValueKey('hero-${role.name}'))),
        ];
        for (var i = 0; i < rectangles.length; i++) {
          expect(rectangles[i].overlaps(preview), isFalse);
          expect(rectangles[i].left, greaterThanOrEqualTo(0));
          expect(rectangles[i].right, lessThanOrEqualTo(size.width));
          for (var j = i + 1; j < rectangles.length; j++) {
            expect(rectangles[i].overlaps(rectangles[j]), isFalse);
          }
        }
      }

      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final picture = await render.toImage(pixelRatio: 1);
        final data = await picture.toByteData(format: ui.ImageByteFormat.png);
        final output = File(
          'output/screenshots/selector-${size.width.toInt()}x${size.height.toInt()}.png',
        );
        await output.parent.create(recursive: true);
        await output.writeAsBytes(data!.buffer.asUint8List());
        picture.dispose();
      });

      for (final role in Role.values) {
        final choice = find.byKey(ValueKey('hero-${role.name}'));
        await tester.ensureVisible(choice);
        await tester.pumpAndSettle();
        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(selected, role);
        expect(
          tester
              .widget<Art>(find.byKey(const ValueKey('hero-preview-art')))
              .path,
          role.asset,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.ensureVisible(find.byKey(const ValueKey('hero-random')));
      await tester.tap(find.byKey(const ValueKey('hero-random')));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(find.byKey(const ValueKey('hero-preview-art')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'lobby keeps the complete preview visible through rotation and roster changes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final loader = FontLoader(serif)
        ..addFont(rootBundle.load('assets/fonts/NotoSerifSC.ttf'));
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
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
            child: GameShell(audio: AudioDirector(silent: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('踏入月夜'));
      await tester.tap(find.text('踏入月夜'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('12 人守卫局'));
      await tester.tap(find.text('12 人守卫局'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('hero-witch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hero-witch')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final context = boundary.currentContext!;
        for (final asset in [
          'assets/images/village.png',
          'assets/images/hero-figures.png',
          ...Role.values.map((r) => r.asset),
        ]) {
          await precacheImage(AssetImage(asset), context);
        }
      });
      for (final size in [
        const Size(320, 700),
        const Size(390, 844),
        const Size(568, 320),
        const Size(844, 390),
        const Size(768, 1024),
        const Size(1024, 600),
        const Size(1360, 900),
        const Size(1440, 700),
        const Size(1920, 1080),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(HeroSelector));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$size');
        final preview = tester.getRect(
          find.byKey(const ValueKey('hero-preview')),
        );
        expect(preview.top, greaterThanOrEqualTo(72), reason: '$size');
        expect(preview.bottom, lessThanOrEqualTo(size.height), reason: '$size');
        expect(
          tester
              .widget<Art>(find.byKey(const ValueKey('hero-preview-art')))
              .path,
          Role.witch.asset,
        );
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final picture = await render.toImage(pixelRatio: 1);
          final data = await picture.toByteData(format: ui.ImageByteFormat.png);
          final output = File(
            'output/screenshots/lobby-selector-${size.width.toInt()}x${size.height.toInt()}.png',
          );
          await output.parent.create(recursive: true);
          await output.writeAsBytes(data!.buffer.asUint8List());
          picture.dispose();
        });
      }
      await tester.ensureVisible(find.byKey(const ValueKey('hero-guard')));
      await tester.tap(find.byKey(const ValueKey('hero-guard')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('9 人经典局'));
      await tester.tap(find.text('9 人经典局'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('hero-guard')), findsNothing);
      expect(find.byKey(const ValueKey('hero-preview-art')), findsNothing);
      await tester.ensureVisible(find.text('围炉聚会'));
      await tester.tap(find.text('围炉聚会'));
      await tester.pumpAndSettle();
      expect(find.byType(HeroSelector), findsNothing);
      await tester.tap(find.text('单人历练'));
      await tester.pumpAndSettle();
      expect(find.byType(HeroSelector), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
