import 'dart:math';

enum AiTemperament { thoughtful, direct, gentle, witty, cautious, poetic }

extension TemperamentInfo on AiTemperament {
  String get label => ['沉稳', '直率', '温和', '风趣', '谨慎', '感性'][index];
}

/// Public social memory. It contains no role or night-action information.
class AiMemory {
  final AiTemperament temperament;
  int affinity;
  int lastDelta;
  int changedDay;
  String reason;
  final Map<String, int> usedLines;
  AiMemory({
    required this.temperament,
    this.affinity = 0,
    this.lastDelta = 0,
    this.changedDay = 0,
    this.reason = '初次相遇',
    Map<String, int>? usedLines,
  }) : usedLines = usedLines ?? {};

  String get attitude => affinity >= 20
      ? '信赖'
      : affinity > 0
      ? '友善'
      : affinity <= -20
      ? '戒备'
      : affinity < 0
      ? '疏远'
      : '中立';

  void change(int delta, String why, int day) {
    final next = (affinity + delta).clamp(-100, 100);
    lastDelta = next - affinity;
    affinity = next;
    reason = why;
    changedDay = day;
  }

  /// Avoid consecutive repeats within a category, including after resuming.
  String line(String category, List<String> choices, Random random) {
    var index = random.nextInt(choices.length);
    if (choices.length > 1 && usedLines[category] == index) {
      index = (index + 1 + random.nextInt(choices.length - 1)) % choices.length;
    }
    usedLines[category] = index;
    return choices[index];
  }

  Map<String, dynamic> toJson() => {
    'temperament': temperament.name,
    'affinity': affinity,
    'lastDelta': lastDelta,
    'changedDay': changedDay,
    'reason': reason,
    'usedLines': usedLines,
  };
  factory AiMemory.fromJson(Map<String, dynamic> j) => AiMemory(
    temperament: AiTemperament.values.byName(j['temperament']),
    affinity: (j['affinity'] as int? ?? 0).clamp(-100, 100),
    lastDelta: j['lastDelta'] ?? 0,
    changedDay: j['changedDay'] ?? 0,
    reason: j['reason'] ?? '初次相遇',
    usedLines: Map<String, int>.from(j['usedLines'] ?? {}),
  );
}

class VoteMemory {
  final int day;
  final Map<int, int?> ballots;
  VoteMemory(this.day, Map<int, int?> ballots) : ballots = Map.of(ballots);
  Map<String, dynamic> toJson() => {
    'day': day,
    'ballots': ballots.map((k, v) => MapEntry('$k', v)),
  };
  factory VoteMemory.fromJson(Map<String, dynamic> j) => VoteMemory(
    j['day'],
    (j['ballots'] as Map).map((k, v) => MapEntry(int.parse(k), v as int?)),
  );
}

