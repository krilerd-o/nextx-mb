#!/usr/bin/env python3
"""Synthesise the app's shutter sounds (original, royalty-free) into assets/sounds/.

usage: python3 tool/gen_shutter.py
Three styles: rangefinder (soft, default), slr (mirror slap), minimal (digital tick).
Pure stdlib: damped resonators + filtered noise, 44.1 kHz mono 16-bit WAV.
"""
import math, os, random, struct, wave

SR = 44100
random.seed(7)
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'sounds')


def silence(ms):
    return [0.0] * int(SR * ms / 1000)


def click(ms, freqs, decay_ms, noise=0.6, noise_decay_ms=None, lp=0.35, gain=1.0):
    """Mechanical click: noise transient + a few damped resonances, one-pole low-pass."""
    n = int(SR * ms / 1000)
    nd = (noise_decay_ms or decay_ms * 0.4) / 1000
    out, y = [], 0.0
    for i in range(n):
        t = i / SR
        s = noise * (random.random() * 2 - 1) * math.exp(-t / nd)
        for f, a in freqs:
            s += a * math.sin(2 * math.pi * f * t) * math.exp(-t / (decay_ms / 1000))
        att = min(1.0, i / (SR * 0.0006))  # 0.6 ms attack, no pop
        y += lp * (s * att - y)
        out.append(y * gain)
    return out


def mix(*parts):
    """parts: (offset_ms, samples)"""
    end = max(int(SR * o / 1000) + len(s) for o, s in parts)
    buf = [0.0] * end
    for o, s in parts:
        k = int(SR * o / 1000)
        for i, v in enumerate(s):
            buf[k + i] += v
    return buf


def write(name, samples, peak=0.7):
    m = max(abs(v) for v in samples) or 1
    tail = int(SR * 0.004)
    for i in range(tail):  # fade the last 4 ms
        samples[-1 - i] *= i / tail
    data = b''.join(struct.pack('<h', int(max(-1, min(1, v / m * peak)) * 32767)) for v in samples)
    path = os.path.join(OUT, name)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print(f'{name}: {len(samples) / SR * 1000:.0f} ms, {os.path.getsize(path)} bytes')


os.makedirs(OUT, exist_ok=True)

# Rangefinder: a quiet, crisp leaf-shutter "tsk" with a soft second blade.
write('shutter_rangefinder.wav', mix(
    (0, click(55, [(3400, 0.5), (5200, 0.25), (1900, 0.2)], 9, noise=0.7, lp=0.45)),
    (34, click(45, [(2900, 0.3), (4600, 0.15)], 7, noise=0.4, lp=0.4, gain=0.45)),
), peak=0.55)

# SLR: mirror up "ka" + mirror down "chak", deeper and longer.
write('shutter_slr.wav', mix(
    (0, click(80, [(1250, 0.6), (2300, 0.35), (640, 0.4)], 18, noise=0.9, noise_decay_ms=6, lp=0.3)),
    (105, click(95, [(1050, 0.6), (2050, 0.3), (520, 0.45)], 22, noise=1.0, noise_decay_ms=8, lp=0.28, gain=0.9)),
), peak=0.75)

# Minimal: short digital tick.
write('shutter_minimal.wav', mix(
    (0, click(30, [(2400, 1.0)], 6, noise=0.05, lp=0.9)),
    (22, click(26, [(3600, 0.6)], 5, noise=0.03, lp=0.9, gain=0.35)),
), peak=0.5)
