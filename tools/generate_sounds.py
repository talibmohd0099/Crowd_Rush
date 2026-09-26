#!/usr/bin/env python3
"""
Procedural sound generator for CROWD RUSH prototype.

Every sound effect and both music loops in assets/sounds/ are synthesized by
this script, so the prototype ships with zero third-party audio.
Run:  python3 tools/generate_sounds.py
Requires: numpy
Output: 22.05 kHz mono 16-bit WAV (small + mobile friendly).
Replace any file with a real recording later - keep the same file name.
"""
import os
import wave
import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sounds")
rng = np.random.default_rng(1234)


# ---------------------------------------------------------------- helpers
def tvec(dur):
    return np.arange(int(SR * dur)) / SR


def silence(dur):
    return np.zeros(int(SR * dur))


def noise(dur):
    return rng.uniform(-1.0, 1.0, int(SR * dur))


def lowpass(x, cutoff):
    """One-pole low-pass. cutoff may be scalar or per-sample array."""
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    a = 1.0 - np.exp(-2.0 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def bandpass(x, lo, hi):
    return highpass(lowpass(x, hi), lo)


def exp_env(dur, decay, attack=0.002):
    t = tvec(dur)
    env = np.exp(-t / max(decay, 1e-4))
    a = int(SR * attack)
    if a > 0:
        env[:a] *= np.linspace(0, 1, a)
    return env


def sine(freq, dur, phase=0.0):
    t = tvec(dur)
    if np.ndim(freq) == 0:
        return np.sin(2 * np.pi * freq * t + phase)
    ph = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(ph + phase)


def saw(freq, dur, harmonics=12):
    t = tvec(dur)
    freq = np.broadcast_to(np.asarray(freq, dtype=float), t.shape)
    ph = 2 * np.pi * np.cumsum(freq) / SR
    out = np.zeros_like(t)
    for k in range(1, harmonics + 1):
        out += ((-1) ** (k + 1)) * np.sin(k * ph) / k
    return out * 0.6


def square(freq, dur, harmonics=9):
    t = tvec(dur)
    freq = np.broadcast_to(np.asarray(freq, dtype=float), t.shape)
    ph = 2 * np.pi * np.cumsum(freq) / SR
    out = np.zeros_like(t)
    for k in range(1, harmonics * 2, 2):
        out += np.sin(k * ph) / k
    return out * 0.8


def mix_at(dst, src, start_s, gain=1.0):
    s = int(start_s * SR)
    if s >= len(dst):
        return dst
    e = min(len(dst), s + len(src))
    dst[s:e] += src[: e - s] * gain
    return dst


def fade(x, fin=0.005, fout=0.02):
    x = x.copy()
    a = int(SR * fin)
    b = int(SR * fout)
    if a > 0:
        x[:a] *= np.linspace(0, 1, a)
    if b > 0:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def normalize(x, peak=0.89):
    m = np.max(np.abs(x))
    return x if m < 1e-9 else x * (peak / m)


def soft_clip(x, drive=1.5):
    return np.tanh(x * drive) / np.tanh(drive)


def write(name, x, peak=0.89):
    x = normalize(x, peak)
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", path, "%.2fs" % (len(x) / SR))


def note(n):
    """MIDI note -> Hz"""
    return 440.0 * 2 ** ((n - 69) / 12.0)


# ---------------------------------------------------------------- drums
def kick(dur=0.35, f0=120, f1=42, drive=2.0):
    t = tvec(dur)
    freq = f1 + (f0 - f1) * np.exp(-t / 0.045)
    body = sine(freq, dur) * exp_env(dur, 0.12)
    click = lowpass(noise(dur), 3000) * exp_env(dur, 0.006) * 0.4
    return soft_clip(body + click, drive)


def snare(dur=0.25):
    n = bandpass(noise(dur), 900, 7000) * exp_env(dur, 0.07)
    tone = sine(190, dur) * exp_env(dur, 0.04) * 0.5
    return n + tone


def clap(dur=0.3):
    out = np.zeros(int(SR * dur))
    for off in (0.0, 0.012, 0.024):
        mix_at(out, bandpass(noise(dur), 1000, 5000) * exp_env(dur, 0.05), off, 0.6)
    return out


def hat(dur=0.06, open_=False):
    d = 0.22 if open_ else dur
    return highpass(noise(d), 6000) * exp_env(d, 0.08 if open_ else 0.015) * 0.5


def tom(freq=90, dur=0.5):
    t = tvec(dur)
    f = freq * (1 + 0.6 * np.exp(-t / 0.05))
    return soft_clip(sine(f, dur) * exp_env(dur, 0.18) + lowpass(noise(dur), 1500) * exp_env(dur, 0.02) * 0.3, 1.6)


def pluck(freq, dur=0.25, bright=4000):
    x = saw(freq, dur, 10) * 0.6 + square(freq * 2, dur, 5) * 0.15
    cut = 400 + bright * np.exp(-tvec(dur) / 0.06)
    return lowpass(x, cut) * exp_env(dur, 0.12)


def bass(freq, dur=0.2):
    x = saw(freq, dur, 8) * 0.7 + sine(freq / 2, dur) * 0.5
    cut = 250 + 1400 * np.exp(-tvec(dur) / 0.05)
    return soft_clip(lowpass(x, cut) * exp_env(dur, 0.3, 0.004), 1.4)


# ---------------------------------------------------------------- SFX
def sfx_rumble():
    d = 3.2
    x = lowpass(noise(d), 90) * 6 + sine(34 + 3 * sine(0.4, d), d) * 0.35
    env = np.minimum(1, tvec(d) / 1.2) * np.minimum(1, (d - tvec(d)) / 1.0)
    return x * env


def sfx_city_ambience():
    d = 8.0
    base = lowpass(noise(d), 350) * 2.0
    hiss = bandpass(noise(d), 1500, 4000) * 0.05
    wobble = 0.7 + 0.3 * sine(0.25, d)
    x = base * wobble + hiss
    # distant horns / clanks
    mix_at(x, (square(note(58), 0.5, 5) * 0.3 + square(note(62), 0.5, 5) * 0.2) * exp_env(0.5, 0.3), 2.1, 0.12)
    mix_at(x, bandpass(noise(0.3), 2000, 5000) * exp_env(0.3, 0.05), 5.4, 0.2)
    mix_at(x, lowpass(sine(note(46), 0.8), 400) * exp_env(0.8, 0.4), 6.6, 0.12)
    # seamless loop: crossfade tail into head
    n = int(SR * 0.5)
    head = x[:n].copy()
    x[:n] = head * np.linspace(0, 1, n) + x[-n:] * np.linspace(1, 0, n)
    return x[:-n]


def sfx_whoosh(d=0.55, lo=300, hi=3200, gain=1.0):
    t = tvec(d)
    center = lo + (hi - lo) * np.sin(np.pi * t / d) ** 2
    x = lowpass(noise(d), center) - lowpass(noise(d), center * 0.3) * 0.5
    env = np.sin(np.pi * t / d) ** 1.5
    return x * env * gain


def sfx_impact_distant():
    d = 1.6
    return lowpass(kick(d, 80, 28, 1.2), 600) + lowpass(noise(d), 200) * exp_env(d, 0.4) * 1.5


def sfx_footstep():
    d = 0.12
    return lowpass(noise(d), 900) * exp_env(d, 0.025) + sine(95, d) * exp_env(d, 0.03) * 0.5


def sfx_footsteps_loop():
    """Soft crowd patter loop (1.2s). Volume is scaled by crowd size at runtime."""
    d = 1.2
    x = np.zeros(int(SR * d))
    step = sfx_footstep()
    times = np.sort(rng.uniform(0, d - 0.12, 22))
    for tt in times:
        mix_at(x, lowpass(step, rng.uniform(500, 1400)), tt, rng.uniform(0.3, 1.0))
    # cloth rustle bed
    x += bandpass(noise(d), 800, 3000) * 0.04
    return x


def sfx_gate_positive():
    d = 0.6
    t = tvec(d)
    pop = sine(700 * np.exp(-t / 0.03) + 500, d) * exp_env(d, 0.05)
    f = 520 * (1 + t * 1.6)
    tone = (sine(f, d) + 0.4 * sine(f * 2, d) + 0.2 * sine(f * 3, d)) * exp_env(d, 0.25, 0.01)
    shimmer = highpass(noise(d), 5000) * exp_env(d, 0.12) * 0.15
    return pop * 0.8 + tone * 0.6 + shimmer


def sfx_gate_negative():
    d = 0.6
    t = tvec(d)
    thud = kick(d, 140, 45, 2.5) * 0.9
    buzz = lowpass(square(np.where(t % 0.16 < 0.08, 220, 185), d, 6), 1800) * exp_env(d, 0.25, 0.01) * 0.35
    return thud + buzz


def sfx_multiply():
    d = 0.95
    t = tvec(d)
    x = sfx_whoosh(d, 400, 5000, 0.8)
    pop = sine(900 * np.exp(-t / 0.02) + 400, d) * exp_env(d, 0.06)
    mix_at(x, pop, 0.12, 1.0)
    for i, n in enumerate([72, 76, 79, 84, 88]):
        mix_at(x, (sine(note(n), 0.35) + 0.3 * sine(note(n) * 2, 0.35)) * exp_env(0.35, 0.12), 0.14 + i * 0.05, 0.45)
    mix_at(x, highpass(noise(0.6), 6000) * exp_env(0.6, 0.18), 0.2, 0.25)
    mix_at(x, kick(0.3, 180, 60, 1.5), 0.12, 0.5)
    return x


def sfx_pop():
    d = 0.14
    t = tvec(d)
    return sine(1100 * np.exp(-t / 0.015) + 350, d) * exp_env(d, 0.035)


def sfx_sparkle():
    d = 0.7
    x = np.zeros(int(SR * d))
    for i in range(7):
        f = note(int(rng.integers(84, 98)))
        mix_at(x, sine(f, 0.25) * exp_env(0.25, 0.06), i * 0.06 + rng.uniform(0, 0.02), 0.5)
    return x


def sfx_wood_impact():
    d = 0.9
    x = kick(d, 150, 55, 2.0) * 0.7
    for i in range(6):
        f = rng.uniform(300, 900)
        mix_at(x, bandpass(noise(0.2), f * 0.7, f * 2.5) * exp_env(0.2, 0.04), rng.uniform(0, 0.25), 0.7)
    mix_at(x, sine(420, 0.3) * exp_env(0.3, 0.05), 0.0, 0.3)
    return x


def sfx_thud():
    d = 0.35
    return kick(d, 110, 40, 1.8) + lowpass(noise(d), 800) * exp_env(d, 0.04) * 0.5


def sfx_boss_roar():
    d = 2.0
    t = tvec(d)
    f = 62 + 14 * np.sin(np.pi * t / d) + 3 * np.sin(2 * np.pi * 11 * t)
    x = saw(f, d, 24) + saw(f * 1.5, d, 16) * 0.4
    grit = bandpass(noise(d), 300, 2500) * (0.6 + 0.4 * np.sin(2 * np.pi * 23 * t))
    x = lowpass(x + grit * 0.6, 900 + 900 * np.sin(np.pi * t / d))
    env = np.minimum(1, t / 0.25) * np.minimum(1, (d - t) / 0.6)
    return soft_clip(x * env, 2.0)


def sfx_boss_step():
    d = 0.6
    return kick(d, 70, 30, 2.5) + lowpass(noise(d), 300) * exp_env(d, 0.12) * 1.2


def sfx_weapon_swing():
    return sfx_whoosh(0.6, 150, 1600, 1.0) + sfx_whoosh(0.6, 80, 600, 0.6)


def sfx_ground_slam():
    d = 1.8
    x = kick(d, 90, 26, 3.0) * 1.2
    x += lowpass(noise(d), 500) * exp_env(d, 0.35) * 1.4
    for i in range(10):
        mix_at(x, bandpass(noise(0.25), 600, 3000) * exp_env(0.25, 0.05), 0.05 + rng.uniform(0, 0.5), 0.4)
    return soft_clip(x, 1.4)


def sfx_hit():
    d = 0.25
    t = tvec(d)
    body = sine(260 * np.exp(-t / 0.03) + 90, d) * exp_env(d, 0.06)
    snap = bandpass(noise(d), 1500, 6000) * exp_env(d, 0.015)
    return soft_clip(body + snap * 0.7, 2.0)


def sfx_boss_hit():
    d = 0.18
    t = tvec(d)
    metal = (sine(1250, d) + sine(1830, d) * 0.6 + sine(2570, d) * 0.3) * exp_env(d, 0.05)
    thump = sine(160 * np.exp(-t / 0.02) + 70, d) * exp_env(d, 0.04)
    return metal * 0.35 + thump


def sfx_victory():
    d = 2.4
    x = np.zeros(int(SR * d))
    seq = [(60, 0.0), (64, 0.12), (67, 0.24), (72, 0.36)]
    for n, st in seq:
        mix_at(x, pluck(note(n), 0.35, 5000), st, 0.7)
    chord = np.zeros(int(SR * 1.8))
    for n in (72, 76, 79, 84):
        chord += (saw(note(n), 1.8, 8) * 0.3 + sine(note(n), 1.8)) * exp_env(1.8, 0.8, 0.01)
    mix_at(x, lowpass(chord, 3500), 0.5, 0.4)
    mix_at(x, kick(0.4), 0.5, 0.6)
    mix_at(x, highpass(noise(1.5), 7000) * exp_env(1.5, 0.3), 0.5, 0.2)
    return x


def sfx_crowd_cheer():
    d = 2.6
    t = tvec(d)
    x = np.zeros(len(t))
    # many "voices": formant-filtered noise bursts with rising pitch contours
    for i in range(26):
        vd = rng.uniform(0.6, 1.6)
        vt = tvec(vd)
        f0 = rng.uniform(170, 330)
        voice = saw(f0 * (1 + 0.15 * np.sin(np.pi * vt / vd)), vd, 14)
        voice = bandpass(voice, rng.uniform(500, 800), rng.uniform(1500, 2600))
        env = np.sin(np.pi * vt / vd) ** 0.6
        mix_at(x, voice * env, rng.uniform(0, d - vd), rng.uniform(0.3, 0.8))
    x += bandpass(noise(d), 400, 3000) * 0.35
    env = np.minimum(1, t / 0.15) * np.minimum(1, (d - t) / 0.9)
    return x * env


def sfx_click():
    d = 0.08
    t = tvec(d)
    return sine(1400 * np.exp(-t / 0.01) + 600, d) * exp_env(d, 0.02)


def sfx_barrier_crash():
    d = 1.0
    x = sfx_wood_impact()[: int(SR * d)]
    for i in range(8):
        mix_at(x, bandpass(noise(0.15), 400, 2000) * exp_env(0.15, 0.03), 0.15 + rng.uniform(0, 0.6), 0.5)
    return x


def sfx_warning():
    d = 0.7
    t = tvec(d)
    f = np.where((t % 0.35) < 0.175, 330, 262)
    return lowpass(square(f, d, 6), 2200) * np.minimum(1, (d - t) / 0.1) * 0.8


# ---------------------------------------------------------------- music
def build_loop(bpm, bars, pattern_fn):
    beat = 60.0 / bpm
    total = beat * 4 * bars
    buf = np.zeros(int(SR * total) + SR)
    pattern_fn(buf, beat, bars)
    out = buf[: int(SR * total)]
    # wrap the reverb-ish tail back to the head for a seamless loop
    tail = buf[int(SR * total):]
    out[: len(tail)] += tail
    return out


def music_main_pattern(buf, beat, bars):
    # A minor, playful-tense: Am - F - C - G
    roots = [57, 53, 48, 55]
    arps = [[69, 72, 76, 72], [69, 72, 77, 72], [67, 72, 76, 72], [67, 71, 74, 71]]
    k = kick(0.35)
    s = clap(0.3)
    h = hat()
    ho = hat(open_=True)
    for bar in range(bars):
        b0 = bar * 4 * beat
        chord = bar % 4
        for q in range(4):
            mix_at(buf, k, b0 + q * beat, 0.9)
        for q in (1, 3):
            mix_at(buf, s, b0 + q * beat, 0.5)
        for e in range(8):
            mix_at(buf, ho if e % 4 == 3 else h, b0 + e * beat / 2, 0.35)
        # bass: off-beat 8ths with octave pops
        for e in range(8):
            n = roots[chord] - 12 + (12 if e in (3, 7) else 0)
            mix_at(buf, bass(note(n), beat / 2 * 0.9), b0 + e * beat / 2, 0.5)
        # lead pluck 16ths (second half of phrase only for build-up)
        if bar >= 2:
            for sx in range(16):
                n = arps[chord][sx % 4] + (12 if (sx // 4) % 2 == 1 and bar >= 6 else 0)
                mix_at(buf, pluck(note(n), 0.22, 3500), b0 + sx * beat / 4, 0.18)
        # stab on bar start
        for n in (roots[chord] + 12, roots[chord] + 19, roots[chord] + 24):
            mix_at(buf, lowpass(saw(note(n), beat * 0.8, 10) * exp_env(beat * 0.8, 0.2), 2500), b0, 0.12)


def music_boss_pattern(buf, beat, bars):
    # D minor, heavier: Dm - Bb - Gm - A
    roots = [50, 46, 43, 45]
    k = kick(0.4, 110, 38, 2.6)
    s = snare()
    h = hat()
    for bar in range(bars):
        b0 = bar * 4 * beat
        chord = bar % 4
        for e in range(8):
            if e in (0, 3, 4, 6):
                mix_at(buf, k, b0 + e * beat / 2, 1.0)
        for q in (1, 3):
            mix_at(buf, s, b0 + q * beat, 0.55)
        for sx in range(16):
            mix_at(buf, h, b0 + sx * beat / 4, 0.18 + (0.12 if sx % 4 == 2 else 0))
        # taiko toms
        mix_at(buf, tom(85), b0 + 3.5 * beat, 0.6)
        mix_at(buf, tom(70), b0 + 3.75 * beat, 0.6)
        # driving bass 16ths
        for sx in range(16):
            n = roots[chord] - 12
            mix_at(buf, bass(note(n), beat / 4 * 0.85), b0 + sx * beat / 4, 0.4)
        # brass-ish power stab
        dur = beat * 1.5
        stab = np.zeros(int(SR * dur))
        for n in (roots[chord] + 12, roots[chord] + 19):
            stab += saw(note(n), dur, 14)
        stab = lowpass(stab, 700 + 2200 * np.exp(-tvec(dur) / 0.15)) * exp_env(dur, 0.5, 0.01)
        mix_at(buf, stab, b0, 0.22)
        mix_at(buf, stab, b0 + 2.5 * beat, 0.16)


def main():
    os.makedirs(OUT, exist_ok=True)
    write("intro_rumble", sfx_rumble())
    write("city_ambience", sfx_city_ambience(), 0.6)
    write("whoosh", sfx_whoosh())
    write("impact_distant", sfx_impact_distant())
    write("footstep", sfx_footstep())
    write("footsteps_loop", sfx_footsteps_loop(), 0.7)
    write("gate_positive", sfx_gate_positive())
    write("gate_negative", sfx_gate_negative())
    write("multiply", sfx_multiply())
    write("pop", sfx_pop(), 0.6)
    write("sparkle", sfx_sparkle(), 0.7)
    write("wood_impact", sfx_wood_impact())
    write("barrier_crash", sfx_barrier_crash())
    write("thud", sfx_thud())
    write("boss_roar", sfx_boss_roar())
    write("boss_step", sfx_boss_step())
    write("weapon_swing", sfx_weapon_swing())
    write("ground_slam", sfx_ground_slam())
    write("hit", sfx_hit())
    write("boss_hit", sfx_boss_hit(), 0.6)
    write("victory_sting", sfx_victory())
    write("crowd_cheer", sfx_crowd_cheer())
    write("ui_click", sfx_click(), 0.6)
    write("warning", sfx_warning(), 0.7)
    write("music_main", build_loop(132, 8, music_main_pattern), 0.8)
    write("music_boss", build_loop(140, 4, music_boss_pattern), 0.8)


if __name__ == "__main__":
    main()
