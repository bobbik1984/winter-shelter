#!/usr/bin/env python3
"""网页版风声循环（2026-11-07）：和 scripts/systems/ambient_audio.gd 里逐采样的风声同一个算法
（布朗噪声 + 少量白噪声 → 两级一阶低通；× 2.2 在游戏里乘），离线烤成两段无缝循环：
  wind_open.wav     迎风（截止 2000 Hz）
  wind_muffled.wav  背风 / 庇护所里（截止 150 Hz）
游戏里按当前截止频率在两段之间交叉淡化，音量和阵风按帧调。网页版交给浏览器（Web Audio）播放，
主线程卡一下也不断音；本地版仍逐采样合成。
用法：python3 tools/bake_wind_loops.py  （写 assets/audio/，固定随机种子，结果可复现）"""
import os, wave
import numpy as np

RATE = 22050
SECONDS = 8.0
FADE = 1.0
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')

def wind(cut, n, rng):
    a = 1.0 - np.exp(-2 * np.pi * cut / RATE)
    u = rng.uniform(-1, 1, n)
    white = rng.uniform(-1, 1, n)
    out = np.empty(n)
    brown = lp = lp2 = 0.0
    for i in range(n):
        brown = min(1.0, max(-1.0, brown * 0.998 + u[i] * 0.06))
        lp += a * ((white[i] * 0.35 + brown) - lp)
        lp2 += a * (lp - lp2)
        out[i] = lp2
    return out[RATE // 2:]   # 丢掉开头半秒（滤波器起振）；× 2.2 放在游戏里的音量上，免得这里削波

def bake(name, cut, seed):
    rng = np.random.default_rng(seed)
    n_loop = int(RATE * SECONDS)
    n_fade = int(RATE * FADE)
    x = wind(cut, n_loop + n_fade + RATE // 2, rng)
    # 无缝：把尾巴多出来的一秒等功率地叠到开头（两段噪声不相关，所以用 sin/cos）
    t = np.linspace(0, np.pi / 2, n_fade)
    head = x[:n_fade] * np.sin(t) + x[n_loop:n_loop + n_fade] * np.cos(t)
    y = np.concatenate([head, x[n_fade:n_loop]])
    y = np.clip(y, -1, 1)
    pcm = (y * 32767).astype('<i2')
    path = os.path.join(OUT, name)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    print(name, len(pcm), 'frames, rms %.3f' % float(np.sqrt(np.mean(y ** 2))))

os.makedirs(OUT, exist_ok=True)
bake('wind_open.wav', 2000.0, 11)
bake('wind_muffled.wav', 150.0, 12)
