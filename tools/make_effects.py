"""Original procedural game effects, with deterministic noise and safe headroom."""
import array
import math
from pathlib import Path
import random
import wave

OUT = Path(__file__).resolve().parent.parent / 'assets/audio'
SR = 44100

def render(name, seconds, sample):
    rng = random.Random(183)
    data = array.array('h')
    low = 0.0
    for i in range(int(SR * seconds)):
        t = i / SR
        noise = rng.uniform(-1, 1)
        low = .91 * low + .09 * noise
        value = sample(t, noise, low)
        # Avoid pops and clipping; impact comes from the transient, not loudness.
        fade = min(1, t / .003, (seconds - t) / .035)
        data.append(round(max(-.8, min(.8, value * fade)) * 32767))
    with wave.open(str(OUT / f'fx_{name}.wav'), 'w') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR)
        f.writeframes(data.tobytes())

def bell(t, f, start=0, gain=.25):
    d = t - start
    if d < 0: return 0
    return gain * math.exp(-d * 2.4) * (
        math.sin(math.tau * f * d) + .25 * math.sin(math.tau * f * 2.01 * d))

render('gunshot', 1.4, lambda t, n, low:
       .68 * n * math.exp(-t * 23) +
       .34 * math.sin(math.tau * (90 * t - 20 * t * t)) * math.exp(-t * 9) +
       .12 * low * math.exp(-t * 3))
render('bite', 1.2, lambda t, n, low:
       .23 * low * math.sin(math.pi * min(t / .45, 1)) +
       .25 * math.sin(math.tau * (62 * t + 18 * t * t)) * math.exp(-t * 3) +
       (.3 * n * math.exp(-(t - .22) * 25) if t > .22 else 0))
render('shield', 1.8, lambda t, n, low:
       bell(t, 220, gain=.32) + bell(t, 440, .08, .16) + .1 * low * math.exp(-t * 5))
render('heal', 2.0, lambda t, n, low:
       bell(t, 523.25) + bell(t, 659.25, .2) + bell(t, 783.99, .4))
render('poison', 1.8, lambda t, n, low:
       .2 * low * math.sin(math.pi * t / 1.8) +
       .13 * math.sin(math.tau * (130 * t - 32 * t * t)) * math.exp(-t * 1.5))
render('reveal', 2.0, lambda t, n, low:
       bell(t, 659.25) + bell(t, 987.77, .16, .15) + bell(t, 1318.51, .32, .1))
render('out', 2.2, lambda t, n, low:
       bell(t, 110, gain=.35) + .12 * low * math.exp(-t * 2))
render('victory', 3.0, lambda t, n, low:
       sum(bell(t, f, start, .16) for f, start in
           [(261.63, 0), (329.63, .15), (392, .3), (523.25, .65), (659.25, .85)]))
render('defeat', 3.0, lambda t, n, low:
       sum(bell(t, f, start, .2) for f, start in
           [(146.83, 0), (174.61, .2), (220, .4)]) + .09 * low * math.exp(-t))
print('Created 9 original game effects.')
