"""Tira de animação em "pixel art" da IA -> quadros 192x192 de pixel art real.
- separa os quadros (blob principal + rastros/lascas próximos vão para o quadro mais perto)
- UMA escala para a tira: o quadro de referência (pose em pé) fica com a altura da semente
- cada quadro: paleta travada da semente, redução por voto, contorno de 1 px
- âncora: centro dos pés (faixa de baixo) e sola, iguais em todos os quadros e no idle
Uso: process_pixel_strip.py <img> <nome> --frames N [--ref K] [--ms ...] [--seed-height 174]"""
import argparse
import numpy as np
from PIL import Image
from scipy import ndimage
from normalize_strip import remove_white
from to_pixel import pixelize

CELL = 192


def split_row(path, n, rows=1):
    rgba = remove_white(Image.open(path)); arr = np.asarray(rgba); al = arr[..., 3] > 40
    lab, k = ndimage.label(al); sizes = ndimage.sum(al, lab, range(1, k + 1))
    H = al.shape[0]
    cm = {l: ndimage.center_of_mass(lab == l) for l in np.argsort(sizes)[::-1][:n] + 1}
    if rows > 1:   # grade: separa as linhas pelo maior vão vertical entre os centros
        ys = sorted(c[0] for c in cm.values())
        gaps = sorted(range(1, len(ys)), key=lambda i: ys[i] - ys[i - 1])[-(rows - 1):]
        cuts = sorted((ys[i] + ys[i - 1]) / 2 for i in gaps)
        rowof = lambda y: sum(y > c for c in cuts)
    else:
        rowof = lambda y: 0
    mains = sorted(cm, key=lambda l: (rowof(cm[l][0]), cm[l][1]))
    owner = {}
    for l in range(1, k + 1):
        if sizes[l - 1] < 60:
            continue
        c = ndimage.center_of_mass(lab == l)
        owner[l] = mains[int(np.argmin([np.hypot(c[0] - cm[m][0], c[1] - cm[m][1]) for m in mains]))]
    frames = []
    for m_l in mains:
        m = np.isin(lab, [l for l, o in owner.items() if o == m_l])
        ys, xs = np.nonzero(m); y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        c = arr[y0:y1, x0:x1].copy(); c[..., 3] = np.where(m[y0:y1, x0:x1], c[..., 3], 0)
        frames.append(Image.fromarray(c))
    return frames


def head_w(img):
    """Tamanho da cabeça = raiz da área do cabelo branco (componente que toca o topo).
    Muda pouco com a pose do corpo, então serve para igualar a escala entre animações."""
    a = np.asarray(img).astype(int); al = a[..., 3] > 40
    rgb = a[..., :3]
    hair = al & (rgb.min(-1) > 175) & ((rgb.max(-1) - rgb.min(-1)) < 35)
    ys = np.nonzero(al.any(1))[0]; t = ys.min()
    hair[t + int((ys.max() - t) * 0.45):] = False
    lab, k = ndimage.label(ndimage.binary_closing(hair, iterations=2))
    if k == 0:
        return None
    sizes = ndimage.sum(hair, lab, range(1, k + 1))
    return float(np.sqrt(sizes.max()))


def torso(img):
    a = np.asarray(img).astype(int); al = a[..., 3] > 40
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    belt = al & (r > 120) & (g < 80) & (b < 80) & (r - g > 60)
    cnt = belt.sum(1)
    if cnt.max() < 3:
        return None
    return int(cnt.argmax()) - int(np.nonzero(al.any(1))[0].min())


