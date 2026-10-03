import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game/engine.dart';
import 'game/roles.dart';
import 'services/audio_director.dart';
import 'services/window_controller.dart';
import 'ui/kit.dart';
import 'ui/game_screen.dart';
import 'ui/hero_selector.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: ink,
    ),
  );
  // 读取一次原生窗口全屏状态（桌面端）。
  WindowController.instance.init();
  runApp(const MoonveilApp());
}

class MoonveilApp extends StatelessWidget {
  const MoonveilApp({super.key});
  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.f11) {
        WindowController.instance.toggle();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: MaterialApp(
      title: '月隐 · 狼人杀',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: ink,
        colorScheme: const ColorScheme.dark(
          primary: gold,
          surface: panel,
          onSurface: cream,
        ),
        fontFamily: 'NotoSerifSC',
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 13, color: cream, height: 1.8),
          bodySmall: TextStyle(fontSize: 11, color: muted, height: 1.7),
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: gold,
          thumbColor: gold,
          inactiveTrackColor: line,
        ),
        tooltipTheme: const TooltipThemeData(textStyle: TextStyle(color: ink)),
      ),
      home: const GameShell(),
    ),
  );
}

class GameShell extends StatefulWidget {
  const GameShell({super.key, this.audio});
  final AudioDirector? audio;
  @override
  State<GameShell> createState() => _GameShellState();
}

class _GameShellState extends State<GameShell> {
  late final AudioDirector audio = widget.audio ?? AudioDirector();
  int tab = 0;
  bool lobby = false, local = false;
  int count = 12;
  WinRule winRule = WinRule.border;
  Role? preferred;
  GameEngine? game;
  Map<String, dynamic>? saved;
  List<Map<String, dynamic>> history = [];
  SharedPreferences? prefs;
  Timer? saveTimer;
  bool resultRecorded = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await audio.load();
    prefs = await SharedPreferences.getInstance();
    final storedWinRule = prefs!.getString('winRule');
    for (final rule in WinRule.values) {
      if (rule.name == storedWinRule) {
        winRule = rule;
        break;
      }
    }
    try {
      final raw = prefs!.getString('game');
      if (raw != null) saved = jsonDecode(raw);
      history = (jsonDecode(prefs!.getString('history') ?? '[]') as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      saved = null;
    }
    if (mounted) setState(() {});
  }

