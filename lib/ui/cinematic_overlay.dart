import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/cinematic_event.dart';
import '../game/roles.dart';
import '../services/audio_director.dart';
import 'kit.dart';

class CinematicOverlay extends StatefulWidget {
  static Future<void> preload() async {
    await Future.wait([
      for (final path in [
        'assets/images/wolf-action.png',
        'assets/images/hunter-action.png',
        'assets/images/village.png',
        'assets/images/hero-figures.png',
        ...Role.values.map((r) => r.asset),
      ])
        _CinematicOverlayState.artwork(path),
    ]);
  }

  final CinematicEvent event;
  final AudioDirector audio;
  final VoidCallback onComplete;
  final double? previewProgress;
  const CinematicOverlay({
    super.key,
    required this.event,
    required this.audio,
    required this.onComplete,
    this.previewProgress,
  });
  @override
  State<CinematicOverlay> createState() => _CinematicOverlayState();
}

class _CinematicOverlayState extends State<CinematicOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  ui.Image? actor, target, village, figures;
  bool sounded = false, finished = false, reduced = false;
  static final Map<String, Future<ui.Image>> _art = {};

  static Future<ui.Image> artwork(String path) =>
      _art.putIfAbsent(path, () async {
        final data = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(),
          targetHeight: path.contains('action') ? 640 : 768,
        );
        final frame = await codec.getNextFrame();
        codec.dispose();
        return frame.image;
      });

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.event.ending ? 4400 : 2900),
    );
    controller.addListener(() {
      if (!sounded &&
          controller.value >= .42 &&
          widget.previewProgress == null) {
        sounded = true;
        if (!widget.event.muteEffect) widget.audio.effect(widget.event.effect);
      }
    });
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
    _load();
  }

  Future<void> _load() async {
    final e = widget.event;
    final actorPath = switch (e.kind) {
      CinematicKind.wolfAttack => 'assets/images/wolf-action.png',
      CinematicKind.hunterShot => 'assets/images/hunter-action.png',
      _ => e.actorRole.asset,
    };
    // Decode failures should leave a skippable effect, never hold up a turn.
    List<ui.Image>? pictures;
    try {
      pictures = await Future.wait([
        artwork(actorPath),
        artwork((e.targetRole ?? Role.villager).asset),
        artwork('assets/images/village.png'),
        artwork('assets/images/hero-figures.png'),
      ]);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      actor = pictures?[0];
      target = pictures?[1];
      village = pictures?[2];
      figures = pictures?[3];
    });
    if (widget.previewProgress != null) {
      controller.value = widget.previewProgress!;
    } else {
      reduced = MediaQuery.disableAnimationsOf(context);
      if (reduced) controller.duration = const Duration(milliseconds: 700);
      controller.forward();
    }
  }

  void _finish() {
    if (finished || !mounted || widget.previewProgress != null) return;
    finished = true;
    widget.audio.stopEffect();
    widget.onComplete();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlockSemantics(
    child: Material(
      color: ink,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final short = constraints.maxHeight < 450;
            return AnimatedBuilder(
              animation: controller,
              builder: (_, __) => Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ScenePainter(
                        widget.event,
                        reduced ? .55 : controller.value,
                        actor,
                        target,
                        village,
                        figures,
                        reduced,
                      ),
                    ),
                  ),
                  Positioned(
                    top: short ? 10 : 28,
                    left: 24,
                    right: 24,
                    child: Column(
                      children: [
                        Text(
                          widget.event.ending
                              ? 'THE FINAL CHAPTER'
                              : 'THE NIGHT MOVES',
                          style: caption(color: gold, size: 10),
                        ),
                        if (widget.event.targetName != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${widget.event.targetId} 号 · ${widget.event.targetName}',
                            style: const TextStyle(color: cream, fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: short ? 58 : 100,
                    left: 20,
                    right: 20,
                    child: Column(
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            widget.event.title,
                            style: heading(
                              short
                                  ? 32
                                  : constraints.maxWidth > 700
                                  ? 52
                                  : 36,
                              color: cream,
                              spacing: 7,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.event.subtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: gold,
                            fontSize: short ? 11 : 13,
                            letterSpacing: 2,
                            height: 1.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    right: 20,
                    child: GameButton(
                      '跳过演出',
                      onTap: _finish,
                      primary: false,
                      small: true,
                      icon: Icons.skip_next,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _ScenePainter extends CustomPainter {
  final CinematicEvent event;
  final double t;
  final ui.Image? actor, target, village, figures;
  final bool reduced;
  _ScenePainter(
    this.event,
    this.t,
    this.actor,
    this.target,
    this.village,
    this.figures,
    this.reduced,
  );
  double interval(double start, double end) =>
      ((t - start) / (end - start)).clamp(0, 1);
  double ease(double start, double end) =>
      Curves.easeInOutCubic.transform(interval(start, end));
  Color get accent => switch (event.kind) {
    CinematicKind.wolfAttack ||
    CinematicKind.out ||
    CinematicKind.wolfWin => const Color(0xFFCA665D),
    CinematicKind.heal || CinematicKind.guard => const Color(0xFF99D7BB),
    CinematicKind.poison => const Color(0xFFB59AD9),
    CinematicKind.reveal => const Color(0xFF99D0E6),
    _ => gold,
  };

  Rect image(
    Canvas c,
    ui.Image? img,
    Rect rect, {
    double alpha = 1,
    Rect? source,
  }) {
    if (img == null) return rect;
    final full =
        source ??
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final fit = applyBoxFit(
      source == null ? BoxFit.cover : BoxFit.contain,
      full.size,
      rect.size,
    );
    final src = Alignment.center.inscribe(fit.source, full);
    final dst = Alignment.center.inscribe(fit.destination, rect);
    c.drawImageRect(
      img,
      src,
      dst,
      Paint()
        ..color = Colors.white.withValues(alpha: alpha.clamp(0, 1))
        ..filterQuality = FilterQuality.medium,
    );
    return dst;
  }

  void portrait(Canvas c, ui.Image? img, Rect rect, {double alpha = 1}) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    c.save();
    c.clipRRect(rrect);
    image(c, img, rect, alpha: alpha);
    c.restore();
    c.drawRRect(
      rrect,
      Paint()
        ..color = accent.withValues(alpha: .45 * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void figurine(Canvas c, Role role, Rect rect, {double alpha = 1}) {
    if (figures == null) {
      portrait(c, target, rect, alpha: alpha);
      return;
    }
    final frame = role.figurineFrame;
    final scale = figures!.height / 1287;
    // In action scenes the character stands in the village, off the plinth.
    image(
      c,
      figures,
      rect,
      alpha: alpha,
      source: Rect.fromLTRB(
        frame.left * scale,
        frame.top * scale,
        frame.right * scale,
        (frame.bottom - 58) * scale,
      ),
    );
  }

  Rect sprite(Canvas c, ui.Image? img, Rect rect, int frame) {
    if (img == null) return rect;
    final cell = img.width / 3;
    final hunter = event.kind == CinematicKind.hunterShot;
    return image(
      c,
      img,
      rect,
      source: Rect.fromLTWH(
        frame * cell,
        img.height * (hunter ? .05 : .20),
        cell,
        img.height * (hunter ? .90 : .67),
      ),
    );
  }

  void glow(
    Canvas c,
    Offset center,
    double radius,
    Color color,
    double opacity,
  ) {
    c.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: opacity.clamp(0, 1)),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  void spark(Canvas c, Offset center, double radius, Color color) {
    final p = Path();
    for (int i = 0; i < 16; i++) {
      final a = math.pi * i / 8;
      final r = i.isEven ? radius : radius * .2;
      final point = center + Offset(math.cos(a), math.sin(a)) * r;
      if (i == 0) {
        p.moveTo(point.dx, point.dy);
      } else {
        p.lineTo(point.dx, point.dy);
      }
    }
    p.close();
    c.drawPath(p, Paint()..color = color);
  }

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    image(c, village, Offset.zero & s, alpha: .28);
    c.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [ink.withValues(alpha: .45), ink.withValues(alpha: .88)],
        ).createShader(Offset.zero & s),
    );
    glow(c, Offset(w * .5, h * .40), w * .65, accent, .15);
    final short = h < 450;
    final top = h * (short ? .22 : .18), stageH = h * (short ? .50 : .56);
    for (int i = 0; i < 45; i++) {
      final x = ((i * .618033 + t * .02) % 1) * w;
      final y = ((i * .371 + 1 - t * .08) % 1) * h;
      c.drawCircle(
        Offset(x, y),
        i % 3 == 0 ? 1.6 : .7,
        Paint()
          ..color = accent.withValues(
            alpha: .25 + .2 * math.sin(i + t * 4).abs(),
          ),
      );
    }
    if (event.ending) {
      _ending(c, s, top, stageH);
      return;
    }
    final impact = interval(.43, .65);
    final shake = reduced
        ? 0.0
        : math.sin(impact * math.pi * 10) * (1 - impact) * 12;
    final targetRect = Rect.fromLTWH(
      w * (w < 600 ? .57 : .62) + shake,
      top + stageH * .12,
      w * (w < 600 ? .40 : .25),
      stageH * .80,
    );
    if (event.kind == CinematicKind.out) {
      final r = Rect.fromLTWH(w * .34, top, w * .32, stageH);
      figurine(
        c,
        event.targetRole ?? Role.villager,
        r,
        alpha: 1 - ease(.32, .80),
      );
      for (int i = 0; i < 28; i++) {
        final p = Offset(
          r.left + (i * .23 % 1) * r.width,
          r.top + (i * .39 % 1) * r.height,
        );
        final drift =
            Offset(math.cos(i * 2.4), math.sin(i * 2.4)) *
            ease(.35, .90) *
            w *
            .30;
        c.save();
        c.translate(p.dx + drift.dx, p.dy + drift.dy);
        c.rotate(t * i * .2);
        c.drawPath(
          Path()
            ..moveTo(-4, -10)
            ..lineTo(6, 0)
            ..lineTo(-3, 8)
            ..close(),
          Paint()..color = gold.withValues(alpha: .65 * (1 - ease(.65, 1))),
        );
        c.restore();
      }
      glow(c, r.center, r.width, accent, .24 * math.sin(t * math.pi));
      return;
    }
    figurine(
      c,
      event.targetRole ?? Role.villager,
      targetRect,
      alpha: event.kind == CinematicKind.hunterShot
          ? 1 - .7 * ease(.56, .92)
          : 1,
    );
    final combat =
        event.kind == CinematicKind.wolfAttack ||
        event.kind == CinematicKind.hunterShot;
    final attack = ease(.14, .43), retreat = ease(.66, .93);
    final actorRect = Rect.fromLTWH(
      combat
          ? w *
                (.04 +
                    (event.kind == CinematicKind.wolfAttack ? .31 : .04) *
                        attack *
                        (1 - retreat))
          : w * .12,
      top,
      combat ? w * .48 : w * .26,
      stageH,
    );
    if (combat) {
      final frame = t < .25
          ? 0
          : t < .43
          ? 1
          : t < .66
          ? 2
          : 0;
      c.save();
      if (event.kind == CinematicKind.hunterShot) c.translate(-shake, 0);
      final paintedActor = sprite(c, actor, actorRect, frame);
      c.restore();
      if (t > .42 && t < .70) {
        final life = math.sin(interval(.42, .70) * math.pi);
        if (event.kind == CinematicKind.hunterShot) {
          final muzzle = Offset(
            paintedActor.left + paintedActor.width * .78 - shake,
            paintedActor.top + paintedActor.height * .195,
          );
          final hit = Offset(
            targetRect.center.dx,
            muzzle.dy.clamp(targetRect.top, targetRect.bottom),
          );
          glow(c, muzzle, w * .17, const Color(0xFFFFC968), life * .8);
          spark(c, muzzle, w * .045 * life, const Color(0xFFFFE9AF));
          c.drawLine(
            muzzle,
            hit,
            Paint()
              ..color = gold.withValues(alpha: life)
              ..strokeWidth = 3,
          );
          glow(c, hit, w * .13, gold, life * .7);
        } else {
          for (int i = 0; i < 3; i++) {
            final p = targetRect.center + Offset((i - 1) * 18, -20);
            c.drawPath(
              Path()
                ..moveTo(p.dx - 24, p.dy - 30)
                ..quadraticBezierTo(p.dx, p.dy, p.dx + 20, p.dy + 45),
              Paint()
                ..color = accent.withValues(alpha: life)
                ..strokeWidth = 5
                ..style = PaintingStyle.stroke
                ..strokeCap = StrokeCap.round,
            );
          }
          glow(c, targetRect.center, w * .22, accent, life * .6);
        }
      }
    } else {
      figurine(c, event.actorRole, actorRect);
      final center = targetRect.center;
      final power = math.sin(interval(.12, .93) * math.pi);
      glow(c, center, w * .30, accent, power * .55);
      for (int i = 0; i < 3; i++) {
        final radius = w * (.095 + i * .025) * (.5 + .5 * attack);
        c.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          t * math.pi * (i.isEven ? 2 : -2),
          math.pi * 1.5,
          false,
          Paint()
            ..color = accent.withValues(alpha: power * .65)
            ..style = PaintingStyle.stroke
            ..strokeWidth = i == 0 ? 2 : .8,
        );
      }
      if (event.kind == CinematicKind.guard) {
        final r = w * .10;
        final shield = Path()
          ..moveTo(center.dx, center.dy - r)
          ..lineTo(center.dx + r, center.dy - r * .65)
          ..quadraticBezierTo(
            center.dx + r,
            center.dy + r * .45,
            center.dx,
            center.dy + r * 1.2,
          )
          ..quadraticBezierTo(
            center.dx - r,
            center.dy + r * .45,
            center.dx - r,
            center.dy - r * .65,
          )
          ..close();
        c.drawPath(
          shield,
          Paint()..color = accent.withValues(alpha: power * .16),
        );
        c.drawPath(
          shield,
          Paint()
            ..color = accent.withValues(alpha: power)
            ..strokeWidth = 3
            ..style = PaintingStyle.stroke,
        );
      } else if (event.kind == CinematicKind.reveal) {
        final orb = Offset(w * .5, top + stageH * .4);
        glow(c, orb, w * .15, accent, power * .65);
        c.drawCircle(
          orb,
          w * .055,
          Paint()
            ..shader = RadialGradient(
              colors: [
                cream.withValues(alpha: power),
                accent.withValues(alpha: power * .35),
              ],
            ).createShader(Rect.fromCircle(center: orb, radius: w * .055)),
        );
        c.drawLine(
          orb,
          center,
          Paint()
            ..color = accent.withValues(alpha: power * .7)
            ..strokeWidth = 1,
        );
      } else {
        for (int i = 0; i < 30; i++) {
          final a = i * 2.399 + t * 3;
          final radius = w * .13 * (i % 5 / 5 + .2);
          final p =
              center +
              Offset(
                math.cos(a) * radius,
                math.sin(a) * radius - stageH * interval(.30, .95) * .25,
              );
          c.drawCircle(
            p,
            2 + i % 3,
            Paint()..color = accent.withValues(alpha: power * .65),
          );
        }
      }
    }
    c.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, ink.withValues(alpha: .0), ink],
        ).createShader(Offset.zero & s),
    );
  }

  void _ending(Canvas c, Size s, double top, double stageH) {
    final center = Offset(s.width / 2, top + stageH * .44);
    final good = event.kind == CinematicKind.goodWin;
    final radius = math.min(s.width * .27, stageH * .45);
    for (int i = 0; i < 24; i++) {
      final a = i * math.pi / 12 + t * .2;
      final direction = Offset(math.cos(a), math.sin(a));
      c.drawLine(
        center + direction * radius * .7,
        center + direction * radius * (1.4 + ease(.1, .7)),
        Paint()
          ..color = accent.withValues(alpha: .1 + .12 * math.sin(t * math.pi))
          ..strokeWidth = i.isEven ? 8 : 2,
      );
    }
    glow(c, center, radius * 2.4, accent, .45);
    c.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            good ? const Color(0xFFFFE1A3) : const Color(0xFFBD554F),
            good ? gold : const Color(0xFF301B28),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    if (!good) {
      c.drawCircle(
        center + Offset(radius * .22, -radius * .12),
        radius * .93,
        Paint()..color = ink,
      );
    }
    c.drawCircle(
      center,
      radius * 1.13,
      Paint()
        ..color = accent.withValues(alpha: .6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    figurine(
      c,
      good ? Role.villager : Role.werewolf,
      Rect.fromCenter(
        center: center,
        width: radius * 1.45,
        height: radius * 1.9,
      ),
      alpha: ease(.08, .32),
    );
    for (int i = 0; i < 80; i++) {
      final a = i * 2.399;
      final distance = radius * (.7 + (i % 12) / 12 * 2.0) * ease(.05, .8);
      final p = center + Offset(math.cos(a), math.sin(a)) * distance;
      c.drawCircle(
        p,
        (i % 3 + 1).toDouble(),
        Paint()..color = cream.withValues(alpha: .7),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) =>
      old.t != t || old.actor != actor;
}
