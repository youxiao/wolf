import 'dart:math';

import 'package:flutter/foundation.dart';

import 'roles.dart';
import 'ai_personality.dart';

enum Phase {
  deal,
  night,
  guard,
  wolves,
  seer,
  witch,
  dawn,
  discussion,
  vote,
  hunter,
  ended,
}

enum WinRule { border, parity }

extension WinRuleInfo on WinRule {
  String get title => switch (this) {
    WinRule.border => '经典屠边',
    WinRule.parity => '人数制（狼人 ≥ 好人）',
  };

  String get description => switch (this) {
    WinRule.border => '消灭全部村民或全部神职，狼人获胜。',
    WinRule.parity => '存活狼人数量达到或超过存活好人数量，狼人获胜。',
  };
}

class Player {
  final int id;
  final String name;
  final Role role;
  bool alive;
  Player(this.id, this.name, this.role, {this.alive = true});
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'role': role.name,
    'alive': alive,
  };
  factory Player.fromJson(Map<String, dynamic> j) => Player(
    j['id'],
    j['name'],
    Role.values.byName(j['role']),
    alive: j['alive'],
  );
}

class GameEvent {
  final String text;
  final int day;
  final bool secret;
  final String? kind;
  final int? actorId, targetId;
  GameEvent(
    this.text,
    this.day, {
    this.secret = false,
    this.kind,
    this.actorId,
    this.targetId,
  });
  Map<String, dynamic> toJson() => {
    'text': text,
    'day': day,
    'secret': secret,
    'kind': kind,
    'actorId': actorId,
    'targetId': targetId,
  };
  factory GameEvent.fromJson(Map<String, dynamic> j) => GameEvent(
    j['text'],
    j['day'],
    secret: j['secret'],
    kind: j['kind'],
    actorId: j['actorId'],
    targetId: j['targetId'],
  );
}

/// The engine owns rules and validation. UI never resolves skills or votes.
class GameEngine extends ChangeNotifier {
  final bool local;
  final WinRule winRule;
  final Random random;
  final List<Player> players;
  final List<GameEvent> events = [];
  final Map<int, bool> checks = {};
  final Map<int, Map<int, bool>> botChecks = {};
  final Map<int, double> suspicion = {};
  final Map<int, int?> votes = {};
  final Map<int, AiMemory> relationships = {};
  final List<VoteMemory> voteHistory = [];
  final Map<int, int?> announcedVotes = {};
  Phase phase = Phase.deal;
  int day = 1;
  int dealIndex = 0;
  int voteIndex = 0;
  int nightIndex = -1;
  int? attack;
  int? protected;
  int? lastProtected;
  int? poison;
  bool saved = false;
  bool antidote = true;
  bool toxin = true;
  int? hunterId;
  Phase hunterReturn = Phase.dawn;
  String? winner;
  List<int> lastDeaths = [];
  List<int> tied = [];
  List<String> speeches = [];
  String lastVote = '';
  String? privateResult;
  bool awaitingNightConfirmation = false;
  bool nightResultPending = false;

  GameEngine({
    required this.players,
    this.local = false,
    this.winRule = WinRule.border,
    Random? random,
  }) : random = random ?? Random() {
    if (!local) {
      for (final p in players.skip(1)) {
        relationships[p.id] = AiMemory(
          temperament:
              AiTemperament.values[(p.id - 2) % AiTemperament.values.length],
        );
      }
    }
  }

