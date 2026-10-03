import 'engine.dart';
import 'roles.dart';

enum CinematicKind {
  wolfAttack,
  hunterShot,
  guard,
  heal,
  poison,
  reveal,
  out,
  goodWin,
  wolfWin,
}

class CinematicEvent {
  final CinematicKind kind;
  final Role actorRole;
  final Role? targetRole;
  final int? targetId;
  final String? targetName;
  final bool muteEffect;
  const CinematicEvent(
    this.kind, {
    this.actorRole = Role.villager,
    this.targetRole,
    this.targetId,
    this.targetName,
    this.muteEffect = false,
  });

  String get title => switch (kind) {
    CinematicKind.wolfAttack => '暗夜扑袭',
    CinematicKind.hunterShot => '最后一枪',
    CinematicKind.guard => '月下守护',
    CinematicKind.heal => '生命之光',
    CinematicKind.poison => '紫雾之誓',
    CinematicKind.reveal => '星辰洞悉',
    CinematicKind.out => '灯火熄灭',
    CinematicKind.goodWin => '曙光终至',
    CinematicKind.wolfWin => '长夜降临',
  };
  String get subtitle => switch (kind) {
    CinematicKind.wolfAttack => '$targetId 号 · 袭击目标已锁定',
    CinematicKind.hunterShot => '$targetId 号 · 猎人的最后一枪',
    CinematicKind.guard => '$targetId 号 · 今夜的守护已落下',
    CinematicKind.heal => '$targetId 号 · 解药已使用',
    CinematicKind.poison => '$targetId 号 · 毒药已使用',
    CinematicKind.reveal => '$targetId 号 · 真相即将揭晓',
    CinematicKind.out => '$targetId 号 · 已出局',
    CinematicKind.goodWin => '好人阵营获胜 · 黎明归来',
    CinematicKind.wolfWin => '狼人阵营获胜 · 月夜永恒',
  };
  String get effect => switch (kind) {
    CinematicKind.wolfAttack => 'bite',
    CinematicKind.hunterShot => 'gunshot',
    CinematicKind.guard => 'shield',
    CinematicKind.heal => 'heal',
    CinematicKind.poison => 'poison',
    CinematicKind.reveal => 'reveal',
    CinematicKind.out => 'out',
    CinematicKind.goodWin => 'victory',
    CinematicKind.wolfWin => 'defeat',
  };
  bool get ending =>
      kind == CinematicKind.goodWin || kind == CinematicKind.wolfWin;

  /// Unrevealed seats use the same neutral villager avatar as the game board.
  /// An action animation must never reveal the target's secret role.
  static Role visibleRole(GameEngine game, Player player) {
    if (!game.local &&
        (player.id == game.me.id ||
            (game.me.role.isWolf && player.role.isWolf))) {
      return player.role;
    }
    if (game.phase == Phase.ended ||
        game.events.any((e) => e.text == '${player.id} 号亮出猎人身份。')) {
      return player.role;
    }
    return Role.villager;
  }

  factory CinematicEvent.forTarget(
    CinematicKind kind,
    GameEngine game,
    Player target, {
    Role actorRole = Role.villager,
  }) => CinematicEvent(
    kind,
    actorRole: actorRole,
    targetRole: visibleRole(game, target),
    targetId: target.id,
    targetName: target.name,
    muteEffect:
        game.local &&
        (kind == CinematicKind.guard ||
            kind == CinematicKind.heal ||
            kind == CinematicKind.poison),
  );
}
