import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/roles.dart';

const ink = Color(0xFF0A1016);
const panel = Color(0xFF111C24);
const gold = Color(0xFFCCAE76);
const cream = Color(0xFFE9E2D4);
const muted = Color(0xFF92A1A9);
const line = Color(0xFF354047);
const serif = 'NotoSerifSC';

TextStyle heading(double size, {Color color = cream, double spacing = 2}) =>
    TextStyle(
      fontFamily: serif,
      fontSize: size,
      fontWeight: FontWeight.w600,
      color: color,
      letterSpacing: spacing,
      height: 1.45,
    );
TextStyle caption({Color color = muted, double size = 11}) =>
    TextStyle(fontSize: size, letterSpacing: 2.5, color: color, height: 1.6);

class MoonLogo extends StatelessWidget {
  final double size;
  const MoonLogo({super.key, this.size = 38});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _MoonPainter());
}

class _MoonPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final center = Offset(s.width / 2, s.height / 2);
    c.drawCircle(center, s.width * .41, p);
    c.drawCircle(center, s.width * .34, p..color = gold.withValues(alpha: .35));
    final crescent = Path()
      ..addOval(Rect.fromCircle(center: center, radius: s.width * .23));
    final cut = Path()
      ..addOval(
        Rect.fromCircle(
          center: center + Offset(s.width * .11, -s.height * .07),
          radius: s.width * .21,
        ),
      );
    c.drawPath(
      Path.combine(PathOperation.difference, crescent, cut),
      Paint()..color = gold,
    );
    for (final angle in [0.0, math.pi / 2, math.pi, math.pi * 1.5]) {
      final x =
          center + Offset(math.cos(angle), math.sin(angle)) * s.width * .47;
      c.drawCircle(x, 1.7, Paint()..color = gold);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class GameButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final IconData? icon;
  final double? width;
  final bool small;
  const GameButton(
    this.label, {
    super.key,
    required this.onTap,
    this.primary = true,
    this.icon,
    this.width,
    this.small = false,
  });
  @override
  State<GameButton> createState() => _GameButtonState();
}

class _GameButtonState extends State<GameButton> {
  bool hover = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() => hover = false),
        child: ClipPath(
          clipper: _CutCorners(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: widget.width,
            height: widget.small ? 42 : 54,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: widget.primary
                    ? [
                        hover
                            ? const Color(0xFFE3C892)
                            : const Color(0xFFD1B780),
                        const Color(0xFF9C7B49),
                      ]
                    : [panel, hover ? const Color(0xFF263744) : panel],
              ),
              border: Border.all(color: widget.primary ? gold : line),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                child: Opacity(
                  opacity: enabled ? 1 : .38,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.small ? 16 : 26,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(
                            widget.icon,
                            size: 18,
                            color: widget.primary ? ink : gold,
                          ),
                          const SizedBox(width: 10),
                        ],
                        Flexible(
                          child: Text(
                            widget.label,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: serif,
                              color: widget.primary ? ink : cream,
                              fontWeight: FontWeight.w600,
                              fontSize: widget.small ? 13 : 15,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                        if (widget.primary) ...[
                          const SizedBox(width: 20),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 17,
                            color: ink,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CutCorners extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(8, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width, s.height - 8)
    ..lineTo(s.width - 8, s.height)
    ..lineTo(0, s.height)
    ..lineTo(0, 8)
    ..close();
  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class OrnatePanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  const OrnatePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.color = panel,
  });
  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _CornerPainter(),
    child: Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .92),
        border: Border.all(color: line.withValues(alpha: .8)),
      ),
      padding: padding,
      child: child,
    ),
  );
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = gold.withValues(alpha: .7)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (final x in [0.0, s.width]) {
      for (final y in [0.0, s.height]) {
        final dx = x == 0 ? 1.0 : -1.0, dy = y == 0 ? 1.0 : -1.0;
        c.drawPath(
          Path()
            ..moveTo(x + dx * 4, y + dy * 17)
            ..lineTo(x + dx * 4, y + dy * 4)
            ..lineTo(x + dx * 17, y + dy * 4),
          p,
        );
        c.drawCircle(Offset(x + dx * 4, y + dy * 4), 1.5, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SectionLabel extends StatelessWidget {
  final String title, subtitle;
  final Widget? trailing;
  const SectionLabel(this.title, this.subtitle, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(width: 3, height: 26, color: gold),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: heading(22)),
            Text(subtitle, style: caption(size: 9)),
          ],
        ),
      ),
      if (trailing != null) trailing!,
    ],
  );
}

class Tag extends StatelessWidget {
  final String text;
  final Color color;
  const Tag(this.text, {super.key, this.color = gold});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      border: Border.all(color: color.withValues(alpha: .35)),
      color: color.withValues(alpha: .06),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 10, letterSpacing: 1.5),
    ),
  );
}

class Art extends StatelessWidget {
  final String path;
  final BoxFit fit;
  final Alignment alignment;
  const Art(
    this.path, {
    super.key,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });
  @override
  Widget build(BuildContext context) => Image.asset(
    path,
    fit: fit,
    alignment: alignment,
    errorBuilder: (_, __, ___) => Container(
      color: panel,
      child: const Center(child: MoonLogo(size: 80)),
    ),
  );
}

class RoleCard extends StatefulWidget {
  final Role role;
  final VoidCallback onTap;
  final double width, height;
  const RoleCard(
    this.role, {
    super.key,
    required this.onTap,
    this.width = 180,
    this.height = 260,
  });
  @override
  State<RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<RoleCard> {
  bool hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => hover = true),
    onExit: (_) => setState(() => hover = false),
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: widget.width,
        height: widget.height,
        transform: Matrix4.translationValues(0, hover ? -5 : 0, 0),
        decoration: BoxDecoration(
          border: Border.all(color: hover ? gold : line),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Art(widget.role.asset, alignment: Alignment.topCenter),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [.4, 1],
                  colors: [Colors.transparent, ink.withValues(alpha: .98)],
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Icon(widget.role.icon, size: 18, color: gold),
            ),
            Positioned(
              bottom: 16,
              left: 16,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.role.title, style: heading(21)),
                  const SizedBox(height: 4),
                  Text(
                    widget.role.skill,
                    style: TextStyle(
                      color: widget.role.color,
                      fontSize: 11,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<T?> gameDialog<T>(
  BuildContext context, {
  required String title,
  required Widget child,
  List<Widget> actions = const [],
}) => showDialog<T>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: .8),
  builder: (ctx) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(20),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 580),
      child: OrnatePanel(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const MoonLogo(size: 26),
                  const SizedBox(width: 12),
                  Expanded(child: Text(title, style: heading(23))),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, size: 20, color: muted),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              child,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 24),
                Wrap(spacing: 12, runSpacing: 12, children: actions),
              ],
            ],
          ),
        ),
      ),
    ),
  ),
);