  factory GameEngine.create({
    int count = 12,
    bool local = false,
    Role? preferred,
    WinRule winRule = WinRule.border,
    int? seed,
  }) {
    final rng = Random(seed);
    final roles = <Role>[
      ...List.filled(count == 9 ? 3 : 4, Role.werewolf),
      ...List.filled(count == 9 ? 3 : 4, Role.villager),
      Role.seer,
      Role.witch,
      Role.hunter,
      if (count == 12) Role.guard,
    ]..shuffle(rng);
    if (!local && preferred != null && roles.contains(preferred)) {
      final i = roles.indexOf(preferred);
      final temp = roles[0];
      roles[0] = roles[i];
      roles[i] = temp;
    }
    const names = [
      '旅人',
      '林间客',
      '听雨',
      '白露',
      '渡鸦',
      '拾星',
      '暮山',
      '烛影',
      '北辰',
      '霜叶',
      '知秋',
      '望月',
    ];
    return GameEngine(
      local: local,
      winRule: winRule,
      random: rng,
      players: List.generate(
        count,
        (i) => Player(i + 1, local ? '${i + 1} 号玩家' : names[i], roles[i]),
      ),
    );
  }

  Player get me => players.first;
  AiMemory? relationship(int id) => relationships[id];
  Player player(int id) => players.firstWhere((p) => p.id == id);
  List<Player> get alive => players.where((p) => p.alive).toList();
  bool get isNight => [
    Phase.night,
    Phase.guard,
    Phase.wolves,
    Phase.seer,
    Phase.witch,
  ].contains(phase);
  bool get isAction => [
    Phase.guard,
    Phase.wolves,
    Phase.seer,
    Phase.witch,
    Phase.vote,
    Phase.hunter,
  ].contains(phase);
  bool get canAct =>
      isAction &&
      !awaitingNightConfirmation &&
      actor != null &&
      (local || actor!.id == me.id);
  Player? get actor {
    if (phase == Phase.deal) return players[dealIndex];
    if (phase == Phase.vote) {
      return local ? alive[voteIndex] : (me.alive ? me : null);
    }
    if (phase == Phase.hunter) {
      return hunterId == null ? null : player(hunterId!);
    }
    final role = {
      Phase.guard: Role.guard,
      Phase.wolves: Role.werewolf,
      Phase.seer: Role.seer,
      Phase.witch: Role.witch,
    }[phase];
    if (role == null) return null;
    final matches = alive.where((p) => p.role == role).toList();
    if (matches.isEmpty) return null;
    if (!local && me.alive && me.role == role) return me;
    return matches.first;
  }

  List<Player> get wolves => players.where((p) => p.role.isWolf).toList();
  List<Player> get targets =>
      (awaitingNightConfirmation ||
          (phase == Phase.vote && !local && !me.alive))
      ? []
      : alive.where((p) {
          if (phase == Phase.wolves) return !p.role.isWolf;
          if (phase == Phase.guard) return p.id != lastProtected;
          if (phase == Phase.seer ||
              phase == Phase.vote ||
              phase == Phase.hunter) {
            return p.id != actor?.id;
          }
          return true;
        }).toList();
  bool get canSave =>
      antidote && attack != null && (attack != actor?.id || day == 1);
  String get title => {
    Phase.deal: '命运已写下',
    Phase.night: '天黑，请闭眼',
    Phase.guard: '守卫，请守护',
    Phase.wolves: '狼人，请行动',
    Phase.seer: '预言家，请查验',
    Phase.witch: '女巫，请选择',
    Phase.dawn: '天亮了',
    Phase.discussion: '围炉议事',
    Phase.vote: '放逐投票',
    Phase.hunter: '猎人的最后一枪',
    Phase.ended: winner == 'good' ? '曙光终至' : '长夜降临',
  }[phase]!;
  String get instruction => {
    Phase.deal: local
        ? '将设备交给 ${dealIndex + 1} 号玩家，独自查看你的身份。'
        : '记住你的身份与使命。长夜，即将开始。',
    Phase.night: '村庄陷入寂静。你的夜间技能将在对应时刻出现。',
    Phase.guard: '选择今晚要守护的人。不能连续两夜守护同一人。',
    Phase.wolves:
        '你的狼队：${wolves.map((p) => '${p.id}号').join('、')}。选择一位存活的好人袭击。',
    Phase.seer: '选择一位其他存活玩家，查验他的阵营。结果仅你可见。',
    Phase.witch: antidote
        ? (attack == null
              ? '今晚无人被袭击。你可以使用毒药，或静候天明。'
              : '今晚 ${attack!} 号被袭击。你每晚只能使用一瓶药。')
        : '解药已用尽，今晚刀口不可见。可以使用毒药或不行动。',
    Phase.dawn: lastDeaths.isEmpty
        ? '昨夜是一个平安夜。所有灯火，依然亮着。'
        : '昨夜 ${lastDeaths.map((id) => '$id号').join('、')} 玩家出局。请记住他们留下的线索。',
    Phase.discussion: local
        ? '存活玩家依座次自由发言。讨论结束后，将设备传递给每位玩家进行秘密投票。'
        : '听取每个人的发言。你可以公开查验、指认可疑玩家，或谨慎观望。',
    Phase.vote: !local && !me.alive
        ? '你已出局，本轮仅可旁观。存活玩家正在投票。'
        : '选择你认为的狼人，或弃票。最高票平票时，无人出局。',
    Phase.hunter: '你可以带走一位存活玩家。请谨慎选择，或让最后一枪沉默。',
    Phase.ended: winner == 'good' ? '所有狼人已被放逐，村庄迎来了黎明。' : '村民或神职已全部出局，狼群占领了村庄。',
  }[phase]!;

