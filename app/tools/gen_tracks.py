#!/usr/bin/env python3
# Generate bundled relaxation tracks (procedural audio, no samples).
# Output: 16-bit mono WAV, seamless loops.
import numpy as np, wave, os, math

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "Support", "tracks")
os.makedirs(OUT, exist_ok=True)

def save(name, x, norm=0.5):
    x = np.asarray(x, dtype=np.float64)
    peak = np.max(np.abs(x)) + 1e-9
    x = x / peak * norm
    data = (x * 32767).astype("<i2")
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(name, "%.1f MB" % (os.path.getsize(path)/1e6))

def env_pluck(t, t0, decay):
    tau = decay / 5.0
    return np.exp(-(t - t0) / tau) * (t >= t0)

# ---------- 1. Spokojny pad (2:00, chords Am F C G, one per 16 s) ----------
dur = 120.0
n = int(SR * dur)
t = np.arange(n) / SR
chords = [110.0, 87.31, 130.81, 98.0]   # A2, F2, C3, G2 (roots)
pad = np.zeros(n)
chord_len = 16.0
for ci in range(int(dur / chord_len)):
    root = chords[ci % 4]
    start, end = int(ci * chord_len), int((ci + 1) * chord_len)
    seg_t = t[start:end] - ci * chord_len
    # crossfade 4 s in/out
    fade = np.minimum(seg_t / 4.0, 1.0) * np.minimum((chord_len - seg_t) / 4.0, 1.0)
    for mult, amp in [(1.0, 0.5), (1.5, 0.35), (2.0, 0.25), (2.5, 0.12), (3.0, 0.06)]:
        f = root * mult
        detune = 1.0 + 0.0015 * np.sin(2 * np.pi * 0.11 * seg_t)
        pad[start:end] += amp * fade * np.sin(2 * np.pi * f * detune * seg_t)
pad *= 0.6
# gentle breath (very slow AM)
pad *= 1.0 + 0.18 * np.sin(2 * np.pi * (1.0 / 23.0) * t)
save("pad", pad)

# ---------- 2. Deszcz na oknie (2:00) ----------
rng = np.random.default_rng(42)
n = int(SR * dur)
white = rng.uniform(-1, 1, n)
# brown-ish (leaky integrator)
rain = np.zeros(n); last = 0.0
a = 0.02
for i in range(n):
    last = (last + a * white[i]) / (1.0 + a)
    rain[i] = last
rain /= np.max(np.abs(rain))
rain *= 0.9
# slow intensity drift
rain *= 0.75 + 0.25 * np.sin(2 * np.pi * t / 37.0)
# water droplet ticks: short filtered pings at random times on glass
droplets = np.zeros(n)
for _ in range(220):
    t0 = rng.uniform(0, dur - 0.2)
    f0 = rng.uniform(1200, 3800)
    ln = int(0.05 * SR)
    s = int(t0 * SR)
    seg = np.arange(ln) / SR
    droplets[s:s+ln] += rng.uniform(0.08, 0.25) * np.exp(-seg/0.012) * np.sin(2*np.pi*f0*seg)
save("rain", rain + droplets, norm=0.45)

# ---------- 3. Ocean (2:00) ----------
n = int(SR * dur)
swell = 0.5 + 0.5 * np.sin(2 * np.pi * t / 11.0)
swell2 = 0.6 + 0.4 * np.sin(2 * np.pi * t / 17.0 + 1.3)
b = np.zeros(n); last = 0.0
for i in range(n):
    last = (last + 0.05 * white[i]) / 1.05
    b[i] = last
b /= np.max(np.abs(b))
ocean = b * (0.35 + 0.65 * swell * swell2)
# deeper rumble under
ocean += 0.25 * np.sin(2 * np.pi * 45 * t) * swell
save("ocean", ocean, norm=0.5)

# ---------- 4. Misā — singing bowl strikes (2:00) ----------
n = int(SR * dur)
bowl = np.zeros(n)
base = 196.0  # G3
overtones = [(1.0, 1.0), (2.0, 0.55), (3.01, 0.3), (4.2, 0.18), (5.4, 0.1), (6.7, 0.05)]
tt = 6.0
strike = 0
while tt < dur - 20:
    dur_s = rng.uniform(14, 22)
    ln = int(dur_s * SR)
    s = int(tt * SR)
    seg = np.arange(ln) / SR
    decay = np.exp(-seg / (dur_s / 4.0))
    ch = 0.97 + 0.06 * rng.random()
    for mult, amp in overtones:
        f = base * ch * mult
        wob = 1.0 + 0.001 * np.sin(2 * np.pi * rng.uniform(0.3, 0.9) * seg)
        bowl[s:s+ln] += amp * decay * np.sin(2 * np.pi * f * wob * seg)
    tt += dur_s
save("bowl", bowl, norm=0.45)

print("done")