/// Offline dialogue combines temperament, actual public events, and memory.
/// Arguments must come from public information or this speaker's own checks.
class AiDialogue {
  static const viewpoints = <AiTemperament, List<String>>{
    AiTemperament.thoughtful: [
      '先把事实和猜测分开。今天我倾向投 {t} 号，但还愿意听解释。',
      '票要有来由。我目前把 {t} 号放在怀疑名单首位。',
      '我不急着给所有人贴标签；这一轮先看 {t} 号。',
      '结论可以改，理由不能省。我的暂定票是 {t} 号。',
      '与其猜一圈身份，不如先解决一个疑点。我想投 {t} 号。',
      '别把声音大当成证据。我会把票交给 {t} 号。',
      '我会记下今天的票型。目前更想听 {t} 号给一个清楚的立场。',
      '先不跟风。按我现在的判断，{t} 号更值得投。',
    ],
    AiTemperament.direct: [
      '我直说：这一票想给 {t} 号。有理由就现在说服我。',
      '别兜圈子了，我今天盯 {t} 号。',
      '我的立场摆在这里，先投 {t} 号，投错了我也认。',
      '大家都想等别人下结论，我先来：{t} 号。',
      '我不爱绕弯；{t} 号，请把你的票和理由一起摆出来。',
      '先把 {t} 号的事情讲明白，再谈别的。',
      '沉默解决不了问题。我暂时出 {t} 号。',
      '我的票不藏着，{t} 号是我这轮的第一选择。',
    ],
    AiTemperament.gentle: [
      '先别吵，我们慢慢说。我这一轮比较想投 {t} 号。',
      '谁都有判断失误的时候，{t} 号，再给大家一点理由好吗？',
      '我愿意听完每个人，但现在更倾向 {t} 号。',
      '不想冤枉好人。{t} 号，我希望你能说服我收回这票。',
      '先让大家把话说完吧；我的暂定票还是 {t} 号。',
      '不要只凭好恶投票。我今天会重点考虑 {t} 号。',
      '我有些犹豫，还是先把 {t} 号列为这一轮的选择。',
      '我们还有机会把线索理清。现在，我准备投 {t} 号。',
    ],
    AiTemperament.witty: [
      '火烧得挺旺，脑子可别烧糊了。我这票先给 {t} 号。',
      '我的直觉不是水晶球，但今天它指向 {t} 号。',
      '先别把锅甩给月亮。我想听 {t} 号解释，再决定票。',
      '谁也别想靠一句“相信我”过关。我目前选 {t} 号。',
      '好人可以迷路，票可别乱飞。我准备投 {t} 号。',
      '茶凉了可以再煮，投错人就难了。我先盯 {t} 号。',
      '大家说得都像有道理，难的是选一张票。我暂定 {t} 号。',
      '今天先收起玄学，我的怀疑名单里 {t} 号排第一。',
    ],
    AiTemperament.cautious: [
      '我不敢保证猜对了；今天先考虑 {t} 号，听完再改。',
      '不要急着统一票，我想保留对 {t} 号的怀疑。',
      '信息还不够多。不过这一票，我暂时偏向 {t} 号。',
      '查验和票型都要看。我目前先把 {t} 号记下来。',
      '我担心误投，所以还想听听 {t} 号的理由。',
      '我的判断只是暂时的，今天倾向给 {t} 号一票。',
      '越是大家一口咬定，我越想再核对。暂定 {t} 号。',
      '先留一点余地。{t} 号目前最让我拿不准。',
    ],
    AiTemperament.poetic: [
      '灯火还在，我们就还有机会。今天我更怀疑 {t} 号。',
      '夜色藏住了身份，却藏不住每一张票。我暂时选 {t} 号。',
      '月亮不会替我们作答。我想先听 {t} 号，再落下这票。',
      '别让恐惧替我们投票。现在我的选择是 {t} 号。',
      '希望下一盏灯不会熄错。我这一轮倾向 {t} 号。',
      '真相还在雾里，今天先从 {t} 号找起。',
      '每个留在这里的人，都欠村庄一个答案。我的票暂定 {t} 号。',
      '黎明来了，疑问还没散。我会继续关注 {t} 号。',
    ],
  };
  static const friendly = [
    '旅人，我们上次站在同一边，今天你的判断我会认真听。',
    '旅人，谢谢你之前跟我同票；有新线索也别忘了提醒我。',
    '旅人，我们票投到一块过。我愿意多给你一点信任。',
    '旅人，你上次愿意支持我的选择，我记着呢。',
    '旅人，我比较愿意相信你，不过这一票还是得看理由。',
    '旅人，我们配合过一次，希望这回也别走散。',
  ];
  static const distant = [
    '旅人，你之前投过我，这一回我需要更具体的理由。',
    '旅人，那张投向我的票我还记得。我们把分歧说清楚。',
    '旅人，你怀疑过我，我当然也会重新看你的立场。',
    '旅人，我对你有些保留，但不会只为赌气落票。',
    '旅人，前一轮的分歧还在；这次请让我听见你的依据。',
    '旅人，我们的信任还得重新建立，先谈线索吧。',
  ];
  static const peace = [
    '昨夜无人出局，但平安夜不能直接证明谁的身份。',
    '大家都还在，这是好消息；仍要把白天的票想清楚。',
    '平安夜多给了我们一轮机会，别把它浪费在争吵里。',
    '昨夜灯火都没熄，接下来就看我们白天怎么选。',
  ];
  static const loss = [
    '昨夜 {d} 号出局了，我想把这条公开消息和票型一起看。',
    '少了 {d} 号，我们更得把今天的票落准。',
    '先记下昨夜出局的 {d} 号，不要靠刀口直接猜身份。',
    '{d} 号的座位空了。今天我想多听理由，少听保证。',
  ];
  static const checks = [
    '我报预言家，查验 {t} 号是{camp}，请大家把这条信息记下。',
    '我有查验要说：{t} 号是{camp}。我是预言家。',
    '我是预言家，{t} 号的查验结果是{camp}；我的票会参考查验。',
    '先报信息。我是预言家，验到 {t} 号是{camp}。',
    '我不想让查验埋在争论里：{t} 号是{camp}，预言家是我。',
    '我的身份是预言家。最新查验，{t} 号属于{camp}。',
  ];
  static String speech({
    required AiMemory memory,
    required Random random,
    required int? target,
    required List<int> deaths,
    required bool humanAlive,
    required MapEntry<int, bool>? check,
    required VoteMemory? previous,
    required int speakerId,
  }) {
    final parts = <String>[];
    if (memory.affinity != 0 && humanAlive) {
      parts.add(
        memory.line(
          'relation',
          memory.affinity > 0 ? friendly : distant,
          random,
        ),
      );
    }
    if (check != null) {
      parts.add(
        memory
            .line('check', checks, random)
            .replaceAll('{t}', '${check.key}')
            .replaceAll('{camp}', check.value ? '狼人阵营' : '好人阵营'),
      );
    } else {
      parts.add(
        memory
            .line('night', deaths.isEmpty ? peace : loss, random)
            .replaceAll('{d}', deaths.join('、')),
      );
    }
    if (previous != null && previous.ballots.containsKey(speakerId)) {
      final vote = previous.ballots[speakerId];
      parts.add(
        vote == null
            ? '上一轮我弃票了，今天想给出一个更明确的判断。'
            : '上一轮我投的是 $vote 号，今天也欢迎大家回看票型。',
      );
    }
    if (target != null) {
      parts.add(
        memory
            .line('view', viewpoints[memory.temperament]!, random)
            .replaceAll('{t}', '$target'),
      );
    } else {
      parts.add('我暂时没有可投的目标，这一轮选择弃票。');
    }
    return parts.join('');
  }
}
