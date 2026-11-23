"""Generates the game's chiptune sounds (frontend/assets/sounds) from code: pulse, triangle and noise
waves, no recordings. Run from anywhere: python3 frontend/tool/sounds/generate.py [out_dir]
Needs numpy and ffmpeg. Summon timings follow lib/game/screens/pull_reveal_screen.dart.
"""
import math, subprocess, sys, wave
from pathlib import Path
import numpy as np

SR = 44100
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "assets" / "sounds"
OUT.mkdir(parents=True, exist_ok=True)
rng = np.random.default_rng(11)
NOTE = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}
RARITIES = ["basic", "adventurer", "hero", "legend"]


def f(name):
    return 440.0 * 2 ** ((NOTE[name[:-1]] + 12 * (int(name[-1]) + 1) - 69) / 12)


def n_(d): return int(d * SR)
def buf(d): return np.zeros(n_(d))


def env(n, a=0.005, d=0.05, s=0.6, r=0.05):
    e = np.full(n, float(s))
    a, d, r = min(n_(a), n), n_(d), min(n_(r), n)
    e[:a] = np.linspace(0, 1, a, endpoint=False)
    d = min(d, n - a); e[a:a + d] = np.linspace(1, s, d, endpoint=False)
    if r: e[n - r:] *= np.linspace(1, 0, r)
    return e


def expdecay(n, tau): return np.exp(-np.arange(n) / SR / tau)


def phase(freq, dur, slide=None, vib=0.0, vib_rate=6.0):
    tt = np.arange(n_(dur)) / SR
    fr = np.full_like(tt, freq) if slide is None else np.geomspace(freq, slide, len(tt))
    if vib: fr = fr * (1 + vib * np.sin(2 * np.pi * vib_rate * tt))
    return np.cumsum(fr) / SR


def pulse(freq, dur, duty=0.5, **kw): return np.where((phase(freq, dur, **kw) % 1) < duty, 1.0, -1.0)
def tri(freq, dur, **kw): return 4 * np.abs((phase(freq, dur, **kw) % 1) - 0.5) - 1
def fat(freq, dur, duty=0.25, **kw):  # two detuned pulses: the "big" chip lead
    return 0.5 * (pulse(freq * 0.997, dur, duty, **kw) + pulse(freq * 1.003, dur, duty, **kw))


