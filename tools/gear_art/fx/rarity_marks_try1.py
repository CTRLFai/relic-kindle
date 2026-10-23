import sys, random, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
ART = '/home/claude/relic/relic.koplugin/gear_art/'
q = lambda a: (np.round(a / 17) * 17).clip(0, 255).astype(np.uint8)

def mask_of(a):
    ink = a < 235
    from scipy import ndimage
    m = ndimage.binary_closing(ink, iterations=6)
    m = ndimage.binary_fill_holes(m)
    return ndimage.binary_erosion(m, iterations=4)

def pitted(a, rng):
    m = mask_of(a); out = a.astype(float)
    ys, xs = np.where(m)
    im = Image.fromarray(out.astype(np.uint8)); d = ImageDraw.Draw(im)
    for _ in range(int(len(xs) / 900)):
        i = rng.randrange(len(xs)); x, y = xs[i], ys[i]; r = rng.choice([2, 3, 3, 4, 5])
        d.ellipse((x - r, y - r, x + r, y + r), fill=40)
        d.arc((x - r - 1, y - r - 1, x + r + 1, y + r + 1), 200, 20, fill=250, width=1)
    o = np.asarray(im).astype(float)
    return np.where(m, o, a)

def worn(a, rng):
    m = mask_of(a); out = a.astype(float)
    out = np.where(m, 255 - (255 - out) * 0.75, out)   # faded
    im = Image.fromarray(out.astype(np.uint8)); d = ImageDraw.Draw(im)
    ys, xs = np.where(m)
    for _ in range(int(len(xs) / 1200)):
        i = rng.randrange(len(xs)); x, y = xs[i], ys[i]
        ang = rng.uniform(-0.9, -0.3) if rng.random() < .7 else rng.uniform(0.3, 0.9)
        L = rng.randint(18, 60)
        x2, y2 = x + L * math.cos(ang), y + L * math.sin(ang)
        d.line((x, y, x2, y2), fill=255, width=3); d.line((x + 1, y + 3, x2 + 1, y2 + 3), fill=30, width=2)
    # chips bitten out of the edge
    from scipy import ndimage
    edge = m & ~ndimage.binary_erosion(m, iterations=3)
    ey, ex = np.where(edge)
    for _ in range(10):
        i = rng.randrange(len(ex)); r = rng.randint(5, 10)
        d.ellipse((ex[i] - r, ey[i] - r, ex[i] + r, ey[i] + r), fill=255)
    o = np.asarray(im).astype(float)
    return np.where(m, o, a)

def gleaming(a, rng):
    m = mask_of(a); h, w = a.shape
    yy, xx = np.mgrid[0:h, 0:w]
    band = np.zeros_like(a, dtype=float)
    for c, wd in [(0.38, 40), (0.5, 14)]:
        dist = np.abs((xx + yy) - (w + h) * c)
        band = np.maximum(band, np.clip(1 - dist / wd, 0, 1))
    out = a + (255 - a) * band * 0.95
    im = Image.fromarray(np.where(m, out, a).astype(np.uint8)); d = ImageDraw.Draw(im)
    ys, xs = np.where(m)
    for _ in range(3):
        i = rng.randrange(len(xs)); x, y = xs[i], ys[i]
        # engraved glint: a white four-point star with a thin dark outline
        for L, wd, c in [(40, 7, 0), (40, 4, 255), (16, 5, 0), (16, 2, 255)]:
            d.line((x - L, y, x + L, y), fill=c, width=wd); d.line((x, y - L, x, y + L), fill=c, width=wd)
        for L, wd, c in [(14, 5, 0), (14, 2, 255)]:
            d.line((x - L, y - L, x + L, y + L), fill=c, width=wd); d.line((x - L, y + L, x + L, y - L), fill=c, width=wd)
        d.ellipse((x - 6, y - 6, x + 6, y + 6), fill=255)
    return np.asarray(im).astype(float)

def runed(a, rng):
    m = mask_of(a); h, w = a.shape
    ys, xs = np.where(m)
    cy, cx = int(np.median(ys)), int(np.median(xs))
    im = Image.fromarray(a.astype(np.uint8)); d = ImageDraw.Draw(im)
    n, step, H = 4, 44, 30
    for k in range(n):
        x = cx + (k - (n - 1) / 2) * step
        strokes = [((0, -H), (0, H))]
        for _ in range(rng.randint(1, 2)):
            yy = rng.choice([-H, -H // 2, 0]); s_ = rng.choice([-1, 1])
            strokes.append(((0, yy), (14 * s_, yy + 14)))
        for (p0, p1), (wd, c) in [(st, wc) for wc in [(9, 255), (4, 0)] for st in strokes]:
            d.line((x + p0[0], cy + p0[1], x + p1[0], cy + p1[1]), fill=c, width=wd)
    return np.asarray(im).astype(float)

FX = {'pitted': pitted, 'worn': worn, 'gleaming': gleaming, 'runed': runed, 'plain': lambda a, r: a.astype(float)}
if __name__ == '__main__':
    out = sys.argv[1]; pairs = sys.argv[2:]
    tiles = []
    for p in pairs:
        f, e = p.split(':')
        a = np.asarray(Image.open(ART + f + '.png').convert('L')).astype(float)
        tiles.append((Image.fromarray(a.astype(np.uint8)), Image.fromarray(q(FX[e](a, random.Random(7)))), f, e))
    W = Image.new('L', (len(tiles) * 300, 620), 255); d = ImageDraw.Draw(W)
    for i, (b, t, f, e) in enumerate(tiles):
        W.paste(b.resize((300, 300)), (i * 300, 0)); W.paste(t.resize((300, 300)), (i * 300, 310))
    W.save(out)
