import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/roles.dart';
import 'kit.dart';

/// Each frame is a full-body ImageGen figurine on its own display plinth.
class HeroFigurine extends StatelessWidget {
  final Role role;
  const HeroFigurine(this.role, {super.key});
  @override
  Widget build(BuildContext context) {
    // ImageGen trims the outer alpha margins. These frames preserve full heads,
    // capes and plinths at the generated sheet's native aspect ratios.
    final frame = role.figurineFrame;
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: frame.width,
        height: frame.height,
        child: ClipRect(
          child: Stack(
            children: [
              Positioned(
                left: -frame.left,
                top: -frame.top,
                width: 1222,
                height: 1287,
                child: Image.asset(
                  'assets/images/hero-figures.png',
                  fit: BoxFit.fill,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A complete portrait stays next to the choices at every screen shape.
class HeroSelector extends StatefulWidget {
  final Role? selected;
  final int count;
  final ValueChanged<Role?> onSelect;
  const HeroSelector({
    super.key,
    required this.selected,
    required this.count,
    required this.onSelect,
  });

  @override
  State<HeroSelector> createState() => _HeroSelectorState();
}

class _HeroSelectorState extends State<HeroSelector> {
  final strip = ScrollController();

  @override
  void dispose() {
    strip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final screen = MediaQuery.sizeOf(context);
      final roles = Role.values
          .where((r) => widget.count == 12 || r != Role.guard)
          .toList();
      final landscape = c.maxWidth >= 480 && screen.height < 650;
      final surrounding = c.maxWidth >= 680 || landscape;
      final color = widget.selected?.color ?? gold;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('选择你的化身', style: heading(16))),
              const SizedBox(width: 8),
              Semantics(
                selected: widget.selected == null,
                child: OutlinedButton.icon(
                  key: const ValueKey('hero-random'),
                  onPressed: () => widget.onSelect(null),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: gold,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    side: BorderSide(
                      color: widget.selected == null ? gold : line,
                    ),
                    backgroundColor: widget.selected == null
                        ? gold.withValues(alpha: .1)
                        : Colors.transparent,
                    shape: const RoundedRectangleBorder(),
                  ),
                  icon: Icon(
                    widget.selected == null
                        ? Icons.check_circle_outline
                        : Icons.auto_awesome_outlined,
                    size: 16,
                  ),
                  label: const Text('随机身份', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
          if (!landscape) ...[
            const SizedBox(height: 8),
            Text(
              surrounding ? '点击周围的角色，查看完整立绘' : '左右滑动角色卡片，选择你的命运',
              style: const TextStyle(color: muted, fontSize: 11, height: 1.6),
            ),
          ],
          const SizedBox(height: 12),
          if (surrounding)
            _surrounding(roles, c.maxWidth, screen.height, landscape)
          else ...[
            Center(
              child: SizedBox(
                width: math.min(
                  c.maxWidth,
                  ((screen.height * .42).clamp(260.0, 360.0) - 72) * 2 / 3 + 16,
                ),
                height: (screen.height * .42).clamp(260.0, 360.0),
                child: _RolePreview(widget.selected),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              key: const ValueKey('hero-role-strip'),
              height: 134,
              child: Scrollbar(
                controller: strip,
                child: SingleChildScrollView(
                  controller: strip,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < roles.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        SizedBox(
                          width: 96,
                          height: 128,
                          child: _choice(roles[i]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            key: const ValueKey('hero-description'),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .055),
              border: Border(left: BorderSide(color: color, width: 2)),
            ),
            child: Text(
              widget.selected?.description ?? '让命运为你揭晓身份。每一种角色，都有自己的使命。',
              style: const TextStyle(color: cream, fontSize: 13, height: 1.85),
            ),
          ),
        ],
      );
    },
  );

  Widget _choice(Role role, {bool inline = false}) => _RoleChoice(
    role: role,
    selected: widget.selected == role,
    inline: inline,
    onTap: () => widget.onSelect(role),
  );

  Widget _surrounding(
    List<Role> roles,
    double width,
    double screenHeight,
    bool landscape,
  ) {
    final height = landscape
        ? (screenHeight - 140).clamp(170.0, 370.0)
        : (screenHeight * .62).clamp(460.0, 580.0);
    final maxPreviewHeight = landscape ? height : height * .91;
    final previewWidth = math.min(
      width * .34,
      (maxPreviewHeight - 72) * 2 / 3 + 16,
    );
    final previewHeight = (previewWidth - 16) * 1.5 + 72;
    final cardWidth = landscape
        ? math.min(170.0, width * .23)
        : math.min(136.0, width * .17);
    final cardHeight = landscape
        ? math.min(62.0, height / 3 - 4)
        : math.min(168.0, height * .29);
    final left = roles.take((roles.length + 1) ~/ 2).toList();
    final right = roles.skip(left.length).toList();
    return SizedBox(
      key: ValueKey(landscape ? 'hero-landscape' : 'hero-orbit'),
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _OrbitPainter(widget.selected?.color ?? gold),
              ),
            ),
          ),
          Positioned(
            left: (width - previewWidth) / 2,
            top: (height - previewHeight) / 2,
            width: previewWidth,
            height: previewHeight,
            child: _RolePreview(widget.selected, compact: landscape),
          ),
          for (var side = 0; side < 2; side++)
            for (var i = 0; i < (side == 0 ? left : right).length; i++)
              Positioned(
                left:
                    width *
                        (side == 0
                            ? (i == 1 && left.length == 3 ? .12 : .19)
                            : (i == 1 && right.length == 3 ? .88 : .81)) -
                    cardWidth / 2,
                top:
                    height * ((i + .5) / (side == 0 ? left : right).length) -
                    cardHeight / 2,
                width: cardWidth,
                height: cardHeight,
                child: _choice(
                  (side == 0 ? left : right)[i],
                  inline: landscape,
                ),
              ),
        ],
      ),
    );
  }
}

class _RolePreview extends StatelessWidget {
  final Role? role;
  final bool compact;
  const _RolePreview(this.role, {this.compact = false});

  @override
  Widget build(BuildContext context) {
    final color = role?.color ?? gold;
    return Container(
      key: const ValueKey('hero-preview'),
      decoration: BoxDecoration(
        color: ink,
        border: Border.all(color: color.withValues(alpha: .65)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: .12), blurRadius: 28),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: role == null
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [gold.withValues(alpha: .15), panel, ink],
                          radius: .9,
                        ),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            MoonLogo(size: compact ? 52 : 72),
                            const SizedBox(height: 16),
                            Text(
                              '?',
                              style: heading(compact ? 26 : 36, color: gold),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Center(
                      child: AspectRatio(
                        aspectRatio: 2 / 3,
                        child: Art(
                          role!.asset,
                          key: const ValueKey('hero-preview-art'),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
            ),
          ),
          Container(height: 1, color: color.withValues(alpha: .25)),
          Padding(
            padding: EdgeInsets.symmetric(
              vertical: compact ? 6 : 9,
              horizontal: 8,
            ),
            child: Column(
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    role?.title ?? '随机身份',
                    style: heading(compact ? 18 : 23, color: color),
                  ),
                ),
                if (!compact)
                  Text(
                    role?.skill ?? '让命运为你揭晓',
                    style: const TextStyle(
                      color: muted,
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleChoice extends StatefulWidget {
  final Role role;
  final bool selected, inline;
  final VoidCallback onTap;
  const _RoleChoice({
    required this.role,
    required this.selected,
    required this.onTap,
    this.inline = false,
  });

  @override
  State<_RoleChoice> createState() => _RoleChoiceState();
}

class _RoleChoiceState extends State<_RoleChoice> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || hover;
    final color = widget.role.color;
    final label = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.role.title,
          style: heading(
            widget.inline ? 14 : 12,
            color: active ? color : cream,
            spacing: 1,
          ),
        ),
        if (!widget.inline)
          Text(
            widget.role.skill,
            style: const TextStyle(color: muted, fontSize: 9, height: 1.6),
          ),
      ],
    );
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.role.title,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() => hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: active ? .18 : .07),
                panel,
                ink,
              ],
            ),
            border: Border.all(
              color: active ? color : line,
              width: widget.selected ? 2 : 1,
            ),
            boxShadow: [
              if (active)
                BoxShadow(color: color.withValues(alpha: .15), blurRadius: 14),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey('hero-${widget.role.name}'),
              onTap: widget.onTap,
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(7),
                    child: widget.inline
                        ? Row(
                            children: [
                              SizedBox(
                                width: 32,
                                child: HeroFigurine(widget.role),
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: label),
                            ],
                          )
                        : Column(
                            children: [
                              Expanded(child: HeroFigurine(widget.role)),
                              const SizedBox(height: 5),
                              label,
                            ],
                          ),
                  ),
                  if (widget.selected)
                    Positioned(
                      top: 5,
                      right: 5,
                      child: Icon(Icons.check_circle, color: color, size: 13),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  final Color color;
  const _OrbitPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width * .75,
      height: size.height * .88,
    );
    final paint = Paint()
      ..color = color.withValues(alpha: .2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawOval(rect, paint);
    canvas.drawOval(
      rect.deflate(7),
      paint..color = color.withValues(alpha: .055),
    );
    for (var i = 0; i < 12; i++) {
      final angle = math.pi * 2 * i / 12;
      final point =
          rect.center +
          Offset(
            math.cos(angle) * rect.width / 2,
            math.sin(angle) * rect.height / 2,
          );
      canvas.drawCircle(
        point,
        2,
        Paint()..color = color.withValues(alpha: .35),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) =>
      oldDelegate.color != color;
}
