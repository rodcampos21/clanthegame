"""Imagem "estilo pixel art" da IA -> sprite de pixel art real numa célula NxN.
1. remove o fundo branco e recorta
2. reduz por média de área até a altura alvo (o pixel da IA é irregular; a média é mais estável)
3. alpha binário (sem semitransparência) e paleta limitada (k-means nos pixels opacos)
4. contorno escuro de 1 px fechado onde a redução abriu buracos na borda
5. encaixa na célula com os pés embaixo no centro
Uso: to_pixel.py <imagem> <saida> [--cell 64] [--height 60] [--colors 20]"""
import argparse
import numpy as np
from PIL import Image
from scipy import ndimage
from normalize_strip import remove_white

OUTLINE = (34, 28, 40)


def pixelize(img, height, colors, palette_from=None, extra_colors=0):
    """Quantiza a imagem grande numa paleta curta ANTES de reduzir, e reduz por voto da cor
    mais frequente em cada bloco: as cores continuam puras (a média misturava branco com dourado
    e dava bege)."""
    rgba = img if img.mode == "RGBA" and np.asarray(img)[..., 3].min() == 0 else remove_white(img)
    rgba = rgba.crop(rgba.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox())
    a = np.asarray(rgba)
    op = a[..., 3] > 128
    if palette_from is not None:   # paleta travada (a da semente): todas as animações com as mesmas cores
        palette = np.asarray(Image.open(palette_from).convert("RGB")).reshape(-1, 3).astype(int)
        if extra_colors:
            # efeitos (brilho dourado da habilidade) não existem na paleta do Cavaleiro: as cores
            # que ficam longe de toda a paleta viram até N cores extras só desta animação
            px = a[..., :3][op].reshape(-1, 3).astype(int)
            d = ((px[:, None, :] - palette[None]) ** 2).sum(-1).min(1)
            far = px[d > 40 ** 2]
            if len(far) > 50:
                ex = Image.fromarray(far.astype("uint8").reshape(1, -1, 3)).quantize(extra_colors, method=Image.Quantize.MEDIANCUT, kmeans=2)
                extra = np.array(ex.getpalette()[: extra_colors * 3]).reshape(-1, 3)
                palette = np.vstack([palette, extra])
        colors = len(palette)
        pal_img = Image.new("P", (1, 1))
        pal_img.putpalette(palette.astype("uint8").ravel().tolist() + [0] * (768 - colors * 3))
    else:
        pal_img = Image.fromarray(a[..., :3][op].reshape(1, -1, 3)).quantize(colors, method=Image.Quantize.MEDIANCUT, kmeans=3)
        palette = np.array(pal_img.getpalette()[: colors * 3]).reshape(-1, 3)
    full = Image.fromarray(a[..., :3]).quantize(palette=pal_img, dither=Image.Dither.NONE)
    idx = np.asarray(full).astype(int)
    idx[~op] = colors                         # índice extra = transparente
    H, W = idx.shape
    w = max(1, round(W * height / H))
    ys = np.linspace(0, H, height + 1).astype(int)
    xs = np.linspace(0, W, w + 1).astype(int)
    out = np.zeros((height, w, 4), "uint8")
    for i in range(height):
        for j in range(w):
            blk = idx[ys[i]:ys[i + 1], xs[j]:xs[j + 1]].ravel()
            cnt = np.bincount(blk, minlength=colors + 1)
            if cnt[colors] > blk.size * 0.55:       # bloco majoritariamente vazio
                continue
            cnt[colors] = 0
            k = int(cnt.argmax())
            out[i, j, :3] = palette[k]
            out[i, j, 3] = 255
    opaque = out[..., 3] > 0
    # halo: a IA deixa uma franja clara (quase branca, sem contorno) em volta de alguns quadros;
    # remove até 2 camadas de pixels muito claros e pouco saturados encostados no transparente
    for _ in range(2):
        rgb = out[..., :3].astype(int)
        pale = (rgb.min(-1) > 200) & ((rgb.max(-1) - rgb.min(-1)) < 30)
        border = opaque & ~ndimage.binary_erosion(opaque)
        kill = border & pale
        out[kill] = 0
        opaque = out[..., 3] > 0
    edge = opaque & ~ndimage.binary_erosion(opaque)
    lum = out[..., :3].astype(float).mean(-1)
    out[edge & (lum > 90), :3] = OUTLINE
    return Image.fromarray(out)


def place(sprite, cell):
    al = np.asarray(sprite.getchannel("A")) > 0
    rows = np.nonzero(al.any(1))[0]
    band = al[rows.max() - 3: rows.max() + 1]
    xs = np.nonzero(band.any(0))[0]
    feet_x = (xs.min() + xs.max()) // 2
    c = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
    c.alpha_composite(sprite, (cell // 2 - feet_x, cell - 2 - rows.max()))
    return c


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("image"); ap.add_argument("out")
    ap.add_argument("--cell", type=int, default=64); ap.add_argument("--height", type=int, default=60)
    ap.add_argument("--colors", type=int, default=20)
    ap.add_argument("--palette"); ap.add_argument("--save-palette")
    a = ap.parse_args()
    s = pixelize(Image.open(a.image), a.height, a.colors, a.palette)
    if a.save_palette:
        arr = np.asarray(s)
        cols = sorted(set(map(tuple, arr[arr[..., 3] > 0][:, :3])))
        Image.fromarray(np.array(cols, "uint8").reshape(1, -1, 3)).save(a.save_palette)
        print("paleta salva:", len(cols), "cores")
    c = place(s, a.cell)
    c.save(a.out)
    print("sprite", s.size, "célula", c.size, "cores", len(set(map(tuple, np.asarray(c)[np.asarray(c)[..., 3] > 0][:, :3]))))
