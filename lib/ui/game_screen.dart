import 'dart:async';

import 'package:flutter/material.dart';

import '../game/engine.dart';
import '../game/ai_personality.dart';
import '../game/roles.dart';
import '../game/cinematic_event.dart';
import '../services/audio_director.dart';
import 'kit.dart';
import 'cinematic_overlay.dart';

class GameScreen extends StatefulWidget {
  final GameEngine game;
  final AudioDirector audio;
  final Future<void> Function() onLeave;
  final VoidCallback onSettings, onRestart;
  const GameScreen({
    super.key,
    required this.game,
    required this.audio,
    required this.onLeave,
    required this.onSettings,
    required this.onRestart,
  });
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  GameEngine get g => widget.game;
  int? selected;
  String? focusedSpeech;
  bool followHost = true;
  String? previousNarration;
  final focusScroll = ScrollController();
  final historyScroll = ScrollController();
  final discussionSeatsScroll = ScrollController();
  bool revealed = false;
  bool identityVisible = true;
  String token = '';
  int discussionSeconds = 120;
  Timer? clock;
  bool timerRunning = false;
  bool showingPrivateResult = false;
  CinematicEvent? cinematic;
  Completer<void>? cinematicDone;
  final List<CinematicEvent> cues = [];
  bool actionInProgress = false, flowInProgress = false, draining = false;
  bool endingQueued = false;
  int eventIndex = 0;
  int? actingHunter;
  @override
  void initState() {
    super.initState();
    g.addListener(_changed);
    widget.audio.addListener(_audioChanged);
    token = _token;
    eventIndex = g.events.length;
    WidgetsBinding.instance.addPostFrameCallback((_) => _narrate());
  }

