import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonveil/game/ai_personality.dart';
import 'package:moonveil/game/engine.dart';
import 'package:moonveil/game/roles.dart';

GameEngine socialGame() => GameEngine(
  random: Random(12),
  players: [
    Player(1, '旅人', Role.villager),
    Player(2, '林间客', Role.villager),
    Player(3, '听雨', Role.seer),
    Player(4, '白露', Role.werewolf),
    Player(5, '渡鸦', Role.hunter),
    Player(6, '拾星', Role.witch),
    Player(7, '暮山', Role.werewolf),
    Player(8, '烛影', Role.villager),
    Player(9, '北辰', Role.villager),
  ],
);

void main() {
  test('relations settle once from actual ballots, including an exiled AI', () {
    final g = socialGame()..phase = Phase.vote;
    g.suspicion[4] = 4;
    g.announcedVotes.addAll({2: 4, 3: 4, 5: 4, 6: 4, 8: 4, 9: 4});
    expect(g.relationship(4)!.affinity, 0);
    expect(g.act(4), isNull);
    expect(g.relationship(4)!.affinity, -12);
    expect(g.relationship(4)!.reason, '你在第 1 天投了我');
    expect(g.relationship(2)!.affinity, 5);
    expect(g.relationship(2)!.reason, '第 1 天我们同投 4 号');
    expect(g.voteHistory.single.ballots, g.votes);
    expect(g.votes[4], isNot(7)); // Wolf teammates stay excluded.
    final before = g.relationship(2)!.affinity;
    g.continueFlow();
    expect(g.relationship(2)!.affinity, before);
    g.dispose();
  });
  test('abstaining or spectating does not reward coincidental bot ballots', () {
    for (final dead in [false, true]) {
      final g = socialGame()..phase = Phase.vote;
      g.me.alive = !dead;
      if (dead) {
        g.continueFlow();
      } else {
        g.act(null);
      }
      expect(g.relationships.values.every((m) => m.affinity == 0), true);
      g.dispose();
    }
  });
  test(
    'hostility, friendly memories, personality and public votes shape dialogue',
    () {
      final g = socialGame()..phase = Phase.vote;
      g.suspicion[8] = 4;
      g.announcedVotes.addAll({2: 8, 3: 8, 4: 8, 5: 8, 6: 8, 7: 8, 9: 8});
      g.act(2); // Most bots exile 8, leaving the offended 2 alive.
      expect(g.player(2).alive, true);
      g.relationship(3)!.change(5, '第 1 天我们同投 8 号', 1);
      g.phase = Phase.dawn;
      g.lastDeaths = [8];
      g.continueFlow();
      final offended = g.speeches.firstWhere((s) => s.startsWith('2号'));
      final friendly = g.speeches.firstWhere((s) => s.startsWith('3号'));
      expect(offended, contains('旅人'));
      expect(offended, contains('上一轮我投的是 8 号'));
      expect(friendly, contains('旅人'));
      expect(
        g.announcedVotes.keys.toSet(),
        g.alive.skip(1).map((p) => p.id).toSet(),
      );
      expect(g.speeches.any((s) => s.startsWith('8号')), false);
      g.dispose();
    },
  );
  test('verified wolf check outranks maximum affection', () {
    final g = socialGame()..phase = Phase.vote;
    g.relationship(3)!.change(100, '朋友', 1);
    g.botChecks[3] = {1: true};
    g.announcedVotes[3] = 2;
    g.act(4);
    expect(g.votes[3], 1);
    g.dispose();
  });
  test('saved social history survives and old saves start neutral', () {
    final g = socialGame();
    final m = g.relationship(2)!;
    m.change(-12, '你在第 1 天投了我', 1);
    m.line('view', AiDialogue.viewpoints[m.temperament]!, Random(1));
    g.voteHistory.add(VoteMemory(1, {1: 2, 2: 3}));
    g.announcedVotes[2] = 3;
    final j = jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>;
    final restored = GameEngine.fromJson(j);
    expect(restored.toJson(), g.toJson());
    j.remove('relationships');
    j.remove('voteHistory');
    j.remove('announcedVotes');
    final old = GameEngine.fromJson(j);
    expect(old.relationship(2)!.affinity, 0);
    expect(old.voteHistory, isEmpty);
    g.dispose();
    restored.dispose();
    old.dispose();
  });
  test('affinity is bounded and templates do not repeat consecutively', () {
    final m = AiMemory(temperament: AiTemperament.thoughtful);
    m.change(200, '同票', 1);
    expect(m.affinity, 100);
    m.change(-300, '投我', 2);
    expect(m.affinity, -100);
    final rng = Random(4);
    String? previous;
    final unique = <String>{};
    for (var i = 0; i < 40; i++) {
      final next = m.line('view', AiDialogue.viewpoints[m.temperament]!, rng);
      expect(next, isNot(previous));
      unique.add(next);
      previous = next;
    }
    expect(unique.length, 8);
  });
}