  void addEvent(
    String text, {
    bool secret = false,
    String? kind,
    int? actorId,
    int? targetId,
  }) => events.add(
    GameEvent(
      text,
      day,
      secret: secret,
      kind: kind,
      actorId: actorId,
      targetId: targetId,
    ),
  );
  void continueFlow() {
    if (awaitingNightConfirmation) return;
    privateResult = null;
    switch (phase) {
      case Phase.deal:
        if (local && dealIndex < players.length - 1) {
          dealIndex++;
        } else {
          phase = Phase.night;
          addEvent('身份已分配，第一夜降临。');
        }
      case Phase.night:
        _beginNight();
      case Phase.dawn:
        phase = Phase.discussion;
        _makeSpeeches();
      case Phase.discussion:
        phase = Phase.vote;
        voteIndex = 0;
        votes.clear();
      case Phase.vote:
        if (!local && !me.alive) _resolveVotes();
      default:
        break;
    }
    notifyListeners();
  }

  /// Returns a user-facing validation error, or null after accepting the move.
  String? act(int? target, {String potion = 'pass'}) {
    if (!isAction) return '当前不能行动。';
    if (phase == Phase.vote && !local && !me.alive) {
      return '你已出局，不能投票。';
    }
    if (!canAct) return '请先确认行动完成并闭眼。';
    if (target != null && !targets.any((p) => p.id == target)) {
      return '这位玩家不能被选择。';
    }
    if ([Phase.wolves, Phase.seer].contains(phase) && target == null) {
      return '请先选择一位玩家。';
    }
    if (phase == Phase.witch) {
      if (potion == 'save' && !canSave) return '现在不能使用解药。';
      if (potion == 'poison' && (!toxin || target == null)) {
        return '请选择毒药目标，且必须持有毒药。';
      }
      if (!['save', 'poison', 'pass'].contains(potion)) return '无效的药剂选择。';
    }
    if (phase == Phase.vote) {
      if (actor == null) return '请继续结算投票。';
      votes[actor!.id] = target;
      if (local && voteIndex < alive.length - 1) {
        voteIndex++;
      } else {
        _resolveVotes();
      }
    } else if (phase == Phase.hunter) {
      if (target != null) {
        player(target).alive = false;
        addEvent(
          '猎人 ${hunterId!} 号开枪，带走了 $target 号。',
          kind: 'shot',
          actorId: hunterId,
          targetId: target,
        );
      } else {
        addEvent('猎人 ${hunterId!} 号选择不开枪。');
      }
      hunterId = null;
      if (!_checkWinner()) {
        if (hunterReturn == Phase.night) {
          phase = Phase.night;
        } else {
          phase = Phase.dawn;
        }
      }
    } else {
      _applyNight(phase, actor!, target, potion: potion);
      if (local) {
        awaitingNightConfirmation = true;
      } else {
        nightIndex++;
        _seekNight();
      }
    }
    notifyListeners();
    return null;
  }

