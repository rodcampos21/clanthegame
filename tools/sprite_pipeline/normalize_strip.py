#!/usr/bin/env python3
"""Passo 4 do sprite-pipeline: tira gerada por IA -> quadros normalizados.

1. remove o fundo branco (flood fill a partir das bordas: brancos internos ficam)
2. separa os personagens por componentes conexos (cada quadro = maior blob + pedaços próximos)
3. UMA escala para a tira toda (altura do quadro de referência = altura alvo)
4. âncora comum embaixo-no-centro: x = centro das botas, y = sola
5. salva quadros PNG, spritesheet e GIF de prévia
Uso: normalize_strip.py <imagem> <saida_prefixo> --frames N [--height 480] [--fps 6] [--pingpong]
"""
import argparse
from collections import deque

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage


def remove_white(im: Image.Image) -> Image.Image:
    a = np.asarray(im.convert("RGB")).astype(int)
    h, w, _ = a.shape
    nw = (a.min(-1) > 228) & ((a.max(-1) - a.min(-1)) < 20)
    lab, _ = ndimage.label(nw)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bg = np.isin(lab, list(border))
    alpha = Image.fromarray(((~bg) * 255).astype("uint8")).filter(ImageFilter.GaussianBlur(0.8))
    out = im.convert("RGBA")
    out.putalpha(alpha)
    return out


def split(rgba: Image.Image, n: int):
    al = np.asarray(rgba.getchannel("A")) > 40
    lab, k = ndimage.label(al)
    sizes = ndimage.sum(al, lab, range(1, k + 1))
    order = np.argsort(sizes)[::-1]
    mains = sorted(order[:n] + 1, key=lambda l: ndimage.center_of_mass(lab == l)[1])
    centers = [ndimage.center_of_mass(lab == l)[1] for l in mains]
    owner = np.zeros_like(lab)
    for l in range(1, k + 1):
        if sizes[l - 1] < 30:
            continue
        cx = ndimage.center_of_mass(lab == l)[1]
        i = int(np.argmin([abs(cx - c) for c in centers]))
        owner[lab == l] = i + 1
    frames = []
    arr = np.asarray(rgba)
    for i in range(n):
        m = owner == i + 1
        ys, xs = np.nonzero(m)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        crop = arr[y0:y1, x0:x1].copy()
        crop[..., 3] = np.where(m[y0:y1, x0:x1], crop[..., 3], 0)
        frames.append(Image.fromarray(crop))
    return frames


def anchor(fr: Image.Image):
    """(x dos pés, y da sola) dentro do recorte."""
    al = np.asarray(fr.getchannel("A")) > 40
    rows = np.nonzero(al.any(1))[0]
    sole = rows.max()
    band = al[max(0, sole - int(len(rows) * 0.06)): sole + 1]
    xs = np.nonzero(band.any(0))[0]
    return (xs.min() + xs.max()) / 2, sole


def normalize(frames, height, ref=0):
    hs = [f.height for f in frames]
    scale = height / hs[ref]                         # uma escala para a tira toda
    scaled = [f.resize((round(f.width * scale), round(f.height * scale)), Image.LANCZOS) for f in frames]
    anchors = [anchor(f) for f in scaled]
    left = max(ax for ax, _ in anchors)
    right = max(f.width - ax for f, (ax, _) in zip(scaled, anchors))
    top = max(ay for _, ay in anchors)
    W, H = int(left + right) + 8, int(top) + 12
    out = []
    for f, (ax, ay) in zip(scaled, anchors):
        c = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        c.alpha_composite(f, (int(round(4 + left - ax)), int(round(H - 6 - ay))))
        out.append(c)
    return out, scale


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("out")
    ap.add_argument("--frames", type=int, required=True)
    ap.add_argument("--height", type=int, default=480)
    ap.add_argument("--fps", type=float, default=6)
    ap.add_argument("--pingpong", action="store_true")
    a = ap.parse_args()
    rgba = remove_white(Image.open(a.image))
    frames = split(rgba, a.frames)
    print("alturas brutas:", [f.height for f in frames], "larguras:", [f.width for f in frames])
    norm, scale = normalize(frames, a.height)
    for i, f in enumerate(norm):
        f.save(f"{a.out}_{i:02d}.png")
    sheet = Image.new("RGBA", (norm[0].width * len(norm), norm[0].height), (0, 0, 0, 0))
    for i, f in enumerate(norm):
        sheet.alpha_composite(f, (i * norm[0].width, 0))
    sheet.save(f"{a.out}_sheet.png")
    seq = norm + (norm[-2:0:-1] if a.pingpong else [])
    gif = []
    for f in seq:
        bg = Image.new("RGBA", f.size, (205, 210, 215, 255))
        bg.alpha_composite(f)
        gif.append(bg.convert("RGB"))
    gif[0].save(f"{a.out}.gif", save_all=True, append_images=gif[1:], duration=int(1000 / a.fps), loop=0)
    print(f"escala {scale:.3f}, quadro {norm[0].size}, {len(norm)} quadros")


if __name__ == "__main__":
    main()