def noise(dur, steps=1):
    v = rng.uniform(-1, 1, n_(dur) // steps + 1)
    return np.repeat(v, steps)[: n_(dur)]


def biquad(x, kind, fc, q=0.7):
    """RBJ biquad; fc may be an array (swept), coefficients updated every 128 samples."""
    fc = np.broadcast_to(np.asarray(fc, float), x.shape)
    y = np.zeros_like(x); x1 = x2 = y1 = y2 = 0.0
    for s in range(0, len(x), 128):
        w = 2 * math.pi * min(fc[s], SR * 0.45) / SR
        c, al = math.cos(w), math.sin(w) / (2 * q)
        if kind == "lp": b = [(1 - c) / 2, 1 - c, (1 - c) / 2]
        elif kind == "hp": b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
        else: b = [al, 0, -al]
        a0 = 1 + al; b0, b1, b2 = (v / a0 for v in b); a1, a2 = -2 * c / a0, (1 - al) / a0
        for i in range(s, min(s + 128, len(x))):
            xi = x[i]; yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2, x1, y2, y1 = x1, xi, y1, yi; y[i] = yi
    return y


def mix(b, sig, at, g=1.0):
    i = n_(at); end = min(len(b), i + len(sig))
    if end > i: b[i:end] += g * sig[: end - i]
    return b


def echo(x, delay=0.12, fb=0.35, taps=4):
    out = np.concatenate([x, np.zeros(n_(delay * taps))])
    for k in range(1, taps + 1): out[n_(delay * k): n_(delay * k) + len(x)] += x * fb ** k
    return out


def save(name, x, gain=0.6, loop=False):
    """Normalises, softly limits and writes [name]: an mp3 for one-shots; a loop is
    a 22 kHz 8-bit wav instead, as mp3 adds silence at its ends and would click."""
    x = np.tanh(x / max(1e-9, np.max(np.abs(x))) * 1.2) / math.tanh(1.2) * gain
    if loop:
        x = x[::2]  # 44.1 kHz to 22.05 kHz, fine for square waves at these pitches
        with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
            w.setnchannels(1); w.setsampwidth(1); w.setframerate(SR // 2)
            w.writeframes(np.clip(x * 127 + 128, 0, 255).astype(np.uint8).tobytes())
        return
    wav = OUT / f"{name}.tmp.wav"
    with wave.open(str(wav), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-ac", "1", "-b:a", "96k",
                    "-map_metadata", "-1", "-fflags", "+bitexact", str(OUT / f"{name}.mp3")], check=True)
    wav.unlink()



def boom(freq=110, end=32, dur=0.7, tau=0.25):
    x = tri(freq, dur, slide=end); return x * expdecay(len(x), tau)


def crash(dur=1.6, tau=0.5, bright=6000):
    x = biquad(noise(dur), "hp", bright, 0.6); return x * expdecay(len(x), tau)


def box_land():
    b = buf(1.1)
    mix(b, boom(140, 30, 0.6, 0.18), 0, 1.0)                                    # the weight
    thud = biquad(noise(0.25, 2), "lp", 500, 0.9); mix(b, thud * expdecay(len(thud), 0.05), 0, 1.2)
    slap = biquad(noise(0.08), "bp", 1800, 1.2); mix(b, slap * expdecay(len(slap), 0.015), 0, 0.7)  # cardboard
    for at, g in [(0.16, 0.45), (0.27, 0.2)]:                                   # little bounces
        mix(b, boom(120, 40, 0.25, 0.06), at, g)
        s = biquad(noise(0.05), "bp", 1400, 1.5); mix(b, s * expdecay(len(s), 0.01), at, g)
    for k in range(6):                                                          # dust settling rattle
        s = biquad(noise(0.02), "bp", 3000 + 400 * k, 2); mix(b, s * expdecay(len(s), 0.004), 0.32 + 0.045 * k, 0.15)
    return b


def tape_rip(dur=0.9):
    """Packing tape torn off along the cut: crackling bursts that speed up, swept upwards."""
    n = n_(dur); tt = np.arange(n) / SR
    rate = 70 + 180 * (tt / dur)                                                # crackles per second, accelerating
    clicks = np.zeros(n); pos = 0.0
    while pos < dur:
        i = n_(pos)
        if i < n: clicks[i] = rng.uniform(0.4, 1.0)
        pos += 1 / rate[min(i, n - 1)] * rng.uniform(0.5, 1.5)
    grain = np.convolve(clicks, expdecay(n_(0.006), 0.0015), "same")
    x = noise(dur) * grain
    x = biquad(x, "bp", np.geomspace(1500, 4500, n), 0.9) * 1.5 + biquad(noise(dur), "bp", np.geomspace(800, 3000, n), 1.0) * 0.15
    shape = np.clip(tt / 0.05, 0, 1) * np.clip((dur - tt) / 0.04, 0, 1)
    return x * shape


def cut_done(r):
    b = buf(0.6)                                                                # the tape snapping free + a chip "ting"
    s = biquad(noise(0.06), "bp", 2500, 1.5); mix(b, s * expdecay(len(s), 0.01), 0)
    for i, n in enumerate(["C6", "G6"][: 1 + (r >= 2)]):
        x = pulse(f(n), 0.4, 0.125); mix(b, 0.3 * x * expdecay(len(x), 0.1), 0.02 + 0.06 * i)
    return b


def shake(r):
    dur = 0.5 + 0.35 * r
    b = buf(dur + 0.2); tt = 0.0; k = 0
    while tt < dur:                                                             # knocks, faster and harder
        prog = tt / dur
        g = 0.35 + 0.65 * prog
        mix(b, boom(90 + 30 * (k % 2), 45, 0.12, 0.03), tt, 0.7 * g)
        s = biquad(noise(0.04), "bp", 1200 + 600 * (k % 3), 1.4); mix(b, s * expdecay(len(s), 0.008), tt, 0.5 * g)
        tt += 0.11 - 0.06 * prog; k += 1
    riser = fat(f("C4"), dur, 0.25, slide=f("C4") * (2 ** (1 + r * 0.5)), vib=0.02 + 0.01 * r, vib_rate=8 + 4 * r)
    mix(b, riser * np.linspace(0, 1, len(riser)) ** 2, 0, 0.18 + 0.06 * r)
    hiss = biquad(noise(dur), "hp", np.geomspace(2000, 8000, n_(dur)), 0.7)
    mix(b, hiss * np.linspace(0, 1, len(hiss)) ** 3, 0, 0.15 + 0.1 * r)
    return b


def flaps_open(r):
    hold = [0.15, 0.3, 0.5, 0.8][r]
    b = buf(1.0 + hold + 1.5)
    mix(b, boom(160, 28, 0.8 + hold, 0.25 + 0.3 * hold), 0, 1.0)
    whomp = biquad(noise(0.4 + hold, 2), "lp", np.geomspace(1500, 200, n_(0.4 + hold)), 0.8)
    mix(b, whomp * expdecay(len(whomp), 0.1 + 0.15 * hold), 0, 1.0)
    for i in range(2):                                                          # two flaps flicking out
        s = biquad(noise(0.07), "bp", 900 + 500 * i, 1.2); mix(b, s * expdecay(len(s), 0.02), 0.04 + 0.07 * i, 0.6)
    if r >= 2: mix(b, crash(1.5 + 0.5 * (r - 2), 0.4 + 0.3 * (r - 2)), 0, 0.35)
    return b


def beam(r):
    dur = 1.3
    b = buf(dur + 0.6)
    swell = biquad(noise(dur), "bp", np.geomspace(600, 9000, n_(dur)), 1.2)
    mix(b, swell * np.linspace(0, 1, len(swell)) ** 1.5, 0, 0.35)
    scale = ["C", "E", "G"] + (["B"] if r >= 3 else [])
    notes = [f"{p}{o}" for o in range(4, 6 + (r >= 2)) for p in scale]
    step = dur / len(notes)
    for i, n in enumerate(notes):                                              # glittering climb
        x = pulse(f(n), step * 3, 0.125); mix(b, x * expdecay(len(x), step * 1.2), i * step, 0.2)
    pad = sum(fat(f(n), dur, 0.5, vib=0.006) for n in ["C4", "G4", "C5"] + (["E5"] if r >= 1 else []))
    mix(b, pad * np.linspace(0, 1, len(pad)) ** 2, 0, 0.12 + 0.03 * r)
    return b


def flip():
    b = buf(0.7)
    w = biquad(noise(0.35), "bp", np.geomspace(800, 6000, n_(0.35)), 1.5)
    mix(b, w * np.sin(np.linspace(0, np.pi, len(w))), 0, 0.6)
    x = pulse(f("G6"), 0.3, 0.25); mix(b, x * expdecay(len(x), 0.08), 0.3, 0.25)
    return b


def burst(r):
    if r == 0:
        b = buf(1.2); hits = [(0, ["C5", "E5", "G5"], 0.7)]; bass = [("C3", 0, 0.7)]
    elif r == 1:
        b = buf(1.6); hits = [(0, ["G4", "C5", "E5"], 0.15), (0.17, ["C5", "E5", "G5", "C6"], 1.0)]; bass = [("C3", 0.17, 1.0)]
    elif r == 2:
        b = buf(2.6)
        hits = [(0, ["F4", "A4", "C5"], 0.2), (0.22, ["G4", "B4", "D5"], 0.2), (0.44, ["C5", "E5", "G5", "C6"], 1.6)]
        bass = [("F2", 0, 0.2), ("G2", 0.22, 0.2), ("C2", 0.44, 1.6)]
    else:
        b = buf(4.2)
        hits = [(0, ["C5", "E5", "G5"], 0.14), (0.16, ["C5", "E5", "G5"], 0.14), (0.32, ["C5", "E5", "G5"], 0.14),
                (0.5, ["A#4", "D5", "F5"], 0.4), (0.92, ["C5", "E5", "G5", "C6"], 0.14), (1.08, ["D5", "F#5", "A5", "D6"], 2.2)]
        bass = [("C2", 0, .45), ("A#1", 0.5, 0.4), ("C2", 0.92, 0.14), ("D2", 1.08, 2.2)]
    for at, chord, d in hits:
        for n in chord:
            x = fat(f(n), d + 0.3, 0.25, vib=0.008 if d > 0.5 else 0)
            mix(b, x * env(len(x), 0.004, 0.08, 0.55, 0.3), at, 0.22)
    for n, at, d in bass:
        x = tri(f(n), d + 0.2); mix(b, x * env(len(x), 0.003, 0.05, 0.8, 0.15), at, 0.6)
        mix(b, boom(130, 40, 0.4, 0.1), at, 0.5)
    last = hits[-1][0]
    if r >= 1: mix(b, crash(1.2 + 0.5 * r, 0.3 + 0.2 * r), last, 0.2 + 0.08 * r)
    if r >= 2:                                                                  # sparkles falling around the card
        top = hits[-1][1]
        for i in range(6 + 4 * (r - 2)):
            n = top[i % len(top)][:-1] + str(6 + (i % 2) + (r == 3 and i % 3 == 0))
            x = pulse(f(n), 0.12, 0.125); mix(b, x * expdecay(len(x), 0.04), last + 0.15 + i * 0.11, 0.12)
    if r == 3:                                                                  # timpani roll into the last chord
        for k in range(10): mix(b, boom(95, 60, 0.2, 0.05), 0.5 + k * 0.042, 0.25 + k * 0.03)
    return echo(b, 0.14, 0.25 + 0.05 * r, 3) if r >= 2 else b




def blip(note, dur, duty=0.5, a=0.002, d=0.04, s=0.5, r=0.03, **kw):
    x = pulse(f(note), dur, duty, **kw)
    return x * env(len(x), a, d, s, r)


def arp(notes, step, duty=0.25, tail=0.1, **kw):
    b = buf(step * len(notes) + tail)
    for i, n in enumerate(notes):
        mix(b, blip(n, step + tail, duty, s=0.4, r=tail, **kw), i * step)
    return b


def tape_loop(dur=1.0):
    """The tape tearing at a steady pace, seamless: played while the cut moves."""
    n = n_(dur)
    clicks = np.zeros(n); pos = 0.0
    while pos < dur:
        clicks[min(n_(pos), n - 1)] = rng.uniform(0.4, 1.0)
        pos += 1 / 160 * rng.uniform(0.5, 1.5)
    k = expdecay(n_(0.006), 0.0015)
    grain = np.convolve(np.concatenate([clicks, clicks]), k)[n: 2 * n]  # wrapped, so it loops
    x = biquad(np.tile(noise(dur), 3) * np.tile(grain, 3), "bp", 2800, 0.9)[n: 2 * n] * 1.5
    x += biquad(np.tile(noise(dur), 3), "bp", 1600, 1.0)[n: 2 * n] * 0.15
    return x


def music():
    """16 bars at 120 bpm (C – Am – F – G), every tail wrapped round so it loops seamlessly."""
    beat, bars = 0.5, 16
    out = buf(bars * 4 * beat)

    def place(sig, at):
        i = n_(at) % len(out); end = i + len(sig)
        if end <= len(out): out[i:end] += sig
        else:
            cut = len(out) - i; out[i:] += sig[:cut]; out[: len(sig) - cut] += sig[cut:]

    a = [("G4", .5), ("C5", .5), ("E5", 1), ("D5", .5), ("C5", .5), ("E5", 1), ("G5", 1.5), ("E5", .5), ("D5", 1), ("C5", 1),
         ("A4", .5), ("C5", .5), ("E5", 1), ("D5", .5), ("C5", .5), ("A4", 1), ("E5", 2), ("D5", 1), ("C5", 1),
         ("F5", 1), ("E5", .5), ("D5", .5), ("C5", 1), ("A4", 1), ("C5", 1.5), ("D5", .5), ("E5", 1), ("F5", 1)]
    melody = a + [("G5", 1), ("F5", .5), ("E5", .5), ("D5", 1), ("B4", 1), ("D5", 2), ("G4", 1), ("B4", 1)] \
        + a + [("G5", 1), ("A5", .5), ("G5", .5), ("F5", 1), ("D5", 1), ("B4", 1), ("D5", 1), ("G5", 2)]
    pos = 0.0
    for note, d in melody:
        x = pulse(f(note), d * beat, 0.5, vib=0.006 if d >= 1.5 else 0)
        place(0.22 * x * env(len(x), 0.004, 0.06, 0.55, 0.03), pos); pos += d * beat
    chords = [("C", ["C", "E", "G"]), ("A", ["A", "C", "E"]), ("F", ["F", "A", "C"]), ("G", ["G", "B", "D"])]
    for bar in range(bars):
        root, tones = chords[(bar // 2) % 4]; t0 = bar * 4 * beat
        for e in range(8):
            x = tri(f(root + "2") * (2 if e % 2 else 1), beat / 2)
            place(0.45 * x * env(len(x), 0.003, 0.03, 0.8, 0.02), t0 + e * beat / 2)
        for s in range(16):
            tn = tones[s % 3]
            x = pulse(f(tn + ("5" if tn in "CDE" and root in "AG" else "4")), beat / 4, 0.125)
            place(0.06 * x * env(len(x), 0.002, 0.03, 0.4, 0.02), t0 + s * beat / 4)
        for b8 in range(8):
            at = t0 + b8 * beat / 2
            if b8 % 4 == 0: x = tri(150, 0.12, slide=45); place(0.6 * x * env(len(x), 0.001, 0.1, 0.0, 0.01), at)
            if b8 % 4 == 2: x = noise(0.12, 3); place(0.22 * x * env(len(x), 0.001, 0.1, 0.0, 0.01), at)
            x = noise(0.03, 1); place(0.06 * x * env(len(x), 0.001, 0.02, 0.0, 0.005), at)
    return out


# ---------------------------------------------------------------- output
RARITIES = ["basic", "adventurer", "hero", "legend"]

# Drawing
tick = noise(0.03, steps=4) * env(n_(0.03), 0.001, 0.02, 0.0, 0.005)
save("timer_tick", tick, 0.25)
save("timer_final", blip("A5", 0.12, 0.5, s=0.5, r=0.04), 0.4)
b = buf(1.1)
for i in range(3): mix(b, blip("C5", 0.18, 0.5, s=0.7, r=0.03), i * 0.2)
x = pulse(f("A4"), 0.5, 0.5, slide=f("A3")); mix(b, x * env(len(x), 0.005, 0.1, 0.6, 0.15), 0.6)
save("time_up", b, 0.45)
save("drawing_saved", arp(["G5", "C6"], 0.09, 0.5, tail=0.25), 0.4)

# Boost
save("star_drop", arp(["E6", "G6", "C7"], 0.04, 0.125, tail=0.12), 0.4)

# Fights
b = buf(2.0)
for n, at, d in [("G4", 0, .12), ("G4", .13, .12), ("G4", .26, .12), ("C5", .4, .3), ("G4", .72, .15), ("C5", .88, .9)]:
    mix(b, blip(n, d, 0.5, s=0.6, r=0.04, vib=0.01 if d > .5 else 0), at)
    mix(b, 0.5 * blip("C5" if n == "G4" else "E5", d, 0.25, s=0.5, r=0.04), at)
x = tri(f("C3"), 1.0); mix(b, 0.6 * x * env(len(x), 0.005, 0.1, 0.6, 0.3), 0.88)
save("fight_win", b, 0.5)
b = buf(2.0)
for i, n in enumerate(["G4", "F#4", "F4"]): mix(b, blip(n, 0.3, 0.5, s=0.6, r=0.06), i * 0.32)
x = pulse(f("E4"), 0.9, 0.5, slide=f("D#4"), vib=0.02); mix(b, x * env(len(x), 0.005, 0.1, 0.6, 0.4), 0.96)
x = tri(f("C3"), 0.9, slide=f("B2")); mix(b, 0.6 * x * env(len(x), 0.005, 0.1, 0.6, 0.4), 0.96)
save("fight_lose", b, 0.45)

# Summon
save("summon_land", box_land())
save("summon_tape", tape_loop(), 0.5, loop=True)
save("summon_cut", cut_done(2), 0.45)
for r, name in enumerate(RARITIES):
    save(f"summon_shake_{name}", shake(r), 0.55)
    save(f"summon_open_{name}", flaps_open(r), 0.65)
    save(f"summon_beam_{name}", beam(r), 0.5)
    save(f"summon_reveal_{name}", burst(r), 0.6)
save("summon_flip", flip(), 0.45)

# Music
save("music", music(), 0.5, loop=True)
# Buttons: a mechanical switch, a sharp click over a low body knock, then a
# softer one as it springs back. The main buttons clack deeper and harder.
def switch(click_hz, body_hz, release_at, heavy=0.0):
    b = buf(0.14)
    c = biquad(noise(0.012), "bp", click_hz, 1.4); mix(b, c * expdecay(len(c), 0.0018), 0, 1.0)
    x = tri(body_hz, 0.05, slide=body_hz * 0.7); mix(b, x * expdecay(len(x), 0.009 + 0.006 * heavy), 0, 0.8 + 0.4 * heavy)
    k = biquad(noise(0.03, 2), "lp", 700, 0.8); mix(b, k * expdecay(len(k), 0.006), 0.001, 0.5 + 0.5 * heavy)
    r = biquad(noise(0.008), "bp", click_hz * 1.15, 1.6); mix(b, r * expdecay(len(r), 0.0012), release_at, 0.35)
    return b


save("ui_tap", switch(1700, 210, 0.065), 0.4)
save("ui_confirm", switch(1300, 140, 0.075, heavy=1.0), 0.48)

# Fights
b = buf(1.0)                                                                    # the challenger drops onto the stage
mix(b, boom(120, 26, 0.9, 0.22), 0, 1.0)
d = biquad(noise(0.5, 2), "lp", np.geomspace(1200, 150, n_(0.5)), 0.8); mix(b, d * expdecay(len(d), 0.12), 0, 0.9)
save("fight_drop", b, 0.6)
x = pulse(f("C4"), 0.22, 0.25, slide=f("C5"))                                  # a fighter rises into line
w = biquad(noise(0.22), "bp", np.geomspace(500, 2500, n_(0.22)), 1.2)
save("fight_rise", 0.35 * x * env(len(x), 0.01, 0.05, 0.6, 0.08) + 0.6 * w * np.sin(np.linspace(0, np.pi, len(w))), 0.35)
b = buf(1.6)                                                                    # "Fight!"
for n in ["C4", "G4", "C5", "E5"]:
    x = fat(f(n), 0.9, 0.25, vib=0.01); mix(b, x * env(len(x), 0.003, 0.08, 0.5, 0.5), 0, 0.25)
mix(b, boom(150, 50, 0.4, 0.1), 0, 0.6); mix(b, crash(1.5, 0.45), 0, 0.35)
save("fight_call", b, 0.55)
w = biquad(noise(0.2), "bp", np.geomspace(700, 3500, n_(0.2)), 1.3)             # a swing
save("fight_swing", w * np.sin(np.linspace(0, np.pi, len(w))) ** 2, 0.3)


def punch(hard):
    b = buf(0.5 + 0.3 * hard)
    mix(b, boom(170 - 40 * hard, 40, 0.3 + 0.2 * hard, 0.06 + 0.06 * hard), 0, 1.0)
    k = biquad(noise(0.15 + 0.1 * hard, 2), "lp", 1400 - 400 * hard, 0.9); mix(b, k * expdecay(len(k), 0.03 + 0.03 * hard), 0, 1.0)
    c = pulse(f("A5") if not hard else f("E5"), 0.06, 0.125, slide=f("A3")); mix(b, c * expdecay(len(c), 0.02), 0, 0.3)
    if hard: mix(b, crash(0.5, 0.12, 4000), 0, 0.25)
    return b


save("fight_hit", punch(0), 0.5)
save("fight_hit_hard", punch(1), 0.58)
b = buf(2.2)                                                                    # the knockout blow, in slow motion
mix(b, punch(1), 0, 1.0)
mix(b, boom(90, 24, 1.4, 0.45), 0.02, 0.8)
x = fat(f("C5"), 1.2, 0.25, slide=f("C3")); mix(b, x * env(len(x), 0.005, 0.2, 0.5, 0.6), 0.05, 0.25)
mix(b, crash(1.8, 0.6), 0, 0.3)
save("fight_ko", b, 0.62)

# Rewards
b = buf(1.2)                                                                    # pulls or stars received
for i, n in enumerate(["B5", "E6"]):
    mix(b, blip(n, 0.09 if i == 0 else 0.5, 0.5, s=0.5, r=0.4 if i else 0.02), 0.07 * i, 0.5)
for i, n in enumerate(["E6", "G#6", "B6", "E7"]):
    x = pulse(f(n), 0.15, 0.125); mix(b, x * expdecay(len(x), 0.05), 0.2 + 0.06 * i, 0.15)
save("reward", b, 0.45)
b = buf(2.0)                                                                    # an upgrade unlocked
mix(b, arp(["C5", "E5", "G5", "C6", "E6", "G6"], 0.05, 0.25, tail=0.08), 0, 1.0)
for n in ["C5", "E5", "G5", "C6"]:
    x = fat(f(n), 1.0, 0.25, vib=0.008); mix(b, 0.3 * x * env(len(x), 0.01, 0.15, 0.5, 0.6), 0.3)
for i, n in enumerate(["C7", "G7", "E7", "C8"]):
    mix(b, 0.25 * blip(n, 0.08, 0.125, s=0.2, r=0.05), 0.45 + i * 0.12)
save("unlock", echo(b, 0.13, 0.25, 2), 0.5)
print("written to", OUT)