  String get _token =>
      '${g.phase.name}-${g.day}-${g.dealIndex}-${g.voteIndex}-${g.awaitingNightConfirmation}-${g.nightResultPending}';
  bool get _showDawn => g.nightResultPending;
  bool get _private =>
      !_showDawn && g.local && (g.phase == Phase.deal || g.isAction);
  void _changed() {
    for (final event in g.events.skip(eventIndex)) {
      if (event.kind == 'exile' && event.targetId != null) {
        cues.add(
          CinematicEvent.forTarget(
            CinematicKind.out,
            g,
            g.player(event.targetId!),
          ),
        );
      } else if (event.kind == 'shot' &&
          event.targetId != null &&
          event.actorId != actingHunter) {
        cues.add(
          CinematicEvent.forTarget(
            CinematicKind.hunterShot,
            g,
            g.player(event.targetId!),
            actorRole: Role.hunter,
          ),
        );
      }
    }
    eventIndex = g.events.length;
    if (g.phase == Phase.ended && !endingQueued) {
      endingQueued = true;
      cues.add(
        CinematicEvent(
          g.winner == 'good' ? CinematicKind.goodWin : CinematicKind.wolfWin,
        ),
      );
    }
    if (_token != token) {
      token = _token;
      selected = null;
      focusedSpeech = null;
      followHost = true;
      if (!g.awaitingNightConfirmation) revealed = false;
      if (g.phase == Phase.discussion) discussionSeconds = 120;
      clock?.cancel();
      timerRunning = false;
      _narrate();
    }
    if (mounted) setState(() {});
    if (cues.isNotEmpty &&
        !g.nightResultPending &&
        !actionInProgress &&
        !flowInProgress) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _drainCues();
        _narrate();
      });
    }
  }

  void _audioChanged() {
    if (!mounted) return;
    final key = widget.audio.activeNarrationKey;
    if (key == 'discussion' && previousNarration != key) {
      followHost = true;
      if (focusScroll.hasClients) focusScroll.jumpTo(0);
    }
    previousNarration = key;
    setState(() {});
  }

  void _narrate() {
    if (!mounted ||
        showingPrivateResult ||
        cinematic != null ||
        actionInProgress ||
        flowInProgress ||
        draining ||
        (cues.isNotEmpty && !g.nightResultPending)) {
      return;
    }
    if (_showDawn) {
      widget.audio.narrateDawn(g.lastDeaths);
      return;
    }
    if (g.awaitingNightConfirmation) {
      widget.audio.narrate('night_done');
      return;
    }
    final key = g.phase == Phase.ended
        ? (g.winner == 'good' ? 'good' : 'wolf')
        : g.phase.name;
    widget.audio.narrate(key);
  }

  @override
  void dispose() {
    g.removeListener(_changed);
    widget.audio.removeListener(_audioChanged);
    focusScroll.dispose();
    historyScroll.dispose();
    discussionSeatsScroll.dispose();
    clock?.cancel();
    widget.audio.stopVoice();
    widget.audio.stopEffect();
    if (cinematicDone != null && !cinematicDone!.isCompleted) {
      cinematicDone!.complete();
    }
    super.dispose();
  }

  Future<void> _showEvent(CinematicEvent event) async {
    if (!mounted) return;
    widget.audio.stopVoice();
    final done = Completer<void>();
    cinematicDone = done;
    setState(() => cinematic = event);
    await done.future;
  }

  void _finishEvent() {
    if (!mounted) return;
    setState(() => cinematic = null);
    final done = cinematicDone;
    cinematicDone = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  Future<void> _drainCues() async {
    if (draining ||
        actionInProgress ||
        flowInProgress ||
        g.nightResultPending ||
        !mounted) {
      return;
    }
    draining = true;
    try {
      while (cues.isNotEmpty && mounted) {
        await _showEvent(cues.removeAt(0));
      }
    } finally {
      draining = false;
    }
  }

  Future<void> _continue() async {
    if (cinematic != null || flowInProgress) return;
    flowInProgress = true;
    if (_showDawn) {
      cues.insertAll(0, [
        for (final id in g.lastDeaths)
          CinematicEvent.forTarget(CinematicKind.out, g, g.player(id)),
      ]);
      g.acknowledgeNightResult();
      if (g.phase != Phase.dawn) {
        flowInProgress = false;
        await _drainCues();
        _narrate();
        return;
      }
    }
    g.continueFlow();
    flowInProgress = false;
    await _drainCues();
    _narrate();
  }

  Future<void> _action({String potion = 'pass', bool skip = false}) async {
    final before = g.phase;
    if (actionInProgress || cinematic != null) return;
    actionInProgress = true;
    final actorRole = g.actor?.role ?? Role.villager;
    actingHunter = before == Phase.hunter ? g.actor?.id : null;
    final targetId = before == Phase.witch && potion == 'save'
        ? g.attack
        : skip
        ? null
        : selected;
    final kind = switch (before) {
      Phase.wolves => CinematicKind.wolfAttack,
      Phase.hunter => CinematicKind.hunterShot,
      Phase.guard => CinematicKind.guard,
      Phase.seer => CinematicKind.reveal,
      Phase.witch =>
        potion == 'save' ? CinematicKind.heal : CinematicKind.poison,
      _ => null,
    };
    final visual = kind != null && targetId != null
        ? CinematicEvent.forTarget(
            kind,
            g,
            g.player(targetId),
            actorRole: actorRole,
          )
        : null;
    showingPrivateResult = before == Phase.seer && !g.local;
    final error = g.act(skip ? null : selected, potion: potion);
    actingHunter = null;
    if (error != null) {
      showingPrivateResult = false;
      actionInProgress = false;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error), backgroundColor: panel));
      return;
    }
    if (visual != null) await _showEvent(visual);
    if (!mounted) return;
    if (before == Phase.seer && !g.local && g.privateResult != null) {
      final result = g.privateResult!;
      // The next local player's private panel stays sealed behind this result.
      await gameDialog(
        context,
        title: '水晶中的真相 · 仅你可见',
        child: Column(
          children: [
            const Icon(Icons.visibility_outlined, color: gold, size: 50),
            const SizedBox(height: 24),
            Text(
              result,
              style: heading(25, color: gold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            const Text(
              '记住这个结果。关闭后，请将设备传回。',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
        actions: [
          GameButton('我已记住', onTap: () => Navigator.pop(context), small: true),
        ],
      );
      g.privateResult = null;
    }
    showingPrivateResult = false;
    actionInProgress = false;
    await _drainCues();
    _narrate();
  }

  Future<void> _exit() async {
    final result = await gameDialog<bool>(
      context,
      title: '暂别月夜',
      child: const Text(
        '当前进度会保存在本机，下次可从「继续旅程」返回这场对局。',
        style: TextStyle(color: muted, fontSize: 13, height: 2),
      ),
      actions: [
        GameButton(
          '保存并返回',
          onTap: () => Navigator.pop(context, true),
          small: true,
        ),
        GameButton(
          '留在村庄',
          onTap: () => Navigator.pop(context, false),
          small: true,
          primary: false,
        ),
      ],
    );
    if (result == true) await widget.onLeave();
  }

  void _showLog() => gameDialog(
    context,
    title: '长夜纪事',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (g.events.isEmpty)
          const Text('月夜才刚刚开始。', style: TextStyle(color: muted)),
        for (final e in g.events.where((e) => !e.secret || !g.local))
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 55,
                  child: Text(
                    '第${e.day}天',
                    style: const TextStyle(color: gold, fontSize: 11),
                  ),
                ),
                Expanded(
                  child: Text(
                    e.text,
                    style: TextStyle(
                      color: e.secret ? const Color(0xFF8EBCCA) : cream,
                      fontSize: 12,
                      height: 1.8,
                    ),
                  ),
                ),
                if (e.secret)
                  const Icon(Icons.lock_outline, size: 13, color: muted),
              ],
            ),
          ),
      ],
    ),
  );

  void _showRelationships() => gameDialog(
    context,
    title: '村庄关系',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '他们记得每一张票。好感只反映相处，不代表真实阵营。\n投他 −12 · 与他同票 +5 · 弃票不变',
          style: TextStyle(color: muted, fontSize: 11, height: 1.9),
        ),
        const SizedBox(height: 20),
        for (final p in g.players.skip(1)) _relationshipRow(p),
      ],
    ),
  );

  Widget _relationshipRow(Player p) {
    final m = g.relationship(p.id)!;
    final color = m.affinity < 0
        ? const Color(0xFFC77368)
        : m.affinity > 0
        ? const Color(0xFF87B5A3)
        : gold;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: .8),
        border: Border(left: BorderSide(color: color, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${p.id}号 · ${p.name}${p.alive ? '' : ' · 已出局'}',
                  style: const TextStyle(color: cream, fontSize: 12),
                ),
              ),
              Text(
                '${m.affinity > 0 ? '+' : ''}${m.affinity}',
                style: heading(18, color: color),
              ),
            ],
          ),
          Text(
            '${m.temperament.label} · ${m.attitude}',
            style: TextStyle(color: color, fontSize: 10),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: (m.affinity + 100) / 200,
              minHeight: 3,
              color: color,
              backgroundColor: line,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            m.changedDay == 0
                ? m.reason
                : '${m.reason} · ${m.lastDelta > 0 ? '+' : ''}${m.lastDelta}',
            style: const TextStyle(color: muted, fontSize: 10, height: 1.8),
          ),
        ],
      ),
    );
  }

  String? get _visibleSpeech =>
      focusedSpeech != null && g.speeches.contains(focusedSpeech)
      ? focusedSpeech
      : g.speeches.firstOrNull;
  int? _speakerId(String? speech) =>
      int.tryParse(RegExp(r'^(\d+)号').firstMatch(speech ?? '')?.group(1) ?? '');
  int? get _readingSpeakerId =>
      followHost && widget.audio.activeNarrationKey == 'discussion'
      ? null
      : _speakerId(_visibleSpeech);
  bool get _hasSpoken => g.speeches.any((s) => s.startsWith('1号 · 你'));
  bool _canPoint(Player p) =>
      !g.local && g.me.alive && p.alive && p.id != g.me.id;

  void _readSpeech(String speech) {
    setState(() {
      focusedSpeech = speech;
      followHost = false;
    });
    if (focusScroll.hasClients) focusScroll.jumpTo(0);
  }

  void _submitSpeech({bool reveal = false}) {
    g.speak(accuse: reveal ? null : selected, reveal: reveal);
    if (g.speeches.isNotEmpty) _readSpeech(g.speeches.first);
  }

  Widget _discussionWorkspace() => LayoutBuilder(
    builder: (context, viewport) {
      final tight = viewport.maxHeight < 460;
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1600),
          child: SizedBox(
            width: double.infinity,
            height: viewport.maxHeight,
            child: Padding(
              padding: EdgeInsets.all(tight ? 8 : 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(g.title, style: heading(tight ? 18 : 22)),
                            Text(
                              '第 ${g.day} 天 · ${g.alive.length}/${g.players.length} 人存活${!g.local && !g.me.alive ? ' · 旁观中' : ''}',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 10,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${(discussionSeconds ~/ 60).toString().padLeft(2, '0')}:${(discussionSeconds % 60).toString().padLeft(2, '0')}',
                        style: heading(
                          tight ? 20 : 24,
                          color: gold,
                          spacing: 1,
                        ),
                      ),
                      IconButton(
                        tooltip: timerRunning ? '暂停计时' : '开始计时',
                        onPressed: _toggleTimer,
                        icon: Icon(
                          timerRunning ? Icons.pause : Icons.play_arrow,
                          color: gold,
                          size: 20,
                        ),
                      ),
                      IconButton(
                        tooltip: '重置计时',
                        onPressed: () {
                          clock?.cancel();
                          setState(() {
                            discussionSeconds = 120;
                            timerRunning = false;
                          });
                        },
                        icon: const Icon(Icons.replay, color: muted, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final parallel =
                            c.maxWidth >= 720 || (c.maxWidth >= 520 && tight);
                        if (parallel) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 6, child: _speechReader()),
                              const SizedBox(width: 12),
                              Expanded(flex: 5, child: _discussionSeats()),
                            ],
                          );
                        }
                        final seatsHeight = (c.maxHeight * .48).clamp(
                          160.0,
                          230.0,
                        );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _speechReader()),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: seatsHeight,
                              child: _discussionSeats(),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  _discussionActions(tight: tight),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _speechReader() => LayoutBuilder(
    builder: (context, c) {
      final history =
          c.maxWidth >= 500 && c.maxHeight >= 450 && g.speeches.isNotEmpty;
      final compactReader = c.maxHeight < 260;
      final speech = _visibleSpeech;
      final index = speech == null ? -1 : g.speeches.indexOf(speech);
      final host =
          followHost && widget.audio.activeNarrationKey == 'discussion';
      final separator = speech?.indexOf('：') ?? -1;
      final speaker = separator < 0 ? '村庄发言' : speech!.substring(0, separator);
      final body = separator < 0 ? speech : speech!.substring(separator + 1);
      return OrnatePanel(
        padding: EdgeInsets.all(compactReader ? 8 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    compactReader ? (host ? '主持播报' : speaker) : '此刻的村庄',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: heading(compactReader ? 14 : 16, spacing: 1),
                  ),
                ),
                if (index >= 0) ...[
                  Text(
                    '${index + 1}/${g.speeches.length}',
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                  SizedBox(
                    width: 36,
                    height: compactReader ? 32 : 40,
                    child: IconButton(
                      key: const ValueKey('speech-previous'),
                      padding: EdgeInsets.zero,
                      tooltip: '上一条发言',
                      onPressed: index > 0
                          ? () => _readSpeech(g.speeches[index - 1])
                          : null,
                      icon: const Icon(
                        Icons.chevron_left,
                        color: gold,
                        size: 22,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    height: compactReader ? 32 : 40,
                    child: IconButton(
                      key: const ValueKey('speech-next'),
                      padding: EdgeInsets.zero,
                      tooltip: '下一条发言',
                      onPressed: index + 1 < g.speeches.length
                          ? () => _readSpeech(g.speeches[index + 1])
                          : null,
                      icon: const Icon(
                        Icons.chevron_right,
                        color: gold,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: history ? 6 : 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: gold.withValues(alpha: .065),
                  border: Border(
                    left: BorderSide(
                      color: host ? gold : const Color(0xFF8EBCCA),
                      width: 3,
                    ),
                  ),
                ),
                child: Scrollbar(
                  controller: focusScroll,
                  child: SingleChildScrollView(
                    key: const ValueKey('speech-focus-scroll'),
                    controller: focusScroll,
                    padding: EdgeInsets.all(compactReader ? 8 : 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!compactReader)
                          Row(
                            children: [
                              Icon(
                                host
                                    ? Icons.volume_up_outlined
                                    : Icons.chat_bubble_outline,
                                size: 17,
                                color: gold,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  host
                                      ? '主持播报'
                                      : g.local
                                      ? '围炉讨论'
                                      : speaker,
                                  style: heading(16, color: gold, spacing: 1),
                                ),
                              ),
                            ],
                          ),
                        if (!compactReader) const SizedBox(height: 12),
                        Text(
                          host
                              ? widget.audio.activeNarrationText ??
                                    g.instruction
                              : body ?? g.instruction,
                          key: const ValueKey('speech-focus-text'),
                          style: TextStyle(
                            color: cream,
                            fontSize: c.maxWidth >= 500 ? 19 : 16,
                            height: 1.85,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (history) ...[
              const SizedBox(height: 14),
              const Text(
                '发言记录 · 点击切换阅读',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Expanded(
                flex: 4,
                child: Scrollbar(
                  controller: historyScroll,
                  child: ListView.separated(
                    key: const ValueKey('speech-history'),
                    controller: historyScroll,
                    itemCount: g.speeches.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final current = g.speeches[i];
                      final active = current == speech && !host;
                      return Material(
                        color: active
                            ? gold.withValues(alpha: .09)
                            : ink.withValues(alpha: .7),
                        child: InkWell(
                          key: ValueKey('speech-record-${_speakerId(current)}'),
                          onTap: () => _readSpeech(current),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              current,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: active ? gold : cream,
                                fontSize: 13,
                                height: 1.7,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );

  Widget _discussionSeats() => OrnatePanel(
    padding: const EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('村庄席位', style: heading(16, spacing: 1))),
            if (!g.local) ...[
              Text(
                identityVisible ? g.me.role.title : '身份隐藏',
                style: const TextStyle(color: muted, fontSize: 10),
              ),
              SizedBox(
                width: 32,
                height: 36,
                child: IconButton(
                  tooltip: '显示或隐藏身份',
                  padding: EdgeInsets.zero,
                  onPressed: () =>
                      setState(() => identityVisible = !identityVisible),
                  icon: Icon(
                    identityVisible
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: muted,
                    size: 16,
                  ),
                ),
              ),
              SizedBox(
                width: 32,
                height: 36,
                child: IconButton(
                  tooltip: '村庄关系',
                  padding: EdgeInsets.zero,
                  onPressed: _showRelationships,
                  icon: const Icon(
                    Icons.favorite_border,
                    color: gold,
                    size: 16,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final dense = c.maxHeight < 300;
              final cols = dense
                  ? (c.maxWidth >= 330 && c.maxHeight < 160
                        ? 6
                        : c.maxWidth >= 250
                        ? 4
                        : 3)
                  : (c.maxWidth >= 620
                        ? 6
                        : c.maxWidth >= 370
                        ? 4
                        : 3);
              final rows = (g.players.length / cols).ceil();
              final available = (c.maxHeight - 8 * (rows - 1)) / rows;
              final height = available.clamp(
                dense ? 52.0 : 110.0,
                dense ? 76.0 : 240.0,
              );
              return GridView.builder(
                key: const ValueKey('discussion-seats'),
                controller: discussionSeatsScroll,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  mainAxisExtent: height,
                ),
                itemCount: g.players.length,
                itemBuilder: (_, i) => dense
                    ? _discussionSeatChip(g.players[i])
                    : _seat(g.players[i]),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _discussionSeatChip(Player p) {
    final chosen = selected == p.id;
    final reading = _readingSpeakerId == p.id;
    final wolf = !g.local && g.me.role.isWolf && p.role.isWolf;
    final self = !g.local && p.id == g.me.id;
    final color = chosen
        ? gold
        : reading
        ? const Color(0xFF8EBCCA)
        : line;
    return Semantics(
      button: _canPoint(p),
      selected: chosen,
      label: '${p.id}号 ${p.name} ${p.alive ? '存活' : '已出局'}',
      child: Material(
        color: chosen
            ? gold.withValues(alpha: .13)
            : ink.withValues(alpha: .75),
        child: InkWell(
          key: ValueKey('seat-${p.id}'),
          onTap: _canPoint(p)
              ? () => setState(() => selected = chosen ? null : p.id)
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            decoration: BoxDecoration(
              border: Border.all(color: color, width: chosen ? 2 : 1),
            ),
            child: Opacity(
              opacity: p.alive ? 1 : .4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        '${p.id}',
                        style: TextStyle(
                          color: chosen ? gold : cream,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          self ? '你' : p.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: cream,
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                      ),
                      if (chosen)
                        const Icon(Icons.check, size: 12, color: gold),
                    ],
                  ),
                  Text(
                    !p.alive
                        ? '已出局'
                        : self && identityVisible
                        ? p.role.title
                        : wolf
                        ? '狼队同伴'
                        : reading
                        ? '正在查看'
                        : '身份未知',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: reading ? const Color(0xFF8EBCCA) : muted,
                      fontSize: 9,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _discussionActions({required bool tight}) => LayoutBuilder(
    builder: (context, c) {
      final inline = c.maxWidth >= 700 || (tight && c.maxWidth >= 500);
      final reveal =
          !g.local &&
          g.me.alive &&
          !_hasSpoken &&
          g.me.role == Role.seer &&
          g.checks.isNotEmpty;
      final status = Text(
        g.local
            ? '依座次自由讨论，结束后进入秘密投票'
            : _hasSpoken
            ? '你的发言已记录'
            : !g.me.alive
            ? '你已出局，本轮仅可旁观'
            : selected == null
            ? '点击席位选择指认目标，也可以观望'
            : '已选 $selected 号 · ${g.player(selected!).name}',
        key: const ValueKey('discussion-selection'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: gold, fontSize: 11, height: 1.6),
      );
      final submit = GameButton(
        _hasSpoken
            ? '发言已记录'
            : selected == null
            ? '谨慎观望'
            : '指认 $selected 号',
        key: const ValueKey('discussion-submit'),
        onTap: g.me.alive && !_hasSpoken ? _submitSpeech : null,
        primary: false,
        small: true,
        width: double.infinity,
      );
      final next = GameButton(
        inline
            ? (!g.local && !g.me.alive ? '结束发言 · 观看投票' : '结束发言 · 开始投票')
            : !g.local && !g.me.alive
            ? '观看投票'
            : '开始投票',
        key: const ValueKey('discussion-continue'),
        onTap: _continue,
        small: true,
        width: double.infinity,
      );
      final more = PopupMenuButton<String>(
        tooltip: '更多发言方式',
        icon: const Icon(Icons.more_horiz, color: gold, size: 20),
        onSelected: (_) => _submitSpeech(reveal: true),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'reveal', child: Text('公开我的查验')),
        ],
      );
      return OrnatePanel(
        padding: const EdgeInsets.all(8),
        child: inline
            ? Row(
                children: [
                  Expanded(child: status),
                  if (!g.local) ...[
                    const SizedBox(width: 12),
                    SizedBox(width: tight ? 128 : 160, child: submit),
                  ],
                  if (reveal) SizedBox(width: 40, child: more),
                  const SizedBox(width: 8),
                  SizedBox(width: tight ? 210 : 240, child: next),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  status,
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (!g.local) ...[
                        Expanded(child: submit),
                        const SizedBox(width: 8),
                      ],
                      if (reveal) SizedBox(width: 36, child: more),
                      Expanded(child: next),
                    ],
                  ),
                ],
              ),
      );
    },
  );

  void _toggleTimer() {
    if (timerRunning) {
      clock?.cancel();
      setState(() => timerRunning = false);
      return;
    }
    setState(() => timerRunning = true);
    clock = Timer.periodic(const Duration(seconds: 1), (t) {
      if (discussionSeconds <= 0) {
        t.cancel();
        setState(() => timerRunning = false);
      } else {
        setState(() => discussionSeconds--);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1100;
    final sealed = _private && !revealed;
    Widget content;
    if (_showDawn) {
      content = _dawnAnnouncement(width);
    } else if (sealed) {
      content = _privacyGate();
    } else if (g.awaitingNightConfirmation) {
      content = _nightConfirmation(width);
    } else if (g.phase == Phase.discussion) {
      content = _discussionWorkspace();
    } else {
      final stage = g.phase == Phase.deal
          ? _deal()
          : g.phase == Phase.ended
          ? _ending(width)
          : Column(
              children: [
                _phaseBanner(width),
                const SizedBox(height: 24),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 238, child: _identity()),
                      const SizedBox(width: 24),
                      Expanded(child: _board(width)),
                      const SizedBox(width: 24),
                      SizedBox(width: 310, child: _controls()),
                    ],
                  )
                else ...[
                  if (!g.local || g.actor != null) _compactIdentity(),
                  const SizedBox(height: 18),
                  if (g.isAction) ...[
                    _controls(docked: true),
                    const SizedBox(height: 18),
                  ],
                  _board(width),
                  if (!g.isAction) ...[const SizedBox(height: 20), _controls()],
                ],
                const SizedBox(height: 20),
                _timeline(),
              ],
            );
      content = SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1600),
            child: Padding(
              padding: EdgeInsets.all(wide ? 32 : 18),
              child: stage,
            ),
          ),
        ),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _exit();
        }
      },
      child: Scaffold(
        bottomNavigationBar:
            cinematic == null &&
                !wide &&
                g.isAction &&
                !sealed &&
                !_showDawn &&
                !g.awaitingNightConfirmation
            ? _mobileActions()
            : null,
        body: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: .18,
                child: const Art('assets/images/village.png'),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [ink.withValues(alpha: .3), ink],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _header(width),
                  Expanded(child: content),
                ],
              ),
            ),
            if (cinematic != null)
              Positioned.fill(
                child: CinematicOverlay(
                  key: ObjectKey(cinematic),
                  event: cinematic!,
                  audio: widget.audio,
                  onComplete: _finishEvent,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _announcementFrame(Widget child) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: OrnatePanel(
                padding: const EdgeInsets.all(28),
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _dawnAnnouncement(double width) {
    final landscape = MediaQuery.sizeOf(context).height < 600;
    final headline = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('第 ${g.day} 夜 · 村庄公告', style: caption(color: gold, size: 12)),
        SizedBox(height: landscape ? 12 : 24),
        Icon(
          Icons.wb_sunny_outlined,
          color: gold,
          size: landscape
              ? 40
              : width > 600
              ? 64
              : 48,
        ),
        SizedBox(height: landscape ? 12 : 22),
        Text(
          '天亮了',
          style: heading(
            landscape
                ? 34
                : width > 600
                ? 52
                : 36,
            spacing: 6,
          ),
        ),
      ],
    );
    final result = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (g.lastDeaths.isEmpty)
          Text(
            '昨夜平安夜',
            style: heading(
              landscape
                  ? 32
                  : width > 600
                  ? 56
                  : 34,
              color: gold,
              spacing: 3,
            ),
            textAlign: TextAlign.center,
          )
        else ...[
          Text('昨夜出局', style: heading(landscape ? 18 : 22, color: muted)),
          SizedBox(height: landscape ? 8 : 16),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final id in g.lastDeaths)
                Text(
                  '$id 号',
                  style: heading(
                    landscape
                        ? 36
                        : width > 600
                        ? 64
                        : 42,
                    color: const Color(0xFFC77368),
                    spacing: 2,
                  ),
                ),
            ],
          ),
          SizedBox(height: landscape ? 8 : 18),
          const Text(
            '出局玩家请保持旁观，不再参与发言和投票。',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 13, height: 1.8),
          ),
        ],
        SizedBox(height: landscape ? 14 : 30),
        if (!g.local && !g.me.alive && !landscape)
          const Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: Tag('你已出局 · 继续旁观', color: Color(0xFFC77368)),
          ),
        GameButton(
          g.phase == Phase.hunter
              ? '进入猎人行动'
              : g.phase == Phase.ended
              ? '查看终局'
              : '开始白天发言',
          onTap: _continue,
          width: 280,
        ),
      ],
    );
    return _announcementFrame(
      landscape
          ? Row(
              key: const ValueKey('night-result'),
              children: [
                Expanded(child: headline),
                const SizedBox(width: 24),
                Expanded(child: result),
              ],
            )
          : Column(
              key: const ValueKey('night-result'),
              children: [headline, const SizedBox(height: 30), result],
            ),
    );
  }

  Widget _nightConfirmation(double width) => _announcementFrame(
    Column(
      children: [
        const Icon(Icons.lock_outline, color: gold, size: 46),
        const SizedBox(height: 24),
        Text(
          '${g.actor!.role.title} · 行动已记录',
          style: heading(width > 600 ? 30 : 23, color: gold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (g.phase == Phase.seer && g.privateResult != null) ...[
          Text('水晶中的真相 · 仅你可见', style: caption(size: 11)),
          const SizedBox(height: 16),
          Text(
            g.privateResult!,
            style: heading(28),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
        ],
        const Text(
          '请确认你已完成行动并记住结果。\n确认后闭眼，将设备交回，再由下一角色睁眼。',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 14, height: 2),
        ),
        const SizedBox(height: 30),
        GameButton('确认行动完成 · 闭眼', onTap: g.confirmNightAction, width: 300),
      ],
    ),
  );

  Widget _mobileActions() => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      decoration: BoxDecoration(
        color: ink,
        border: Border(top: BorderSide(color: gold.withValues(alpha: .4))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            selected == null
                ? g.phase == Phase.vote && !g.local && !g.me.alive
                      ? '你已出局 · 本轮仅旁观'
                      : '请在席位中选择目标'
                : '已选择 $selected 号 · ${g.player(selected!).name}',
            style: const TextStyle(color: gold, fontSize: 11),
          ),
          const SizedBox(height: 10),
          if (g.phase == Phase.witch)
            Row(
              children: [
                Expanded(
                  child: GameButton(
                    '解药',
                    onTap: g.canSave
                        ? () => _action(potion: 'save', skip: true)
                        : null,
                    small: true,
                    primary: false,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GameButton(
                    '毒药',
                    onTap: g.toxin && selected != null ? _confirmPoison : null,
                    small: true,
                    primary: false,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GameButton(
                    '不用药',
                    onTap: () => _action(skip: true),
                    small: true,
                  ),
                ),
              ],
            )
          else if (g.phase == Phase.vote && !g.local && !g.me.alive)
            GameButton(
              '查看投票结果',
              onTap: _continue,
              small: true,
              width: double.infinity,
            )
          else
            Row(
              children: [
                Expanded(
                  child: GameButton(
                    switch (g.phase) {
                      Phase.guard => '确认守护',
                      Phase.wolves => '确认袭击',
                      Phase.seer => '查验身份',
                      Phase.hunter => '发动技能',
                      _ => '确认投票',
                    },
                    onTap: selected == null ? null : () => _action(),
                    small: true,
                  ),
                ),
                if ([
                  Phase.guard,
                  Phase.vote,
                  Phase.hunter,
                ].contains(g.phase)) ...[
                  const SizedBox(width: 10),
                  GameButton(
                    g.phase == Phase.vote
                        ? '弃票'
                        : g.phase == Phase.hunter
                        ? '不开枪'
                        : '空守',
                    onTap: () => _action(skip: true),
                    primary: false,
                    small: true,
                  ),
                ],
              ],
            ),
        ],
      ),
    ),
  );

  Widget _header(double width) => Container(
    padding: EdgeInsets.symmetric(horizontal: width > 800 ? 32 : 12),
    height: 72,
    decoration: BoxDecoration(
      color: ink.withValues(alpha: .8),
      border: Border(bottom: BorderSide(color: gold.withValues(alpha: .18))),
    ),
    child: Row(
      children: [
        IconButton(
          tooltip: '保存并返回',
          onPressed: _exit,
          icon: const Icon(Icons.arrow_back, color: gold, size: 20),
        ),
        const SizedBox(width: 8),
        if (width >= 400) const MoonLogo(size: 32),
        const SizedBox(width: 12),
        Text('月隐', style: heading(22, color: gold)),
        const Spacer(),
        if (width > 600) Tag('${g.players.length} 人${g.local ? '聚会' : '历练'}'),
        const SizedBox(width: 12),
        IconButton(
          tooltip: '对局记录',
          onPressed: _showLog,
          icon: const Icon(Icons.menu_book_outlined, color: muted, size: 20),
        ),
        IconButton(
          tooltip: '重播主持语音',
          onPressed: _narrate,
          icon: const Icon(
            Icons.record_voice_over_outlined,
            color: muted,
            size: 20,
          ),
        ),
        IconButton(
          tooltip: '声音设置',
          onPressed: widget.onSettings,
          icon: const Icon(Icons.tune_rounded, color: muted, size: 20),
        ),
      ],
    ),
  );
  Widget _privacyGate() => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: OrnatePanel(
            padding: const EdgeInsets.all(36),
            child: Column(
              children: [
                const MoonLogo(size: 94),
                const SizedBox(height: 24),
                Text(
                  g.phase == Phase.deal
                      ? '命运密封信'
                      : g.phase == Phase.vote
                      ? '秘密投票'
                      : '夜间密令',
                  style: heading(30),
                ),
                const SizedBox(height: 14),
                Text(
                  g.phase == Phase.deal
                      ? '请将设备交给 ${g.dealIndex + 1} 号玩家'
                      : g.phase == Phase.vote
                      ? '请将设备交给 ${g.actor?.id} 号玩家'
                      : g.title,
                  style: heading(18, color: gold, spacing: 1),
                ),
                const SizedBox(height: 18),
                Text(
                  g.isNight
                      ? '其他玩家请闭眼。\n仅当前行动角色独自查看并操作。'
                      : '其他玩家请移开视线。\n确保只有当前玩家能看见屏幕。',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: muted, fontSize: 13, height: 2),
                ),
                const SizedBox(height: 32),
                GameButton(
                  '独自查看',
                  onTap: () => setState(() => revealed = true),
                  icon: Icons.lock_open_outlined,
                  width: 240,
                ),
                const SizedBox(height: 18),
                Text('PRIVATE · FOR YOUR EYES ONLY', style: caption(size: 9)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Widget _deal() {
    final p = g.local ? g.actor! : g.me;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: Column(
          children: [
            Text(
              g.local ? '${p.id}号玩家，你的命运是' : '旅人，你的命运是',
              style: caption(color: gold, size: 12),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: 265,
              height: 375,
              child: RoleCard(
                p.role,
                width: 265,
                height: 375,
                onTap: () => widget.audio.narrate('${p.role.name}_lore'),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              p.role.flavor,
              textAlign: TextAlign.center,
              style: heading(18, color: gold, spacing: 1),
            ),
            const SizedBox(height: 20),
            Text(
              p.role.description,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 12, height: 2),
            ),
            const SizedBox(height: 16),
            if (p.role.isWolf)
              Tag('狼队成员：${g.wolves.map((p) => '${p.id}号').join('、')}'),
            const SizedBox(height: 24),
            GameButton(
              g.local
                  ? (g.dealIndex < g.players.length - 1
                        ? '隐藏身份 · 传给下一位'
                        : '隐藏身份 · 进入黑夜')
                  : '铭记使命 · 进入黑夜',
              onTap: _continue,
              width: 300,
            ),
            const SizedBox(height: 22),
          ],
        ),
      ),
    );
  }

  Widget _phaseBanner(double width) => Column(
    children: [
      Text(
        'CHAPTER ${g.day.toString().padLeft(2, '0')}  /  ${g.isNight ? 'THE NIGHT' : 'THE DAY'}',
        style: caption(color: gold, size: 10),
      ),
      const SizedBox(height: 8),
      Text(
        g.title,
        style: heading(width > 600 ? 32 : 26, spacing: 4),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          Tag('第 ${g.day} ${g.isNight ? '夜' : '天'}'),
          Tag(
            '${g.alive.length} / ${g.players.length} 人存活',
            color: const Color(0xFF87B5A3),
          ),
          if (!g.local && !g.me.alive)
            const Tag('你已出局 · 旁观中', color: Color(0xFFC77368)),
        ],
      ),
    ],
  );
  Player? get _identityPlayer => g.local ? g.actor : g.me;
  Widget _identity() {
    final p = _identityPlayer;
    if (p == null) {
      return OrnatePanel(
        child: Column(
          children: [
            const MoonLogo(size: 90),
            const SizedBox(height: 20),
            Text('村庄见证者', style: heading(20)),
            const SizedBox(height: 14),
            const Text(
              '关注每一位玩家的发言，\n让真相逐渐浮出水面。',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12, height: 2),
            ),
          ],
        ),
      );
    }
    return OrnatePanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('你的身份', style: caption(size: 10, color: gold)),
              const Spacer(),
              IconButton(
                tooltip: identityVisible ? '隐藏身份' : '显示身份',
                onPressed: () =>
                    setState(() => identityVisible = !identityVisible),
                icon: Icon(
                  identityVisible
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 16,
                  color: muted,
                ),
              ),
            ],
          ),
          SizedBox(
            height: 280,
            width: double.infinity,
            child: identityVisible
                ? Art(p.role.asset, alignment: Alignment.topCenter)
                : const Center(child: MoonLogo(size: 100)),
          ),
          const SizedBox(height: 18),
          Text(identityVisible ? p.role.title : '身份已隐藏', style: heading(24)),
          const SizedBox(height: 8),
          if (identityVisible) ...[
            Tag(p.role.camp, color: p.role.color),
            const SizedBox(height: 16),
            Text(
              p.role.description,
              style: const TextStyle(color: muted, fontSize: 11, height: 1.9),
            ),
            if (p.role == Role.seer && g.checks.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('你的查验', style: caption(color: gold, size: 9)),
              for (final e in g.checks.entries)
                Text(
                  '${e.key}号 · ${e.value ? '狼人' : '好人'}',
                  style: TextStyle(
                    color: e.value
                        ? const Color(0xFFC77368)
                        : const Color(0xFF87B5A3),
                    fontSize: 12,
                    height: 2,
                  ),
                ),
            ],
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _compactIdentity() {
    final p = _identityPlayer;
    if (p == null) return const SizedBox.shrink();
    return OrnatePanel(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            height: 72,
            child: identityVisible
                ? Art(p.role.asset, alignment: Alignment.topCenter)
                : const MoonLogo(),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  identityVisible
                      ? '${p.role.title} · ${p.role.skill}'
                      : '身份已隐藏',
                  style: heading(16),
                ),
                Text(
                  identityVisible ? '${p.id}号 · ${p.role.camp}' : '仅你可见',
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
                if (identityVisible &&
                    p.role == Role.seer &&
                    g.checks.isNotEmpty)
                  Text(
                    g.checks.entries
                        .map((e) => '${e.key}号 ${e.value ? '狼' : '好'}')
                        .join('  '),
                    style: const TextStyle(color: gold, fontSize: 10),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: '显示或隐藏身份',
            onPressed: () => setState(() => identityVisible = !identityVisible),
            icon: Icon(
              identityVisible
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: muted,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _board(double width) => OrnatePanel(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('村庄席位', style: heading(18)),
            const Spacer(),
            if (!g.local)
              IconButton(
                tooltip: '村庄关系',
                onPressed: _showRelationships,
                icon: const Icon(Icons.favorite_border, color: gold, size: 18),
              ),
            Text(
              g.isAction ? '点击选择目标' : '观察与倾听',
              style: const TextStyle(color: muted, fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 650
                ? 6
                : c.maxWidth >= 300
                ? 4
                : 3;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: g.players.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: 10,
                mainAxisSpacing: 12,
                childAspectRatio: .81,
              ),
              itemBuilder: (_, i) => _seat(g.players[i]),
            );
          },
        ),
      ],
    ),
  );
  Widget _seat(Player p) {
    final canSelect = g.isAction
        ? g.canAct && g.targets.any((o) => o.id == p.id)
        : g.phase == Phase.discussion &&
              g.me.alive &&
              p.alive &&
              p.id != g.me.id &&
              !g.local;
    final chosen = selected == p.id;
    final reading = g.phase == Phase.discussion && _readingSpeakerId == p.id;
    final knownSelf = !g.local && p.id == g.me.id;
    final knownWolf = !g.local && g.me.role.isWolf && p.role.isWolf;
    final publicHunter = g.events.any((e) => e.text == '${p.id} 号亮出猎人身份。');
    final show = knownSelf || knownWolf || publicHunter;
    return Semantics(
      button: canSelect,
      label: '${p.id}号 ${p.name} ${p.alive ? '存活' : '已出局'}',
      selected: chosen,
      child: InkWell(
        key: ValueKey('seat-${p.id}'),
        onTap: canSelect
            ? () => setState(() => selected = chosen ? null : p.id)
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: chosen
                ? gold.withValues(alpha: .12)
                : ink.withValues(alpha: .7),
            border: Border.all(
              color: chosen
                  ? gold
                  : reading
                  ? const Color(0xFF8EBCCA)
                  : line.withValues(alpha: p.alive ? .8 : .3),
              width: chosen ? 1.5 : 1,
            ),
          ),
          child: Opacity(
            opacity: p.alive ? 1 : .38,
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Art(
                        show ? p.role.asset : Role.villager.asset,
                        alignment: const Alignment(0, -.5),
                      ),
                      if (!show) ColoredBox(color: ink.withValues(alpha: .38)),
                      Positioned(
                        top: 5,
                        left: 6,
                        child: Text(
                          p.id.toString().padLeft(2, '0'),
                          style: const TextStyle(
                            color: gold,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (chosen)
                        const Positioned(
                          right: 5,
                          top: 5,
                          child: Icon(
                            Icons.check_circle,
                            color: gold,
                            size: 17,
                          ),
                        ),
                      if (!g.local && p.id != g.me.id)
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Tooltip(
                            message:
                                '${g.relationship(p.id)!.temperament.label} · ${g.relationship(p.id)!.attitude}\n${g.relationship(p.id)!.reason}',
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              color: ink.withValues(alpha: .85),
                              child: Text(
                                '♡ ${g.relationship(p.id)!.affinity > 0 ? '+' : ''}${g.relationship(p.id)!.affinity}',
                                style: TextStyle(
                                  fontSize: 8,
                                  color: g.relationship(p.id)!.affinity < 0
                                      ? const Color(0xFFC77368)
                                      : gold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (!p.alive)
                        const Center(
                          child: Icon(
                            Icons.close_rounded,
                            color: cream,
                            size: 35,
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 7, 4, 7),
                  child: Column(
                    children: [
                      Text(
                        knownSelf ? '你 · ${p.name}' : p.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: cream, fontSize: 10),
                      ),
                      Text(
                        !p.alive
                            ? '已出局'
                            : knownSelf || publicHunter
                            ? p.role.title
                            : knownWolf
                            ? '狼队同伴'
                            : '身份未知',
                        style: TextStyle(
                          fontSize: 8,
                          color: knownWolf ? const Color(0xFFC77368) : muted,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls({bool docked = false}) => OrnatePanel(
    padding: const EdgeInsets.all(22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              g.isNight
                  ? Icons.nightlight_round
                  : g.phase == Phase.vote
                  ? Icons.how_to_vote_outlined
                  : Icons.wb_sunny_outlined,
              color: gold,
              size: 22,
            ),
            const SizedBox(width: 12),
            Text(
              g.isNight
                  ? '夜间行动'
                  : g.phase == Phase.vote
                  ? '做出抉择'
                  : '此刻的村庄',
              style: heading(18),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          g.instruction,
          style: TextStyle(color: muted, fontSize: 12, height: 2),
        ),
        if (docked && g.phase == Phase.witch) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              Tag(g.antidote ? '解药 · 1' : '解药已用'),
              Tag(g.toxin ? '毒药 · 1' : '毒药已用'),
            ],
          ),
        ],
        if (!docked) const SizedBox(height: 22),
        if (g.isAction && !docked) ...[
          if (selected != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: gold.withValues(alpha: .07),
              child: Text(
                '已选择：$selected 号 · ${g.player(selected!).name}',
                style: const TextStyle(color: gold, fontSize: 12),
              ),
            ),
          if (selected != null) const SizedBox(height: 18),
          ..._actionButtons(),
        ] else if (!g.isAction) ...[
          if (g.lastVote.isNotEmpty && g.phase == Phase.night) ...[
            Text('上一轮投票', style: caption(color: gold, size: 9)),
            const SizedBox(height: 10),
            Text(
              g.lastVote,
              style: const TextStyle(color: muted, fontSize: 10, height: 1.9),
            ),
            const SizedBox(height: 20),
          ],
          GameButton(
            switch (g.phase) {
              Phase.night => g.local ? '开始夜间行动' : '进入夜间行动',
              Phase.dawn => '开始白天发言',
              _ => '继续',
            },
            onTap: _continue,
            width: double.infinity,
          ),
        ],
        if (g.local && g.isAction) ...[
          const SizedBox(height: 18),
          const Row(
            children: [
              Icon(Icons.lock_outline, color: muted, size: 12),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  '提交后确认行动完成并闭眼，才能交给下一角色',
                  style: TextStyle(color: muted, fontSize: 9),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
  List<Widget> _actionButtons() {
    if (g.phase == Phase.witch) {
      return [
        Row(
          children: [
            Expanded(
              child: Tag(
                g.antidote ? '解药 · 1' : '解药 · 已用',
                color: const Color(0xFF87B5A3),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Tag(
                g.toxin ? '毒药 · 1' : '毒药 · 已用',
                color: const Color(0xFFC77368),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        GameButton(
          '使用解药${g.canSave ? ' · 救 ${g.attack}号' : ''}',
          onTap: g.canSave ? () => _action(potion: 'save', skip: true) : null,
          primary: false,
          width: double.infinity,
          icon: Icons.healing,
        ),
        const SizedBox(height: 12),
        GameButton(
          '使用毒药',
          onTap: g.toxin && selected != null ? () => _confirmPoison() : null,
          primary: false,
          width: double.infinity,
          icon: Icons.science_outlined,
        ),
        const SizedBox(height: 12),
        GameButton(
          '今夜不使用药剂',
          onTap: () => _action(skip: true),
          width: double.infinity,
        ),
      ];
    }
    if (g.phase == Phase.vote && !g.local && !g.me.alive) {
      return [GameButton('查看投票结果', onTap: _continue, width: double.infinity)];
    }
    return [
      GameButton(
        switch (g.phase) {
          Phase.guard => '确认守护',
          Phase.wolves => '确认袭击',
          Phase.seer => '查验身份',
          Phase.hunter => '发动最后一枪',
          _ => '确认放逐投票',
        },
        onTap: selected == null ? null : () => _action(),
        width: double.infinity,
      ),
      if ([Phase.guard, Phase.vote, Phase.hunter].contains(g.phase)) ...[
        const SizedBox(height: 12),
        GameButton(
          switch (g.phase) {
            Phase.guard => '今夜不守护',
            Phase.hunter => '选择不开枪',
            _ => '弃票',
          },
          onTap: () => _action(skip: true),
          primary: false,
          width: double.infinity,
        ),
      ],
    ];
  }

  Future<void> _confirmPoison() async {
    final result = await gameDialog<bool>(
      context,
      title: '使用毒药',
      child: Text(
        '将毒药用于 $selected 号玩家？\n毒药全局只能使用一次，且本夜不能再使用解药。',
        style: const TextStyle(color: muted, fontSize: 13, height: 2),
      ),
      actions: [
        GameButton(
          '确定使用',
          onTap: () => Navigator.pop(context, true),
          small: true,
        ),
        GameButton(
          '再想一想',
          onTap: () => Navigator.pop(context, false),
          primary: false,
          small: true,
        ),
      ],
    );
    if (result == true) _action(potion: 'poison');
  }

  Widget _timeline() => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 12,
    runSpacing: 8,
    children: [
      for (final entry in [
        (Phase.night, '夜幕'),
        (Phase.dawn, '黎明'),
        (Phase.discussion, '议事'),
        (Phase.vote, '放逐'),
      ])
        Text(
          entry.$2,
          style: TextStyle(
            color: (g.isNight && entry.$1 == Phase.night) || g.phase == entry.$1
                ? gold
                : muted.withValues(alpha: .45),
            fontSize: 11,
            letterSpacing: 3,
          ),
        ),
      Text(
        '·  第 ${g.day} 轮',
        style: const TextStyle(color: muted, fontSize: 10),
      ),
    ],
  );
  Widget _ending(double width) => Column(
    children: [
      const SizedBox(height: 20),
      Icon(
        g.winner == 'good' ? Icons.wb_sunny_outlined : Icons.nightlight_round,
        color: gold,
        size: 64,
      ),
      const SizedBox(height: 18),
      Text(g.title, style: heading(42, color: gold, spacing: 6)),
      const SizedBox(height: 10),
      Text(g.winner == 'good' ? '好人阵营获胜' : '狼人阵营获胜', style: heading(20)),
      const SizedBox(height: 18),
      Text(
        g.instruction,
        textAlign: TextAlign.center,
        style: const TextStyle(color: muted, fontSize: 13),
      ),
      const SizedBox(height: 32),
      LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth > 1000
              ? 6
              : c.maxWidth > 600
              ? 4
              : 3;
          final w = (c.maxWidth - 16 * (cols - 1)) / cols;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final p in g.players)
                SizedBox(
                  width: w,
                  child: Column(
                    children: [
                      RoleCard(
                        p.role,
                        width: w,
                        height: w * 1.35,
                        onTap: () => _showFinalRole(p),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${p.id}号 · ${p.name}',
                        style: const TextStyle(color: cream, fontSize: 11),
                      ),
                      Text(
                        p.alive ? '幸存' : '已出局',
                        style: TextStyle(
                          color: p.alive ? const Color(0xFF87B5A3) : muted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 34),
      Wrap(
        spacing: 16,
        runSpacing: 12,
        alignment: WrapAlignment.center,
        children: [
          GameButton('再赴长夜', onTap: widget.onRestart, width: 200),
          GameButton('回到村庄', onTap: widget.onLeave, width: 200, primary: false),
          GameButton('回看长夜纪事', onTap: _showLog, primary: false, width: 220),
        ],
      ),
      const SizedBox(height: 26),
    ],
  );
  void _showFinalRole(Player p) => gameDialog(
    context,
    title: '${p.id}号 · ${p.role.title}',
    child: Column(
      children: [
        SizedBox(height: 300, child: Art(p.role.asset, fit: BoxFit.contain)),
        const SizedBox(height: 18),
        Text(
          p.role.description,
          style: const TextStyle(color: muted, fontSize: 12, height: 2),
        ),
      ],
    ),
  );
}