  void confirmNightAction() {
    if (!local || !awaitingNightConfirmation) return;
    awaitingNightConfirmation = false;
    privateResult = null;
    nightIndex++;
    _seekNight();
    notifyListeners();
  }

  void acknowledgeNightResult() {
    if (!nightResultPending) return;
    nightResultPending = false;
    notifyListeners();
  }

  void _beginNight() {
    attack = null;
    protected = null;
    poison = null;
    saved = false;
    lastDeaths = [];
    nightResultPending = false;
    awaitingNightConfirmation = false;
    nightIndex = 0;
    _seekNight();
  }

  static const _nightSteps = [
    Phase.guard,
    Phase.wolves,
    Phase.seer,
    Phase.witch,
  ];
  void _seekNight() {
    while (nightIndex < _nightSteps.length) {
      phase = _nightSteps[nightIndex];
      final a = actor;
      if (a == null) {
        nightIndex++;
        continue;
      }
      if (local || a.id == me.id) return;
      _botNight(a);
      nightIndex++;
    }
    _resolveNight();
  }

  void _applyNight(
    Phase step,
    Player a,
    int? target, {
    String potion = 'pass',
  }) {
    switch (step) {
      case Phase.guard:
        protected = target;
      case Phase.wolves:
        attack = target;
      case Phase.seer:
        if (target != null) {
          final wolf = player(target).role.isWolf;
          botChecks.putIfAbsent(a.id, () => {})[target] = wolf;
          if (local || a.id == me.id) {
            checks[target] = wolf;
            privateResult = '$target 号是${wolf ? '狼人阵营' : '好人阵营'}。';
            if (!local) {
              addEvent(
                '你查验了 $target 号：${wolf ? '狼人阵营' : '好人阵营'}。',
                secret: true,
              );
            }
          }
        }
      case Phase.witch:
        if (potion == 'save') {
          saved = true;
          antidote = false;
        }
        if (potion == 'poison') {
          poison = target;
          toxin = false;
        }
      default:
        break;
    }
  }

  Player _pick(List<Player> options) => options[random.nextInt(options.length)];
  double _suspicionScore(Player speaker, Player candidate) {
    final known = botChecks[speaker.id]?[candidate.id];
    return (suspicion[candidate.id] ?? 0) +
        (known == null
            ? 0
            : known
            ? 12
            : -12) -
        (candidate.id == me.id
            ? (relationship(speaker.id)?.affinity ?? 0) / 100 * .9
            : 0);
  }

  int? _suspect(Player a, {bool excludeTeam = false}) {
    final options = alive
        .where((p) => p.id != a.id && (!excludeTeam || !p.role.isWolf))
        .toList();
    if (options.isEmpty) return null;
    options.shuffle(random);
    options.sort(
      (first, second) =>
          _suspicionScore(a, second).compareTo(_suspicionScore(a, first)),
    );
    return _suspicionScore(a, options.first) >= 5 || random.nextDouble() < .7
        ? options.first.id
        : _pick(options).id;
  }

