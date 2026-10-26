#!/usr/bin/env python3
"""Cenário "pixel art" da IA -> pixel art real na grade do jogo (320x180).
O Gemini desenhou com "pixels" de ~8 px numa imagem de 2576x1438, ou seja, já pensando numa
grade de ~320x180. Cada célula da grade vira 1 pixel com a cor mais votada do bloco (depois de
reduzir a imagem inteira para uma paleta curta), então as bordas ficam nítidas e as cores puras.
Uso: bg_to_grid.py <imagem> <saida.png> [--w 320] [--h 180] [--colors 40] [--palette-out pal.png]"""
import argparse
import numpy as np
from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument("image"); ap.add_argument("out")
ap.add_argument("--w", type=int, default=320); ap.add_argument("--h", type=int, default=180)
ap.add_argument("--colors", type=int, default=40); ap.add_argument("--palette-out")
a = ap.parse_args()
im = Image.open(a.image).convert("RGB")
q = im.quantize(a.colors, method=Image.Quantize.MEDIANCUT, kmeans=3, dither=Image.Dither.NONE)
pal = np.array(q.getpalette()[: a.colors * 3]).reshape(-1, 3)
idx = np.asarray(q).astype(int)
H, W = idx.shape
ys = np.linspace(0, H, a.h + 1).astype(int); xs = np.linspace(0, W, a.w + 1).astype(int)
out = np.zeros((a.h, a.w, 3), "uint8")
for i in range(a.h):
    for j in range(a.w):
        blk = idx[ys[i]:ys[i + 1], xs[j]:xs[j + 1]]
        # só o miolo do bloco (as bordas da célula da IA são borradas pelo JPEG)
        bh, bw = blk.shape
        core = blk[bh // 4: bh - bh // 4 or bh, bw // 4: bw - bw // 4 or bw].ravel()
        out[i, j] = pal[np.bincount(core, minlength=a.colors).argmax()]
Image.fromarray(out).save(a.out)
used = sorted(set(map(tuple, out.reshape(-1, 3))))
if a.palette_out:
    Image.fromarray(np.array(used, "uint8").reshape(1, -1, 3)).save(a.palette_out)
print(f"{a.out}: {a.w}x{a.h}, {len(used)} cores")
