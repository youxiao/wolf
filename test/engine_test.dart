import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonveil/game/engine.dart';
import 'package:moonveil/game/roles.dart';

GameEngine village({Role first = Role.guard}) {
  final roles = [
    first,
    Role.werewolf,
    Role.seer,
    Role.witch,
    Role.hunter,
    Role.villager,
    Role.villager,
    Role.werewolf,
    Role.villager,
  ];
  return GameEngine(
    local: true,
    players: List.generate(
      roles.length,
      (i) => Player(i + 1, '${i + 1}号', roles[i]),
    ),
  );
}

void begin(GameEngine g) {
  while (g.phase == Phase.deal) {
    g.continueFlow();
  }
  g.continueFlow();
}

void night(
  GameEngine g, {
  int? guard,
  int attack = 6,
  int check = 2,
  String potion = 'pass',
  int? poison,
}) {
  if (g.phase == Phase.guard) expect(move(g, guard), isNull);
  expect(g.phase, Phase.wolves);
  expect(move(g, attack), isNull);
  if (g.phase == Phase.seer) expect(move(g, check), isNull);
  if (g.phase == Phase.witch) expect(move(g, poison, potion: potion), isNull);
}

void abstain(GameEngine g) {
  g.continueFlow();
  g.continueFlow();
  while (g.phase == Phase.vote) {
    expect(move(g, null), isNull);
  }
}

String? move(GameEngine g, int? target, {String potion = 'pass'}) {
  final error = g.act(target, potion: potion);
  if (error == null && g.awaitingNightConfirmation) g.confirmNightAction();
  return error;
}