  void _botNight(Player a) {
    int? target;
    String potion = 'pass';
    switch (phase) {
      case Phase.guard:
        final options = targets;
        if (options.isNotEmpty) target = _pick(options).id;
      case Phase.wolves:
        final options = targets;
        if (options.isNotEmpty) target = _pick(options).id;
      case Phase.seer:
        final known = botChecks[a.id] ?? {};
        var options = targets.where((p) => !known.containsKey(p.id)).toList();
        if (options.isEmpty) options = targets;
        if (options.isNotEmpty) target = _pick(options).id;
      case Phase.witch:
        if (canSave && random.nextDouble() < .8) {
          potion = 'save';
        } else if (toxin && day > 1 && random.nextDouble() < .4) {
          target = _suspect(a);
          if (target != null) potion = 'poison';
        }
      default:
        break;
    }
    _applyNight(phase, a, target, potion: potion);
  }

  void _resolveNight() {
    final deaths = <int>{};
    if (attack != null) {
      final guarded = protected == attack;
      // Guard and antidote cancel when both protect the attacked player.
      if (guarded == saved) deaths.add(attack!);
    }
    if (poison != null) deaths.add(poison!);
    lastProtected = protected;
    lastDeaths = deaths.toList()..sort();
    for (final id in deaths) {
      player(id).alive = false;
    }
    addEvent(
      lastDeaths.isEmpty
          ? '第 $day 夜，平安夜。'
          : '第 $day 夜，${lastDeaths.map((id) => '$id号').join('、')} 出局。',
    );
    phase = Phase.dawn;
    nightResultPending = true;
    final hunters = players.where(
      (p) => deaths.contains(p.id) && p.role == Role.hunter && poison != p.id,
    );
    if (hunters.isNotEmpty) {
      _triggerHunter(hunters.first, Phase.dawn);
    } else {
      _checkWinner();
    }
  }

  void _triggerHunter(Player hunter, Phase resume) {
    hunterId = hunter.id;
    hunterReturn = resume;
    phase = Phase.hunter;
    addEvent('${hunter.id} 号亮出猎人身份。');
    if (!local && hunter.id != me.id) {
      final target = _suspect(hunter);
      if (target != null) {
        player(target).alive = false;
        addEvent(
          '猎人 ${hunter.id} 号开枪，带走 $target 号。',
          kind: 'shot',
          actorId: hunter.id,
          targetId: target,
        );
      }
      hunterId = null;
      if (!_checkWinner()) phase = resume;
    }
  }

  void _makeSpeeches() {
    speeches.clear();
    announcedVotes.clear();
    if (local) return;
    for (final p in alive.where((p) => p.id != me.id)) {
      final known = botChecks[p.id] ?? {};
      MapEntry<int, bool>? check;
      if (p.role == Role.seer && known.isNotEmpty) {
        final e = known.entries.last;
        check = e;
        suspicion[e.key] = (suspicion[e.key] ?? 0) + (e.value ? 3 : -2);
      }
      final target = _suspect(p, excludeTeam: p.role.isWolf);
      announcedVotes[p.id] = target;
      final speech = AiDialogue.speech(
        memory: relationships[p.id]!,
        random: random,
        target: target,
        deaths: lastDeaths,
        humanAlive: me.alive,
        check: check,
        previous: voteHistory.isEmpty ? null : voteHistory.last,
        speakerId: p.id,
      );
      speeches.add('${p.id}号 · ${p.name}：$speech');
    }
  }

  void speak({int? accuse, bool reveal = false}) {
    if (local || phase != Phase.discussion || !me.alive) return;
    if (speeches.any((s) => s.startsWith('1号 · 你'))) return;
    if (reveal && me.role == Role.seer && checks.isNotEmpty) {
      final text = checks.entries
          .map((e) => '${e.key}号是${e.value ? '狼人' : '好人'}')
          .join('，');
      speeches.insert(0, '1号 · 你：我是预言家，我的查验是：$text。');
      for (final e in checks.entries) {
        suspicion[e.key] = (suspicion[e.key] ?? 0) + (e.value ? 3 : -2);
      }
    } else if (accuse != null &&
        alive.any((p) => p.id == accuse) &&
        accuse != me.id) {
      speeches.insert(0, '1号 · 你：我认为 $accuse 号值得怀疑，希望大家关注他的发言。');
      suspicion[accuse] = (suspicion[accuse] ?? 0) + 1.5;
    } else {
      speeches.insert(0, '1号 · 你：我先听取大家的意见，暂时保留判断。');
    }
    notifyListeners();
  }