def feet_anchor(sprite):
    al = np.asarray(sprite.getchannel("A")) > 0
    rows = np.nonzero(al.any(1))[0]; sole = rows.max()
    band = al[sole - 3: sole + 1]; xs = np.nonzero(band.any(0))[0]
    return (xs.min() + xs.max()) / 2, sole


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image"); ap.add_argument("name")
    ap.add_argument("--frames", type=int, required=True); ap.add_argument("--ref", type=int, default=-1)
    ap.add_argument("--seed-height", type=int, default=174); ap.add_argument("--palette", default="knight_palette.png")
    ap.add_argument("--ms", default="120"); ap.add_argument("--scale-by", default="height"); ap.add_argument("--rows", type=int, default=1); ap.add_argument("--anchor", default="feet"); ap.add_argument("--anchor-x", type=float, default=None)
    a = ap.parse_args()
    frames = split_row(a.image, a.frames, a.rows)
    if a.scale_by == "head":
        # largura da cabeça (faixa de cima do cabelo até o queixo) igual à do idle 192
        idle_h = head_w(Image.open("knight_192.png"))
        hs = [head_w(f) for f in frames]
        s = idle_h / float(np.median(hs))
        print("cabeça bruta", hs, "idle", idle_h)
    elif a.scale_by == "torso":
        # poses sem quadro em pé (dano, morte): escala pela distância topo do cabelo -> cinto,
        # que quase não muda com a pose das pernas; alvo = a mesma medida no idle 192
        idle_t = torso(Image.open("knight_192.png"))
        ts = [torso(f) for f in frames]
        s = idle_t / float(np.median([t for t in ts if t]))
        print("topo->cinto bruto", ts, "idle", idle_t)
    else:
        ref = frames[a.ref]
        s = a.seed_height / ref.height
    print("alturas brutas", [f.height for f in frames], "escala", round(s, 4))
    sprites = [pixelize(f, max(8, round(f.height * s)), 0, a.palette) for f in frames]
    # âncora x comum = a do idle (pés no centro da célula); cada quadro alinhado pelos pés
    # célula: altura 192 sempre; largura cresce se o golpe passar da célula. A ORIGEM (ponto entre
    # os pés, na sola) fica em (ox, 190) em todas as folhas -> no Godot basta alinhar esse ponto.
    if a.anchor == "body":
        # corrida/avanço: o corpo não pode "pular" de lado entre quadros -> x pelo centro do cinto
        anchors = []
        for sp in sprites:
            fx, sole = feet_anchor(sp)
            aa = np.asarray(sp).astype(int); al = aa[..., 3] > 0
            belt = al & (aa[..., 0] > 120) & (aa[..., 1] < 80) & (aa[..., 2] < 80)
            cnt = belt.sum(1); y = int(cnt.argmax()); xs = np.nonzero(belt[max(0, y - 2): y + 3].any(0))[0]
            anchors.append(((xs.min() + xs.max()) / 2 if len(xs) else fx, sole))
    elif a.anchor == "mass":
        # queda: pés e cinto somem/mudam de lugar -> x pelo centro de massa, y pela sola
        anchors = []
        for sp in sprites:
            fx, sole = feet_anchor(sp)
            al = np.asarray(sp.getchannel("A")) > 0
            anchors.append((float(np.nonzero(al)[1].mean()), sole))
    else:
        anchors = [feet_anchor(sp) for sp in sprites]
    ox = int(max(CELL // 2, max(fx for fx, _ in anchors) + 2))
    right = max(sp.width - fx for sp, (fx, _) in zip(sprites, anchors))
    W = int(np.ceil((ox + right + 2) / 16) * 16)
    W = max(W, CELL)
    out = []
    for sp, (fx, sole) in zip(sprites, anchors):
        c = Image.new("RGBA", (W, CELL), (0, 0, 0, 0))
        c.alpha_composite(sp, (int(round(ox - fx)), CELL - 2 - sole))
        out.append(c)
    print(f"célula {W}x{CELL}, origem (pés) em ({ox}, {CELL - 2})")
    for i, f in enumerate(out):
        f.save(f"{a.name}_{i:02d}.png")
    sheet = Image.new("RGBA", (W * len(out), CELL)); [sheet.alpha_composite(f, (i * W, 0)) for i, f in enumerate(out)]
    sheet.save(f"{a.name}_sheet.png")
    ms = [int(x) for x in a.ms.split(",")]
    ms = ms * len(out) if len(ms) == 1 else ms
    g = []
    for f in out:
        bg = Image.new("RGBA", f.size, (205, 210, 215, 255)); bg.alpha_composite(f); g.append(bg.convert("RGB").resize((W * 2, CELL * 2), Image.NEAREST))
    g[0].save(f"{a.name}.gif", save_all=True, append_images=g[1:], duration=ms, loop=0)
    v = Image.new("RGBA", sheet.size, (205, 210, 215, 255)); v.alpha_composite(sheet); v.convert("RGB").resize((sheet.width * 2, CELL * 2), Image.NEAREST).save(f"{a.name}_view.png")
    for i, sp in enumerate(sprites):
        print(i, "sprite", sp.size)


if __name__ == "__main__":
    main()