  void _gameChanged() {
    if (game == null) return;
    if (game!.phase == Phase.ended && !resultRecorded) {
      resultRecorded = true;
      history.insert(0, {
        'date': DateTime.now().toIso8601String(),
        'winner': game!.winner,
        'role': game!.me.role.name,
        'local': game!.local,
        'count': game!.players.length,
        'day': game!.day,
      });
      if (history.length > 30) history.removeLast();
      prefs?.setString('history', jsonEncode(history));
    }
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 120), () {
      if (game == null) return;
      saved = game!.toJson();
      prefs?.setString('game', jsonEncode(saved));
    });
  }

  void _enterLobby({bool tabletop = false}) {
    audio.start();
    setState(() {
      lobby = true;
      local = tabletop;
      tab = 0;
    });
  }

  void _start() {
    game?.removeListener(_gameChanged);
    game?.dispose();
    game = GameEngine.create(
      count: count,
      local: local,
      preferred: preferred,
      winRule: winRule,
    );
    resultRecorded = false;
    game!.addListener(_gameChanged);
    _gameChanged();
    audio.start();
    audio.narrate('deal');
    setState(() => lobby = false);
  }

  void _updateWinRule(WinRule rule) {
    setState(() => winRule = rule);
    prefs?.setString('winRule', rule.name);
  }

  void _resume() {
    if (saved == null) return;
    try {
      game = GameEngine.fromJson(saved!);
      local = game!.local;
      count = game!.players.length;
      resultRecorded = game!.phase == Phase.ended;
      game!.addListener(_gameChanged);
      audio.start();
      setState(() => lobby = false);
    } catch (_) {
      saved = null;
      setState(() {});
    }
  }

  Future<void> _leave() async {
    audio.stopVoice();
    saveTimer?.cancel();
    if (game != null) {
      saved = game!.toJson();
      await prefs?.setString('game', jsonEncode(saved));
      game!.removeListener(_gameChanged);
      game!.dispose();
    }
    setState(() {
      game = null;
      tab = 0;
      lobby = false;
    });
  }

  @override
  void dispose() {
    saveTimer?.cancel();
    game?.dispose();
    audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (game != null) {
      return GameScreen(
        game: game!,
        audio: audio,
        onLeave: _leave,
        onSettings: () => showAudioSettings(
          context,
          audio,
          winRule: winRule,
          onWinRuleChanged: _updateWinRule,
          currentGameRule: game!.winRule,
        ),
        onRestart: () {
          _leave().then((_) {
            _enterLobby(tabletop: local);
          });
        },
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: wide ? 730 : 680,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const Art(
                  'assets/images/village.png',
                  alignment: Alignment(.35, -.2),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        ink.withValues(alpha: .15),
                        ink.withValues(alpha: .3),
                        ink,
                      ],
                      stops: const [0, .62, 1],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _header(wide),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: lobby
                        ? _lobby(wide)
                        : switch (tab) {
                            0 => _home(wide),
                            1 => _roles(wide),
                            2 => _rules(wide),
                            _ => _history(wide),
                          },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(bool wide) => Container(
    height: wide ? 88 : 72,
    padding: EdgeInsets.symmetric(horizontal: wide ? 48 : 20),
    decoration: BoxDecoration(
      color: ink.withValues(alpha: .65),
      border: Border(bottom: BorderSide(color: gold.withValues(alpha: .14))),
    ),
    child: Row(
      children: [
        GestureDetector(
          onTap: () => setState(() {
            tab = 0;
            lobby = false;
          }),
          child: Row(
            children: [
              const MoonLogo(size: 38),
              const SizedBox(width: 14),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('月 隐', style: heading(23, color: gold, spacing: 5)),
                  Text(
                    'MOONVEIL',
                    style: caption(size: 8, color: gold.withValues(alpha: .65)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Spacer(),
        if (wide) ...[
          for (int i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: InkWell(
                onTap: () {
                  audio.start();
                  setState(() {
                    tab = i;
                    lobby = false;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: tab == i && !lobby ? gold : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    ['月下启程', '角色图鉴', '规则手册', '旅人档案'][i],
                    style: TextStyle(
                      color: tab == i ? cream : muted,
                      fontSize: 13,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 24),
        ],
        if (WindowController.instance.isSupported)
          ValueListenableBuilder<bool>(
            valueListenable: WindowController.instance.fullScreen,
            builder: (_, isFs, __) => IconButton(
              tooltip: isFs ? '退出全屏' : '全屏',
              onPressed: () {
                audio.start();
                WindowController.instance.toggle();
              },
              icon: Icon(
                isFs
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                color: gold,
                size: 21,
              ),
            ),
          ),
        IconButton(
          tooltip: '设置',
          onPressed: () {
            audio.start();
            showAudioSettings(
              context,
              audio,
              winRule: winRule,
              onWinRuleChanged: _updateWinRule,
            );
          },
          icon: const Icon(Icons.tune_rounded, color: gold, size: 21),
        ),
        if (!wide)
          IconButton(
            tooltip: '导航菜单',
            onPressed: () => gameDialog(
              context,
              title: '月下旅途',
              child: Column(
                children: [
                  for (int i = 0; i < 4; i++)
                    ListTile(
                      title: Text(['月下启程', '角色图鉴', '规则手册', '旅人档案'][i]),
                      trailing: const Icon(Icons.chevron_right, color: gold),
                      onTap: () {
                        Navigator.pop(context);
                        setState(() {
                          tab = i;
                          lobby = false;
                        });
                      },
                    ),
                ],
              ),
            ),
            icon: const Icon(Icons.menu_rounded, color: gold),
          ),
      ],
    ),
  );
  Widget _frame(Widget child, {String? keyName}) => SingleChildScrollView(
    key: ValueKey(keyName ?? '$tab-$lobby'),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1440),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.sizeOf(context).width >= 1000 ? 64 : 22,
            vertical: 28,
          ),
          child: child,
        ),
      ),
    ),
  );
  Widget _home(bool wide) => _frame(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: wide ? 420 : 410,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Container(width: 28, height: 1, color: gold),
                        const SizedBox(width: 12),
                        Text(
                          '月光之下 · 暗藏真相',
                          style: caption(color: gold, size: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text(
                      '每个人，\n都有一个秘密。',
                      style: heading(wide ? 50 : 34, spacing: 4),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '当钟声敲响，熟悉的面孔也许不再可信。\n倾听、推理、抉择。让真相穿过这片长夜。',
                      style: TextStyle(
                        color: const Color(0xFFAFB8BD),
                        fontSize: wide ? 13 : 12,
                        height: 2.1,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        GameButton(
                          '踏入月夜',
                          onTap: () => _enterLobby(),
                          icon: Icons.nightlight_round,
                          width: wide ? 216 : 205,
                        ),
                        if (saved != null && saved!['phase'] != 'ended')
                          GameButton(
                            '继续旅程',
                            onTap: _resume,
                            primary: false,
                            small: true,
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Icon(
                          Icons.headphones_outlined,
                          size: 13,
                          color: muted,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '中文语音主持  /  经典狼人杀  /  离线畅玩',
                            style: TextStyle(
                              fontSize: 10,
                              color: muted,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (wide)
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 46, right: 15),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'THE NIGHT KNOWS',
                            style: caption(
                              size: 9,
                              color: cream.withValues(alpha: .55),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '「 不要轻信，任何一盏灯。 」',
                            style: heading(
                              13,
                              color: cream.withValues(alpha: .65),
                              spacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) {
            final cards = [_modeCard(false), _modeCard(true)];
            return wide
                ? Row(
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 20),
                      Expanded(child: cards[1]),
                    ],
                  )
                : Column(
                    children: [cards[0], const SizedBox(height: 14), cards[1]],
                  );
          },
        ),
        const SizedBox(height: 42),
        SectionLabel(
          '月下众生',
          'SIX ROLES · SIX FATES',
          trailing: TextButton(
            onPressed: () => setState(() => tab = 1),
            child: const Text(
              '查看图鉴  →',
              style: TextStyle(color: gold, fontSize: 11),
            ),
          ),
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, c) {
            final w = wide ? (c.maxWidth - 5 * 16) / 6 : 155.0;
            return SizedBox(
              height: wide ? w * 1.43 : 235,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: Role.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemBuilder: (_, i) => RoleCard(
                  Role.values[i],
                  width: w,
                  height: wide ? w * 1.43 : 230,
                  onTap: () => showRoleDetail(context, Role.values[i], audio),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 36),
        _footer(),
      ],
    ),
    keyName: 'home',
  );
  Widget _modeCard(bool tabletop) => InkWell(
    onTap: () => _enterLobby(tabletop: tabletop),
    child: OrnatePanel(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 21),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: gold.withValues(alpha: .3)),
              color: gold.withValues(alpha: .05),
            ),
            child: Icon(
              tabletop ? Icons.groups_outlined : Icons.auto_awesome_outlined,
              color: gold,
              size: 22,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Text(tabletop ? '围炉聚会' : '单人历练', style: heading(20)),
                    Tag(tabletop ? '同屏传递' : 'AI 对战'),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  tabletop ? '与朋友相聚，把秘密交给月光。' : '独自踏入迷雾，在推理中磨练直觉。',
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.arrow_forward, color: gold, size: 19),
        ],
      ),
    ),
  );
  Widget _footer() => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: Container(height: 1, color: line.withValues(alpha: .5)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              '✦',
              style: TextStyle(color: gold.withValues(alpha: .6), fontSize: 12),
            ),
          ),
          Expanded(
            child: Container(height: 1, color: line.withValues(alpha: .5)),
          ),
        ],
      ),
      const SizedBox(height: 18),
      Text('月 隐  ·  在 长 夜 中 ， 找 到 彼 此', style: caption(size: 9)),
      const SizedBox(height: 16),
    ],
  );
  Widget _lobby(bool wide) => _frame(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => lobby = false),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('返回村庄', style: TextStyle(fontSize: 12)),
          ),
        ),
        const SizedBox(height: 14),
        const SectionLabel('准备踏入长夜', 'CHOOSE YOUR JOURNEY'),
        const SizedBox(height: 22),
        OrnatePanel(
          padding: EdgeInsets.all(wide ? 20 : 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, c) => c.maxWidth >= 760
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _journeyChoices()),
                          const SizedBox(width: 24),
                          Expanded(child: _villageChoices()),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _journeyChoices(),
                          const SizedBox(height: 20),
                          _villageChoices(),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in Role.values.where(
                    (r) => count == 12 || r != Role.guard,
                  ))
                    Tag(
                      '${r.title} × ${r == Role.werewolf || r == Role.villager ? (count == 9 ? 3 : 4) : 1}',
                      color: r.color,
                    ),
                ],
              ),
              if (local) ...[
                const SizedBox(height: 18),
                const Text(
                  '身份随机分配。请依次传递设备查看身份；夜晚仅行动者睁眼，白天面对面讨论。',
                  style: TextStyle(color: muted, fontSize: 13, height: 1.9),
                ),
              ],
            ],
          ),
        ),
        if (!local) ...[
          const SizedBox(height: 20),
          OrnatePanel(
            padding: EdgeInsets.all(wide ? 20 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('03  你的命运', style: caption(color: gold)),
                const SizedBox(height: 10),
                HeroSelector(
                  selected: preferred,
                  count: count,
                  onSelect: (role) => setState(() => preferred = role),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        OrnatePanel(
          padding: EdgeInsets.all(wide ? 20 : 14),
          child: LayoutBuilder(
            builder: (context, c) {
              final rules = Text(
                '${winRule.title} · 无警长 · 最高票平票无人出局\n女巫首夜可自救 · 同守同救出局',
                style: const TextStyle(color: muted, fontSize: 12, height: 1.9),
              );
              final start = GameButton(
                '开启 $count 人${local ? '聚会' : '历练'}',
                onTap: _start,
                width: double.infinity,
                icon: Icons.nightlight_round,
              );
              return c.maxWidth >= 660
                  ? Row(
                      children: [
                        Expanded(child: rules),
                        const SizedBox(width: 24),
                        SizedBox(width: 310, child: start),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [rules, const SizedBox(height: 18), start],
                    );
            },
          ),
        ),
        const SizedBox(height: 28),
        _footer(),
      ],
    ),
    keyName: 'lobby',
  );

  Widget _journeyChoices() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('01  选择旅途', style: caption(color: gold)),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _option(
              '单人历练',
              '与规则 AI 对战',
              !local,
              () => setState(() => local = false),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _option(
              '围炉聚会',
              '同屏轮流操作',
              local,
              () => setState(() => local = true),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _villageChoices() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('02  选择村庄', style: caption(color: gold)),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _option(
              '9 人经典局',
              '3 狼 · 3 民 · 3 神',
              count == 9,
              () => setState(() {
                count = 9;
                if (preferred == Role.guard) preferred = null;
              }),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _option(
              '12 人守卫局',
              '4 狼 · 4 民 · 4 神',
              count == 12,
              () => setState(() => count = 12),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _option(String title, String sub, bool selected, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
          decoration: BoxDecoration(
            color: selected
                ? gold.withValues(alpha: .09)
                : ink.withValues(alpha: .5),
            border: Border.all(color: selected ? gold : line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: heading(
                        15,
                        color: selected ? gold : cream,
                        spacing: 1,
                      ),
                    ),
                  ),
                  if (selected)
                    const Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: gold,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(sub, style: const TextStyle(color: muted, fontSize: 10)),
            ],
          ),
        ),
      );
  Widget _roles(bool wide) => _frame(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const SectionLabel('月下众生', 'THE CHARACTERS OF MOONVEIL'),
        const SizedBox(height: 16),
        const Text(
          '每一种身份，都有自己的使命。点击角色，聆听他们的故事。',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, c) {
            final cols = wide ? 3 : 2;
            final w = (c.maxWidth - (cols - 1) * 20) / cols;
            return Wrap(
              spacing: 20,
              runSpacing: 24,
              children: [
                for (final r in Role.values)
                  RoleCard(
                    r,
                    width: w,
                    height: wide ? 420 : w * 1.62,
                    onTap: () => showRoleDetail(context, r, audio),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 32),
        _footer(),
      ],
    ),
    keyName: 'roles',
  );
  Widget _rules(bool wide) => _frame(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const SectionLabel('长夜生存手册', 'HOW TO SURVIVE THE NIGHT'),
        const SizedBox(height: 28),
        OrnatePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('从夜幕降临，到真相大白。', style: heading(wide ? 30 : 22)),
              const SizedBox(height: 24),
              Wrap(
                spacing: 22,
                runSpacing: 22,
                children: [
                  for (int i = 0; i < 4; i++)
                    SizedBox(
                      width: wide ? 235 : 135,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('0${i + 1}', style: heading(32, color: gold)),
                          Text(
                            ['领取身份', '夜间行动', '白天发言', '投票放逐'][i],
                            style: heading(16),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            [
                              '独自查看角色，记住阵营与技能。',
                              '神职与狼队依次使用技能。',
                              '分享线索，倾听每个人的理由。',
                              '票数最多者出局，直到一方胜利。',
                            ][i],
                            style: const TextStyle(
                              color: muted,
                              fontSize: 12,
                              height: 1.9,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 28),
              Container(height: 1, color: line),
              const SizedBox(height: 24),
              const SelectableText(
                rulesText,
                style: TextStyle(fontSize: 13, height: 2, color: cream),
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        GameButton('我已准备好', onTap: () => _enterLobby(), width: 220),
        const SizedBox(height: 32),
      ],
    ),
    keyName: 'rules',
  );
  Widget _history(bool wide) => _frame(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const SectionLabel('旅人档案', 'YOUR STORIES UNDER THE MOON'),
        const SizedBox(height: 28),
        OrnatePanel(
          child: Row(
            children: [
              const MoonLogo(size: 70),
              const SizedBox(width: 26),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('长夜旅人', style: heading(26)),
                    const SizedBox(height: 8),
                    Text(
                      '已完成 ${history.length} 场旅途 · 记录保存在本机',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (history.isEmpty)
          OrnatePanel(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  children: [
                    const Icon(Icons.menu_book_outlined, size: 36, color: gold),
                    const SizedBox(height: 18),
                    Text('你的故事，尚未写下。', style: heading(20)),
                    const SizedBox(height: 10),
                    const Text(
                      '完成一场游戏后，战绩会留在这里。',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          for (final h in history)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OrnatePanel(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Icon(
                      h['winner'] == 'good'
                          ? Icons.wb_sunny_outlined
                          : Icons.nightlight_round,
                      color: gold,
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${h['winner'] == 'good' ? '好人' : '狼人'}阵营获胜 · ${h['count']} 人局',
                            style: heading(16),
                          ),
                          Text(
                            '${h['date'].toString().substring(0, 10)}  ·  ${h['local'] == true ? '围炉聚会' : Role.values.byName(h['role']).title}  ·  第 ${h['day']} 天',
                            style: const TextStyle(color: muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.auto_awesome_outlined,
                      color: gold,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 30),
      ],
    ),
    keyName: 'history',
  );
}

class ExpandedIf extends StatelessWidget {
  final bool enabled;
  final int flex;
  final Widget child;
  const ExpandedIf({
    super.key,
    required this.enabled,
    this.flex = 1,
    required this.child,
  });
  @override
  Widget build(BuildContext context) =>
      enabled ? Expanded(flex: flex, child: child) : child;
}

Future<void> showRoleDetail(
  BuildContext context,
  Role role,
  AudioDirector audio,
) async {
  await gameDialog(
    context,
    title: '角色图鉴',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 310,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Art(role.asset, alignment: const Alignment(0, -.55)),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, ink.withValues(alpha: .9)],
                  ),
                ),
              ),
              Positioned(
                left: 20,
                bottom: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(role.english, style: caption(color: gold, size: 9)),
                    Text(role.title, style: heading(36)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          children: [
            Tag(role.camp, color: role.color),
            Tag(role.skill),
          ],
        ),
        const SizedBox(height: 18),
        Text(role.flavor, style: heading(17, color: gold, spacing: 1)),
        const SizedBox(height: 18),
        Text(
          role.description,
          style: const TextStyle(color: muted, fontSize: 13, height: 2),
        ),
        const SizedBox(height: 20),
        GameButton(
          '聆听角色故事',
          onTap: () {
            audio.start();
            audio.narrate('${role.name}_lore');
          },
          primary: false,
          icon: Icons.volume_up_outlined,
          small: true,
        ),
      ],
    ),
  );
  await audio.stopVoice();
}

Future<void> showAudioSettings(
  BuildContext context,
  AudioDirector audio, {
  required WinRule winRule,
  required ValueChanged<WinRule> onWinRuleChanged,
  WinRule? currentGameRule,
}) {
  var selectedRule = winRule;
  return gameDialog(
    context,
    title: '设置',
    child: StatefulBuilder(
      builder: (context, setDialogState) => ListenableBuilder(
        listenable: audio,
        builder: (_, __) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('胜负规则', style: caption(color: gold)),
            const SizedBox(height: 4),
            Text(
              currentGameRule == null
                  ? '选择后应用于新开启的对局。'
                  : '本局采用「${currentGameRule.title}」。更改后应用于新开启的对局。',
              style: const TextStyle(color: muted, fontSize: 11, height: 1.7),
            ),
            const SizedBox(height: 8),
            for (final rule in WinRule.values)
              RadioListTile<WinRule>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeColor: gold,
                title: Text(rule.title, style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  rule.description,
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
                value: rule,
                groupValue: selectedRule,
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => selectedRule = value);
                  onWinRuleChanged(value);
                },
              ),
            const SizedBox(height: 12),
            Container(height: 1, color: line),
            const SizedBox(height: 14),
            Text('声音与氛围', style: caption(color: gold)),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('月夜氛围音乐', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                '原创风声、低鸣与远处钟音',
                style: TextStyle(color: muted, fontSize: 11),
              ),
              value: audio.musicEnabled,
              activeThumbColor: gold,
              onChanged: (v) => audio.update(music: v),
            ),
            Slider(
              value: audio.musicVolume,
              onChanged: (v) => audio.update(musicLevel: v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('中文语音主持', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                '离线合成配音，私密操作不会公开播报',
                style: TextStyle(color: muted, fontSize: 11),
              ),
              value: audio.voiceEnabled,
              activeThumbColor: gold,
              onChanged: (v) => audio.update(voice: v),
            ),
            Slider(
              value: audio.voiceVolume,
              onChanged: (v) => audio.update(voiceLevel: v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('战斗与技能音效', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                '开枪、扑袭、技能与胜负演出的声音',
                style: TextStyle(color: muted, fontSize: 11),
              ),
              value: audio.effectsEnabled,
              activeThumbColor: gold,
              onChanged: (v) => audio.update(effects: v),
            ),
            const SizedBox(height: 16),
            GameButton(
              '试听中文主持',
              onTap: () => audio.narrate('welcome'),
              primary: false,
              icon: Icons.play_arrow,
              small: true,
            ),
            if (audio.error != null) ...[
              const SizedBox(height: 12),
              Text(
                audio.error!,
                style: const TextStyle(color: Color(0xFFC77368), fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