  void _resolveVotes() {
    votes.removeWhere(
      (voter, target) =>
          !alive.any((p) => p.id == voter) ||
          (target != null && !alive.any((p) => p.id == target)),
    );
    if (!local) {
      for (final p in alive.where((p) => p.id != me.id)) {
        // Keep the public intention unless stronger evidence appeared later.
        final intended = announcedVotes[p.id];
        final reconsidered = _suspect(p, excludeTeam: p.role.isWolf);
        final validIntent =
            intended != null &&
            alive.any(
              (o) =>
                  o.id == intended &&
                  o.id != p.id &&
                  (!p.role.isWolf || !o.role.isWolf),
            );
        votes[p.id] =
            validIntent &&
                (reconsidered == null ||
                    _suspicionScore(p, player(intended)) >=
                        _suspicionScore(p, player(reconsidered)) - .5)
            ? intended
            : reconsidered;
      }
    }
    _rememberBallots();
    final counts = <int, int>{};
    for (final v in votes.values.whereType<int>()) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
    tied.clear();
    if (counts.isNotEmpty) {
      final max = counts.values.reduce((a, b) => a > b ? a : b);
      tied =
          counts.entries.where((e) => e.value == max).map((e) => e.key).toList()
            ..sort();
    }
    final detail = votes.entries
        .map((e) => '${e.key}号 → ${e.value == null ? '弃票' : '${e.value}号'}')
        .join('，');
    lastVote = detail;
    addEvent('投票记录：$detail');
    if (tied.length != 1) {
      addEvent(tied.isEmpty ? '所有人弃票，无人出局。' : '${tied.join('、')}号平票，无人出局。');
    } else {
      final p = player(tied.first);
      p.alive = false;
      addEvent('${p.id} 号被放逐。', kind: 'exile', targetId: p.id);
      if (p.role == Role.hunter) {
        day++;
        _triggerHunter(p, Phase.night);
        return;
      }
    }
    if (!_checkWinner()) {
      day++;
      phase = Phase.night;
    }
  }

  void _rememberBallots() {
    if (local || voteHistory.any((round) => round.day == day)) return;
    voteHistory.add(VoteMemory(day, votes));
    final humanVote = votes[me.id];
    if (humanVote == null) return;
    for (final p in alive.where((p) => p.id != me.id)) {
      final memory = relationships[p.id]!;
      if (humanVote == p.id) {
        memory.change(-12, '你在第 $day 天投了我', day);
      } else if (votes[p.id] == humanVote) {
        memory.change(5, '第 $day 天我们同投 $humanVote 号', day);
      }
    }
  }

