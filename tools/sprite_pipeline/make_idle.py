#!/usr/bin/env python3
"""Idle de batalha por código a partir do quadro-semente (sem IA: zero tremido).
O corpo inteiro sobe 1 px; o "esticão" vai para a fileira entre o quadril e os tornozelos que
menos muda ao ser duplicada (canela reta), então nada deforma rosto, pescoço ou tronco.
Uso: make_idle.py <knight_192.png> <saida_idle.png>"""
import sys

import numpy as np
from PIL import Image

base = Image.open(sys.argv[1])
a = np.asarray(base).astype(int)
al = a[..., 3] > 0
rows = np.nonzero(al.any(1))[0]
top, bot = rows.min(), rows.max()
H = bot - top
cut = min(range(top + int(H * 0.55), top + int(H * 0.88)),
          key=lambda y: int((np.abs(a[y] - a[y + 1]).sum(-1) > 0).sum()))
up = Image.new("RGBA", base.size, (0, 0, 0, 0))
up.alpha_composite(base.crop((0, cut, base.width, base.height)), (0, cut))
up.alpha_composite(base.crop((0, 0, base.width, cut + 1)), (0, -1))
sheet = Image.new("RGBA", (base.width * 2, base.height), (0, 0, 0, 0))
sheet.alpha_composite(base, (0, 0))
sheet.alpha_composite(up, (base.width, 0))
sheet.save(sys.argv[2])
print("idle: corte na linha", cut)
