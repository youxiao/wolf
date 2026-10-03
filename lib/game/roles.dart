import 'package:flutter/material.dart';

enum Role { werewolf, seer, witch, hunter, guard, villager }

extension RoleInfo on Role {
  Rect get figurineFrame => const [
    Rect.fromLTRB(0, 0, 439, 633),
    Rect.fromLTRB(436, 0, 817, 633),
    Rect.fromLTRB(817, 0, 1222, 633),
    Rect.fromLTRB(0, 633, 423, 1287),
    Rect.fromLTRB(421, 633, 836, 1287),
    Rect.fromLTRB(833, 633, 1222, 1287),
  ][index];
  String get title => ['狼人', '预言家', '女巫', '猎人', '守卫', '村民'][index];
  String get english => [
    'THE WEREWOLF',
    'THE SEER',
    'THE WITCH',
    'THE HUNTER',
    'THE GUARDIAN',
    'THE VILLAGER',
  ][index];
  String get asset =>
      'assets/images/${this == Role.hunter ? 'hunter-v2' : name}.png';
  bool get isWolf => this == Role.werewolf;
  bool get isGod => !isWolf && this != Role.villager;
  String get camp => isWolf ? '狼人阵营' : '好人阵营';
  String get skill => ['暗夜袭击', '洞悉真相', '生死灵药', '最后一枪', '月下守护', '明辨是非'][index];
  String get flavor => [
    '月圆之夜，伪装褪去。\n你的獠牙，是村庄最深的秘密。',
    '星辰沉默，水晶低语。\n你是黑暗中唯一看见真相的人。',
    '一瓶救赎，一瓶终结。\n生与死，只在你的一念之间。',
    '即使长夜将你吞没，\n最后一声枪响依然会划破黎明。',
    '站在黑暗与村庄之间，\n用盾牌守住最后一盏灯。',
    '你没有魔法，却拥有判断。\n每一张选票，都能改变命运。',
  ][index];
  String get description => [
    '每晚与狼队共同选择一名玩家袭击。白天隐藏身份，通过发言和投票淘汰好人。狼人胜利条件由设置中的胜负规则决定。',
    '每晚查验一名其他存活玩家，得知其是否属于狼人阵营。善用查验信息，带领好人找出所有狼人。',
    '拥有一瓶解药与一瓶毒药，每瓶全局只能使用一次，每晚最多用一瓶。解药救下当夜被袭击者，毒药使一人出局。仅首夜可以自救。',
    '被狼人袭击或被投票放逐时，可以开枪带走一名存活玩家。被女巫毒杀时不能开枪，也可以选择不开枪。',
    '每晚守护一名玩家，可守护自己，但不能连续两晚守护同一人。同一人同时被守护与解药救治，仍会出局。守护不能挡住毒药。',
    '夜晚没有主动技能。白天通过发言、观察和投票寻找狼人。与神职共同放逐全部狼人，守护村庄；胜负条件由设置中的规则决定。',
  ][index];
  IconData get icon => [
    Icons.pets_rounded,
    Icons.visibility_outlined,
    Icons.science_outlined,
    Icons.my_location_rounded,
    Icons.shield_outlined,
    Icons.wb_sunny_outlined,
  ][index];
  Color get color => [
    const Color(0xFFC77368),
    const Color(0xFF8EBCCA),
    const Color(0xFFB097C4),
    const Color(0xFFC3A576),
    const Color(0xFF87B5A3),
    const Color(0xFFB8AF8B),
  ][index];
}

const rulesText = '''这是无警长局。胜负规则可在设置中选择，默认使用经典屠边。

9 人局：3 狼人、3 村民、预言家、女巫、猎人各 1。
12 人局：4 狼人、4 村民、预言家、女巫、猎人、守卫各 1。

夜晚顺序：守卫 → 狼人 → 预言家 → 女巫。
好人胜利：所有狼人出局。
经典屠边：狼人消灭全部村民或全部神职获胜。
人数制：存活狼人数量大于或等于存活好人数量时，狼人获胜。

女巫：每夜只用一瓶药；仅第一夜能自救。解药用完后，不再得知当夜刀口。
守卫：不能连续守同一人；同守同救会出局；不能阻挡毒药。
猎人：被毒杀不能开枪；枪杀先结算，再判定胜负。
投票：不能投自己，可以弃票；最高票平票则无人出局。
出局玩家不公布身份，猎人发动技能例外。终局公开全部身份。

单人历练：你与离线规则 AI 对战。AI 发言和投票是模拟推理，不是联网大模型。
同屏聚会：所有玩家轮流查看身份和私密操作，请传递设备，其他人闭眼。狼人由一名队友代表操作；白天面对面自由讨论，再依次秘密投票。主持音频不播报私密行动和查验结果。''';