  bool _checkWinner() {
    final wolfCount = alive.where((p) => p.role.isWolf).length;
    final goodCount = alive.length - wolfCount;
    if (wolfCount == 0) {
      winner = 'good';
    } else if (winRule == WinRule.parity
        ? wolfCount >= goodCount
        : !alive.any((p) => p.role == Role.villager) ||
              !alive.any((p) => p.role.isGod)) {
      winner = 'wolf';
    }
    if (winner != null) {
      phase = Phase.ended;
      addEvent(winner == 'good' ? '好人阵营获胜。' : '狼人阵营获胜。');
      return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
    'local': local,
    'winRule': winRule.name,
    'players': players.map((p) => p.toJson()).toList(),
    'phase': phase.name,
    'day': day,
    'events': events.map((e) => e.toJson()).toList(),
    'checks': checks.map((k, v) => MapEntry('$k', v)),
    'botChecks': botChecks.map(
      (k, v) => MapEntry('$k', v.map((a, b) => MapEntry('$a', b))),
    ),
    'suspicion': suspicion.map((k, v) => MapEntry('$k', v)),
    'votes': votes.map((k, v) => MapEntry('$k', v)),
    'relationships': relationships.map((k, v) => MapEntry('$k', v.toJson())),
    'voteHistory': voteHistory.map((r) => r.toJson()).toList(),
    'announcedVotes': announcedVotes.map((k, v) => MapEntry('$k', v)),
    'dealIndex': dealIndex,
    'voteIndex': voteIndex,
    'nightIndex': nightIndex,
    'attack': attack,
    'protected': protected,
    'lastProtected': lastProtected,
    'poison': poison,
    'saved': saved,
    'antidote': antidote,
    'toxin': toxin,
    'hunterId': hunterId,
    'hunterReturn': hunterReturn.name,
    'winner': winner,
    'lastDeaths': lastDeaths,
    'tied': tied,
    'speeches': speeches,
    'lastVote': lastVote,
    'awaitingNightConfirmation': awaitingNightConfirmation,
    'nightResultPending': nightResultPending,
    'privateResult': privateResult,
  };
  factory GameEngine.fromJson(Map<String, dynamic> j) {
    final g = GameEngine(
      players: (j['players'] as List)
          .map((p) => Player.fromJson(Map<String, dynamic>.from(p)))
          .toList(),
      local: j['local'],
      winRule: WinRule.values.firstWhere(
        (rule) => rule.name == j['winRule'],
        orElse: () => WinRule.border,
      ),
    );
    g.phase = Phase.values.byName(j['phase']);
    g.day = j['day'];
    g.events.addAll(
      (j['events'] as List).map(
        (e) => GameEvent.fromJson(Map<String, dynamic>.from(e)),
      ),
    );
    (j['checks'] as Map).forEach((k, v) => g.checks[int.parse(k)] = v);
    (j['botChecks'] as Map).forEach(
      (k, v) => g.botChecks[int.parse(k)] = (v as Map).map(
        (a, b) => MapEntry(int.parse(a), b as bool),
      ),
    );
    (j['suspicion'] as Map).forEach(
      (k, v) => g.suspicion[int.parse(k)] = (v as num).toDouble(),
    );
    (j['votes'] as Map).forEach((k, v) => g.votes[int.parse(k)] = v);
    (j['relationships'] as Map? ?? {}).forEach((k, v) {
      g.relationships[int.parse(k)] = AiMemory.fromJson(
        Map<String, dynamic>.from(v),
      );
    });
    g.voteHistory.addAll(
      (j['voteHistory'] as List? ?? []).map(
        (r) => VoteMemory.fromJson(Map<String, dynamic>.from(r)),
      ),
    );
    (j['announcedVotes'] as Map? ?? {}).forEach(
      (k, v) => g.announcedVotes[int.parse(k)] = v,
    );
    g.dealIndex = j['dealIndex'];
    g.voteIndex = j['voteIndex'];
    g.nightIndex = j['nightIndex'];
    g.attack = j['attack'];
    g.protected = j['protected'];
    g.lastProtected = j['lastProtected'];
    g.poison = j['poison'];
    g.saved = j['saved'];
    g.antidote = j['antidote'];
    g.toxin = j['toxin'];
    g.hunterId = j['hunterId'];
    g.hunterReturn = Phase.values.byName(j['hunterReturn']);
    g.winner = j['winner'];
    g.lastDeaths = List<int>.from(j['lastDeaths']);
    g.tied = List<int>.from(j['tied']);
    g.speeches = List<String>.from(j['speeches']);
    g.lastVote = j['lastVote'];
    g.awaitingNightConfirmation = j['awaitingNightConfirmation'] ?? false;
    g.nightResultPending = j['nightResultPending'] ?? (g.phase == Phase.dawn);
    g.privateResult = j['privateResult'];
    return g;
  }
}
