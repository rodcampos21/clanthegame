#!/usr/bin/env python3
"""HUD sheet from the AI (art/hud/hud_sheet.jpg) -> real pixel-art pieces in assets/ui/hud/.

The AI drew the sheet with fake pixels of ~8.08 px. For every piece:
  1. find the grid phase that makes the cells most uniform, take the median color of each cell
  2. remove the white background (flood fill from the border)
  3. snap every pixel to one shared palette (k-means over all pieces) -> hud_palette.png

Bars: the AI fills (red / blue / orange strips) never match the frame channels exactly, so
the fill textures are rebuilt *inside each frame's channel* (the dark navy area): every row
takes the color of the same relative row of the AI fill, and the 5 segment dividers are
redrawn at even spacing. Fill, trail and frame have the same size, so the game just draws
the frame and then the first N columns of the channel of the trail and fill on top.
Prints the channel rect of each frame (copy it to the HudBarStyle .tres).

Usage: make_hud.py <hud_sheet.jpg> <out_dir>
"""
import json
import sys

import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.cluster.vq import kmeans2

P = 8.08            # AI pixel size in the sheet
COLORS = 32
# piece: (y0, x0, y1, x1) in the sheet
BOXES = {
    "frame_hp": (182, 88, 352, 1217), "frame_mp": (596, 87, 765, 1218), "frame_short": (2079, 393, 2233, 903),
    "fill_hp": (898, 134, 996, 1170), "fill_mp": (1229, 134, 1304, 1170), "fill_trail": (1384, 134, 1466, 1170),
    "icon_heart": (1690, 159, 1844, 329), "icon_crystal": (1665, 458, 1861, 572),
    "icon_shield": (1682, 717, 1853, 863), "icon_star": (1682, 979, 1844, 1150),
}
# which fill goes into which frame
BARS = {"frame_hp": ["fill_hp", "fill_trail"], "frame_mp": ["fill_mp"], "frame_short": ["fill_hp", "fill_trail"]}
SEGMENTS = 5


def sample(A, box):
    y0, x0, y1, x1 = box
    best = None
    for py in range(8):
        for px in range(8):
            ys = np.arange(y0 - 8 + py, y1 + 8, P).astype(int)
            xs = np.arange(x0 - 8 + px, x1 + 8, P).astype(int)
            err = sum(A[ys[i] + 2:ys[i + 1] - 2, xs[j] + 2:xs[j + 1] - 2].std(axis=(0, 1)).sum()
                      for i in range(len(ys) - 1) for j in range(len(xs) - 1))
            if best is None or err < best[0]:
                best = (err, ys, xs)
    _, ys, xs = best
    g = np.zeros((len(ys) - 1, len(xs) - 1, 3), "float32")
    for i in range(len(ys) - 1):
        for j in range(len(xs) - 1):
            g[i, j] = np.median(A[ys[i] + 2:ys[i + 1] - 2, xs[j] + 2:xs[j + 1] - 2].reshape(-1, 3), 0)
    return g


def cut_background(g):
    white = (g.min(2) > 200) & (np.ptp(g, axis=2) < 30)
    lab, _ = ndimage.label(white)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    alpha = ~np.isin(lab, list(border))
    ys, xs = np.nonzero(alpha)
    sl = (slice(ys.min(), ys.max() + 1), slice(xs.min(), xs.max() + 1))
    return g[sl], alpha[sl]


def snap(rgb, pal):
    d = ((rgb[..., None, :] - pal[None, None]) ** 2).sum(-1)
    return pal[d.argmin(-1)]


def channel(img, alpha):
    """Dark navy channel of a frame: the dark component that holds the middle of the bar."""
    lum = img.mean(2)
    dark = alpha & (lum < 70) & (img[..., 2] > img[..., 0] + 8)
    lab, _ = ndimage.label(dark)
    h, w = lum.shape
    ids = lab[h // 2, int(w * 0.4):int(w * 0.8)]
    cid = np.bincount(ids[ids > 0]).argmax()
    mask = lab == cid
    # close the gaps the AI left on the channel edges (odd navy shades): each row runs
    # solid from its first to its last channel pixel
    for y in range(mask.shape[0]):
        xs = np.nonzero(mask[y])[0]
        if len(xs):
            mask[y, xs.min():xs.max() + 1] = True
    return mask


def fill_profile(fill_rgb, fill_a):
    """Row colors of an AI fill strip (inside its outline), median over its first segment."""
    cols = fill_rgb[:, 4:12]
    a = fill_a[:, 4:12].all(1)
    rows = [i for i in range(fill_rgb.shape[0]) if a[i] and cols[i].mean() > 60]
    prof = np.median(cols[rows], 1)
    return prof


def build_fill(mask, prof, pal):
    ys, xs = np.nonzero(mask)
    top, bot = ys.min(), ys.max()
    x0, x1 = xs.min(), xs.max()
    out = np.zeros(mask.shape + (4,), "uint8")
    dark = prof.min(0) * 0.6
    hi = np.minimum(prof.max(0) * 1.15, 255)
    for y, x in zip(ys, xs):
        r = (y - top) / max(bot - top, 1)
        c = prof[min(int(r * len(prof)), len(prof) - 1)]
        out[y, x, :3] = snap(c[None, None], pal)[0, 0]
        out[y, x, 3] = 255
    w = x1 - x0 + 1
    for k in range(1, SEGMENTS):
        dx = x0 + round(k * w / SEGMENTS)
        for y in range(top, bot + 1):
            if mask[y, dx]:
                out[y, dx, :3] = snap(dark[None, None], pal)[0, 0]
            if dx + 1 <= x1 and mask[y, dx + 1] and y < (top + bot) / 2:
                out[y, dx + 1, :3] = snap(hi[None, None], pal)[0, 0]
    return out, (int(x0), int(top), int(w), int(bot - top + 1))


def main(sheet, out_dir):
    A = np.asarray(Image.open(sheet).convert("RGB")).astype("float32")
    pieces = {n: cut_background(sample(A, b)) for n, b in BOXES.items()}
    allpx = np.concatenate([g[a] for g, a in pieces.values()])
    pal, _ = kmeans2(allpx, COLORS, minit="++", seed=7)
    pal = np.unique(np.clip(pal, 0, 255).round(), axis=0)
    snapped = {n: snap(g, pal) for n, (g, a) in pieces.items()}
    used = set()
    meta = {}
    for name in BOXES:
        if name.startswith("fill"):
            continue
        g, a = pieces[name]
        rgba = np.dstack([snapped[name], a * 255]).astype("uint8")
        rgba[~a] = 0
        Image.fromarray(rgba).save(f"{out_dir}/{name}.png")
        used |= set(map(tuple, rgba[a][:, :3]))
        if name in BARS:
            mask = channel(snapped[name], a)
            for fname in BARS[name]:
                prof = fill_profile(*pieces[fname])
                fill, rect = build_fill(mask, prof, pal)
                kind = fname.split("_")[1]
                Image.fromarray(fill).save(f"{out_dir}/{name}_{kind}.png")
                used |= set(map(tuple, fill[fill[..., 3] > 0][:, :3]))
                meta[name] = {"size": [int(a.shape[1]), int(a.shape[0])], "channel": rect}
    pal_img = np.array(sorted(used), "uint8").reshape(1, -1, 3)
    Image.fromarray(pal_img).save(f"{out_dir}/hud_palette.png")
    print(json.dumps(meta, indent=1))
    print(f"palette: {pal_img.shape[1]} colors")


if __name__ == "__main__":
    main(*sys.argv[1:3])
