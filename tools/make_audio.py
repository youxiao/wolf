"""Rebuild original local ambience and Chinese host audio using macOS Speech."""
import argparse, array, json, math, pathlib, random, subprocess, wave
ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / 'assets/audio'
OUT.mkdir(parents=True, exist_ok=True)
LINES = {
    'welcome': '欢迎来到月隐。月光之下，每个人都有一个秘密。',
    'deal': '命运已经写下。请独自查看你的身份，并记住你的使命。',
    'night': '天黑，请闭眼。让村庄的灯火，暂时沉入夜色。',
    'guard': '守卫，请睁眼。请选择今晚你要守护的人。',
    'wolves': '狼人，请睁眼。请选择今晚你们要袭击的目标。',
    'seer': '预言家，请睁眼。请选择一位玩家，查验他的身份。',
    'witch': '女巫，请睁眼。今夜，你是否要使用你的药剂？',
    'dawn': '天亮了，请所有人睁眼。',
    'night_done': '行动已经记录。请确认行动完成，随后闭眼，将设备交回。',
    'guard_close': '守卫，请闭眼。',
    'wolves_close': '狼人，请闭眼。',
    'seer_close': '预言家，请闭眼。',
    'witch_close': '女巫，请闭眼。',
    'deaths_intro': '昨夜出局的玩家是，',
    'deaths_outro': '出局玩家请保持旁观，不再参与发言和投票。',
    'discussion': '现在开始白天发言。请倾听，也请谨慎判断。',
    'vote': '发言结束。请选择你要放逐的玩家，或者弃票。',
    'hunter': '猎人，请决定是否发动你的最后一枪。',
    'good': '所有狼人已经出局。好人阵营获胜。村庄终于迎来了黎明。',
    'wolf': '最后的灯火熄灭。狼人阵营获胜。长夜，仍将继续。',
    'peace': '昨夜是一个平安夜。',
    'werewolf_lore': '狼人。月圆之夜，伪装褪去。你的獠牙，是村庄最深的秘密。',
    'seer_lore': '预言家。星辰沉默，水晶低语。你是黑暗中唯一看见真相的人。',
    'witch_lore': '女巫。一瓶救赎，一瓶终结。生与死，只在你的一念之间。',
    'hunter_lore': '猎人。即使长夜将你吞没，最后一声枪响依然会划破黎明。',
    'guard_lore': '守卫。站在黑暗与村庄之间，用盾牌守住最后一盏灯。',
    'villager_lore': '村民。你没有魔法，却拥有判断。每一张选票，都能改变命运。',
}
NUMBERS = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十', '十一', '十二']
LINES.update({f'seat_{i}': f'{number}号，' for i, number in enumerate(NUMBERS, 1)})
parser = argparse.ArgumentParser()
parser.add_argument('--only', nargs='+', help='Only rebuild these voice clips; skip ambience')
args = parser.parse_args()
(OUT / 'transcripts.json').write_text(json.dumps(LINES, ensure_ascii=False, indent=2))
for key, line in LINES.items():
    if args.only and key not in args.only:
        continue
    temp = OUT / f'{key}.aiff'
    subprocess.run(['say', '-v', 'Tingting', '-r', '155', '-o', str(temp), line], check=True)
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', str(temp), '-af', 'volume=0.85', '-codec:a', 'libmp3lame', '-b:a', '96k', str(OUT / f'{key}.mp3')], check=True)
    temp.unlink()
if args.only:
    print(f'Created {len(args.only)} voice clips.')
    raise SystemExit(0)
# Original synthesized nocturnal soundscape: quiet wind, slowly beating pads,
# and sparse distant bell harmonics. No third-party music or samples.
sr, duration = 22050, 40
rng = random.Random(42)
data = array.array('h')
wind = 0.0
for n in range(sr * duration):
    t = n / sr
    wind = .98 * wind + .02 * rng.uniform(-1, 1)
    drone = sum(math.sin(2 * math.pi * f * t) for f in [65.4, 98.0, 130.8, 196.0]) / 4
    envelope = .55 + .2 * math.cos(2 * math.pi * t / duration)
    bell = 0
    for start, freq in [(3, 523.25), (13, 392), (24, 440), (33, 329.63)]:
        dt = t - start
        if dt >= 0:
            bell += math.exp(-dt / 2.7) * (math.sin(2 * math.pi * freq * dt) + .25 * math.sin(2 * math.pi * freq * 2.01 * dt))
    sample = .12 * drone * envelope + .15 * wind + .025 * bell
    fade = min(1, t / 2, (duration - t) / 2)
    data.append(int(max(-1, min(1, sample * fade)) * 32767))
with wave.open(str(OUT / 'ambience.wav'), 'w') as f:
    f.setnchannels(1); f.setsampwidth(2); f.setframerate(sr); f.writeframes(data.tobytes())
subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', str(OUT / 'ambience.wav'), '-codec:a', 'libmp3lame', '-b:a', '96k', str(OUT / 'ambience.mp3')], check=True)
(OUT / 'ambience.wav').unlink()
print(f'Created {len(LINES)} Chinese voice clips and original ambience.')