void main() {
  test('dead solo player cannot choose, submit or leave a counted ballot', () {
    final g = GameEngine.create(preferred: Role.villager, seed: 3);
    g.me.alive = false;
    g.phase = Phase.vote;
    expect(g.actor, isNull);
    expect(g.canAct, false);
    expect(g.targets, isEmpty);
    expect(g.act(2), contains('不能投票'));
    expect(g.act(null), contains('不能投票'));
    expect(g.votes, isEmpty);
    g.votes[g.me.id] = 2; // Also reject a stale ballot from a restored game.
    g.continueFlow();
    expect(g.votes.containsKey(g.me.id), false);
    expect(
      g.lastVote.split('，').any((ballot) => ballot.startsWith('1号 →')),
      false,
    );
  });
  test(
    'local night cannot advance until completed role confirms closing eyes',
    () {
      final g = village();
      begin(g);
      expect(g.act(6), isNull);
      expect(g.protected, 6);
      expect(g.phase, Phase.guard);
      expect(g.awaitingNightConfirmation, true);
      expect(g.canAct, false);
      expect(g.act(7), isNotNull);
      g.continueFlow();
      expect(g.phase, Phase.guard);
      final restored = GameEngine.fromJson(jsonDecode(jsonEncode(g.toJson())));
      expect(restored.awaitingNightConfirmation, true);
      restored.confirmNightAction();
      expect(restored.phase, Phase.wolves);
      expect(restored.awaitingNightConfirmation, false);
      expect(restored.act(6), isNull);
      restored.confirmNightAction();
      expect(restored.phase, Phase.seer);
      expect(restored.act(2), isNull);
      expect(restored.phase, Phase.seer);
      expect(restored.privateResult, contains('狼人'));
      final seerSave = GameEngine.fromJson(
        jsonDecode(jsonEncode(restored.toJson())),
      );
      expect(seerSave.privateResult, restored.privateResult);
      seerSave.confirmNightAction();
      expect(seerSave.phase, Phase.witch);
      expect(seerSave.privateResult, isNull);
      expect(seerSave.act(null), isNull);
      expect(seerSave.phase, Phase.witch);
      seerSave.confirmNightAction();
      expect(seerSave.phase, Phase.dawn);
      expect(seerSave.nightResultPending, true);
      expect(seerSave.lastDeaths, isEmpty);
    },
  );
  test(
    'night announcement survives save and still precedes a night victory',
    () {
      final g = GameEngine(
        local: true,
        players: [
          Player(1, 'wolf', Role.werewolf),
          Player(2, 'seer', Role.seer),
          Player(3, 'villager', Role.villager),
        ],
      );
      begin(g);
      move(g, 3);
      move(g, 1);
      expect(g.phase, Phase.ended);
      expect(g.nightResultPending, true);
      expect(g.lastDeaths, [3]);
      final saved = GameEngine.fromJson(jsonDecode(jsonEncode(g.toJson())));
      expect(saved.nightResultPending, true);
      saved.acknowledgeNightResult();
      expect(saved.nightResultPending, false);
      expect(saved.winner, 'wolf');
    },
  );
  test('9 and 12 player classic distributions and chosen identity', () {
    for (final n in [9, 12]) {
      final g = GameEngine.create(count: n, preferred: Role.witch, seed: 4);
      expect(g.players.length, n);
      expect(g.me.role, Role.witch);
      expect(g.wolves.length, n == 9 ? 3 : 4);
      expect(g.players.where((p) => p.role.isGod).length, n == 9 ? 3 : 4);
    }
  });
  test(
    'guard protects attack, guard plus antidote cancels, poison ignores guard',
    () {
      final a = village();
      begin(a);
      night(a, guard: 6);
      expect(a.player(6).alive, true);
      final b = village();
      begin(b);
      night(b, guard: 6, potion: 'save');
      expect(b.player(6).alive, false);
      expect(b.antidote, false);
      final c = village();
      begin(c);
      night(c, guard: 7, attack: 6, potion: 'poison', poison: 7);
      expect(c.lastDeaths, [6, 7]);
      expect(c.toxin, false);
    },
  );
  test('guard cannot guard same seat twice, can abstain', () {
    final g = village();
    begin(g);
    night(g, guard: 6);
    abstain(g);
    g.continueFlow();
    expect(g.phase, Phase.guard);
    expect(move(g, 6), isNotNull);
    expect(move(g, null), isNull);
  });
  test('seer cannot inspect self and gets correct private alignment', () {
    final g = village();
    begin(g);
    move(g, null);
    move(g, 6);
    expect(move(g, 3), isNotNull);
    expect(move(g, 2), isNull);
    expect(g.checks[2], true);
    expect(g.privateResult, isNull);
    expect(g.events.any((e) => e.text.contains('查验')), false);
  });
  test('witch may self-save only on the first night, antidote hides target once used', () {
    final g = village();
    begin(g);
    night(g, attack: 4, potion: 'save');
    expect(g.player(4).alive, true);
    expect(g.antidote, false);
    abstain(g);
    g.continueFlow();
    move(g, null);
    move(g, 6);
    move(g, 2);
    expect(g.instruction, contains('刀口不可见'));
    expect(move(g, null, potion: 'save'), isNotNull);
    final second = village();
    begin(second);
    night(second, guard: 6);
    abstain(second);
    second.continueFlow();
    move(second, null);
    move(second, 4);
    move(second, 2);
    expect(second.canSave, false);
    expect(move(second, null, potion: 'save'), isNotNull);
  });
  test(
    'poisoned hunter cannot shoot, attacked hunter shoots before victory',
    () {
      final g = village();
      begin(g);
      night(g, guard: 6, potion: 'poison', poison: 5);
      expect(g.phase, Phase.dawn);
      expect(g.player(5).alive, false);
      final h = village();
      begin(h);
      night(h, attack: 5);
      expect(h.phase, Phase.hunter);
      expect(move(h, 2), isNull);
      expect(h.player(2).alive, false);
      expect(h.phase, Phase.dawn);
    },
  );
  test(
    'local ballots are sequential, self-vote invalid, ties exile nobody',
    () {
      final g = village();
      begin(g);
      night(g, guard: 6);
      g.continueFlow();
      g.continueFlow();
      expect(move(g, 1), isNotNull);
      for (final target in [2, 1, 2, 1, null, null, null, null, null]) {
        expect(move(g, target), isNull);
      }
      expect(g.phase, Phase.night);
      expect(g.alive.length, 9);
      expect(g.tied, [1, 2]);
      expect(g.lastVote, contains('弃票'));
    },
  );
  test(
    'saved game round-trip retains private state, skills and vote position',
    () {
      final g = village();
      begin(g);
      move(g, 6);
      move(g, 7);
      move(g, 2);
      final restored = GameEngine.fromJson(jsonDecode(jsonEncode(g.toJson())));
      expect(restored.toJson(), g.toJson());
      expect(restored.phase, Phase.witch);
      expect(restored.checks[2], true);
      move(restored, null, potion: 'save');
      expect(restored.antidote, false);
    },
  );
  test(
    '200 seeded solo games terminate for all six roles without deadlocks',
    () {
      for (int i = 0; i < 200; i++) {
        final g = GameEngine.create(
          count: 12,
          preferred: Role.values[i % 6],
          seed: i,
        );
        int steps = 0;
        while (g.phase != Phase.ended && steps++ < 500) {
          if (g.isAction) {
            if (g.phase == Phase.vote && !g.me.alive) {
              g.continueFlow();
              continue;
            }
            final options = g.targets;
            final target = options.isEmpty ? null : options.first.id;
            final error = move(g, g.phase == Phase.witch ? null : target);
            expect(error, isNull, reason: 'seed $i, ${g.phase}');
          } else {
            g.continueFlow();
          }
        }
        expect(g.phase, Phase.ended, reason: 'seed $i after $steps steps');
        expect(g.winner, isNotNull);
      }
    },
  );
  test('a hunter taking the last wolf wins even after the final god dies', () {
    final g = GameEngine(
      local: true,
      players: [
        Player(1, 'wolf', Role.werewolf),
        Player(2, 'hunter', Role.hunter),
        Player(3, 'villager', Role.villager),
      ],
    );
    begin(g);
    expect(g.phase, Phase.wolves);
    move(g, 2);
    expect(g.phase, Phase.hunter);
    move(g, 1);
    expect(g.winner, 'good');
  });
}
