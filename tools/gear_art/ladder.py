import math, random
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

BASE = Image.open('sword_lv_170.png').convert('L')
W0, H0 = BASE.size
d0 = ImageDraw.Draw(BASE)
d0.rectangle((0, 0, 14, H0), fill=255); d0.rectangle((450, 0, W0, H0), fill=255)  # frame lines
d0.rectangle((240, 2270, W0, H0), fill=255)  # speck by the tip

LEFT = [(171,470),(174,630),(176,780),(178,930),(181,1080),(183,1230),(184,1380),(185,1530),(186,1680),(188,1830),(190,1980),(196,2130)]
RIGHT = [(285,470),(281,630),(278,780),(275,930),(273,1080),(268,1230),(266,1380),(264,1530),(261,1680),(258,1830),(257,1980),(252,2130)]
TIP = (224, 2285)
POMMEL = (228, 72)
FULLER = 228

def poly_mask(inset):
    m = Image.new('L', (W0, H0), 0)
    pts = [(x + inset, y) for x, y in LEFT] + [(TIP[0], TIP[1] - inset * 4)] + [(x - inset, y) for x, y in reversed(RIGHT)]
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m

BLADE = poly_mask(7)

# silhouette: dilate the drawing, then fill holes by flooding the outside
dark = BASE.point(lambda v: 255 if v < 200 else 0).filter(ImageFilter.MaxFilter(21))
sil = dark.copy(); ImageDraw.floodfill(sil, (0, 0), 128); ImageDraw.floodfill(sil, (W0 - 1, H0 - 1), 128)
SIL = sil.point(lambda v: 0 if v == 128 else 255)
SIL = ImageChops.lighter(SIL, poly_mask(0))

def layer():
    return Image.new('L', (W0, H0), 255)

def stamp(dst, lay, mask=None):
    if mask is not None:
        lay = Image.composite(lay, Image.new('L', lay.size, 255), mask)
    return ImageChops.darker(dst, lay)

def runes(rng):
    lay = layer(); d = ImageDraw.Draw(lay)
    y0, y1 = 545, 590
    for y in (y0, y1):
        d.line((150, y, 310, y), fill=0, width=4)
    x = 178
    while x < 278:
        top, bot = y0 + 9, y1 - 9
        d.line((x, top, x, bot), fill=0, width=3)
        k = rng.randrange(4)
        if k == 0: d.line((x, top, x + 9, top + 9), fill=0, width=3)
        elif k == 1: d.line((x, bot, x + 9, bot - 10), fill=0, width=3)
        elif k == 2: d.line((x, (top + bot) // 2, x + 9, top), fill=0, width=3)
        else: d.line((x, top + 6, x + 9, bot - 6), fill=0, width=3)
        x += 16
    return lay

def fern(d, x, y, ang, length, depth, rng, w):
    x2 = x + math.cos(ang) * length; y2 = y + math.sin(ang) * length
    d.line((x, y, x2, y2), fill=0, width=w)
    if depth == 0: return
    n = 3
    for i in range(1, n + 1):
        t = i / (n + 1)
        bx = x + (x2 - x) * t; by = y + (y2 - y) * t
        sub = length * (0.55 - 0.1 * t)
        for s in (-1, 1):
            fern(d, bx, by, ang + s * math.radians(58 + rng.uniform(-6, 6)), sub, depth - 1, rng, max(2, w - 1))

def edge_x(y, side):
    pts = RIGHT if side > 0 else LEFT
    for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
        if y1 <= y <= y2:
            return x1 + (x2 - x1) * (y - y1) / (y2 - y1)
    return pts[-1][0]

def feather(d, x, y, ang, length, rng, barb=13, w=2):
    # frost feather: a gently curving stem with fine barbs swept toward its tip
    pts = [(x, y)]
    curve = rng.uniform(-0.004, 0.004)
    for i in range(int(length / 4)):
        ang += curve * 4
        x += math.cos(ang) * 4; y += math.sin(ang) * 4
        pts.append((x, y))
    d.line(pts, fill=0, width=w)
    for i in range(2, len(pts) - 1, 2):
        px, py = pts[i]
        t = i / len(pts)
        L = barb * (1 - 0.7 * t) * rng.uniform(0.8, 1.1)
        for sgn in (-1, 1):
            ba = ang + sgn * math.radians(48)
            d.line((px, py, px + math.cos(ba) * L, py + math.sin(ba) * L), fill=0, width=1 if L < 7 else w)

def frost(rng, y_from, y_to, step):
    lay = layer(); d = ImageDraw.Draw(lay)
    y = y_from; side = 1
    while y < y_to:
        # feathers start at the fuller and sweep out toward the edge and the tip
        ang = math.atan2(1.6, side * 1.0) + rng.uniform(-0.12, 0.12)
        feather(d, FULLER + side * 5, y, ang, rng.uniform(85, 110), rng)
        if rng.random() < 0.5:
            feather(d, FULLER + side * 5, y + 20, ang + side * -0.25, rng.uniform(45, 60), rng, barb=9)
        side = -side
        y += step
    return lay

def gem(cx, cy, r):
    lay = layer(); d = ImageDraw.Draw(lay)
    d.ellipse((cx - r - 5, cy - r - 5, cx + r + 5, cy + r + 5), fill=255)  # clear the old boss
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=0, width=4)
    t = r * 0.45
    table = [(cx + t * math.cos(math.radians(a)), cy + t * math.sin(math.radians(a))) for a in range(22, 382, 45)]
    d.polygon(table, outline=0, width=3)
    for a, (tx, ty) in zip(range(22, 382, 45), table):
        ox = cx + r * math.cos(math.radians(a)); oy = cy + r * math.sin(math.radians(a))
        d.line((tx, ty, ox, oy), fill=0, width=3)
    # shade the lower-right facets with hatching, keep a highlight upper-left
    for k in range(-r, r, 6):
        for px in range(-r, r):
            py = k + px * 0.6
            if px * px + py * py < (r - 3) ** 2 and (px + py) > t * 0.6:
                d.point((cx + px, cy + py), fill=0)
    return lay

def stipple(region_mask, rng, spacing=7, rad=1.7):
    lay = layer(); d = ImageDraw.Draw(lay)
    m = np.array(region_mask)
    b = np.array(BASE)
    for y in range(0, H0, spacing):
        for x in range((y // spacing % 2) * spacing // 2, W0, spacing):
            jx, jy = x + rng.uniform(-1.5, 1.5), y + rng.uniform(-1.5, 1.5)
            ix, iy = int(jx), int(jy)
            if 0 <= ix < W0 and 0 <= iy < H0 and m[iy, ix] and b[iy, ix] > 200:
                d.ellipse((jx - rad, jy - rad, jx + rad, jy + rad), fill=0)
    return lay

def gild_mask():
    m = Image.new('L', (W0, H0), 0); d = ImageDraw.Draw(m)
    cx, cy = POMMEL
    d.ellipse((cx - 58, cy - 58, cx + 58, cy + 58), fill=255)
    d.ellipse((cx - 40, cy - 40, cx + 40, cy + 40), fill=0)
    d.rectangle((0, 360, W0, 460), fill=255)
    m = ImageChops.multiply(m, SIL.filter(ImageFilter.MinFilter(15)))
    return ImageChops.subtract(m, poly_mask(-3))

def rays(size, center, rng):
    w, h = size
    lay = Image.new('L', size, 255); d = ImageDraw.Draw(lay)
    cx, cy = center
    n = 48
    for i in range(n):
        a0 = 2 * math.pi * i / n
        if i % 2: continue
        a1 = a0 + 2 * math.pi / n * 0.8
        # each ray is hatched with fine lines, longer and shorter alternating
        L = 330 if i % 4 == 0 else 250
        for j in range(6):
            a = a0 + (a1 - a0) * j / 5
            d.line((cx + math.cos(a) * 90, cy + math.sin(a) * 70, cx + math.cos(a) * L, cy + math.sin(a) * L), fill=110, width=1)
    # fade toward the edges
    fade = Image.new('L', size, 0); fd = ImageDraw.Draw(fade)
    for r in range(330, 0, -6):
        v = int(255 * min(1, (r / 330) ** 1.6))
        fd.ellipse((cx - r, cy - r, cx + r, cy + r), fill=v)
    return ImageChops.lighter(lay, fade)

GRIP_L = [(208, 140), (193, 368)]
GRIP_R = [(245, 140), (265, 368)]

def grip_x(y, pts):
    (x1, y1), (x2, y2) = pts
    return x1 + (x2 - x1) * (y - y1) / (y2 - y1)

def leather(img):
    # clear the old grip texture inside the outline, then wind a leather strap around it
    clear = Image.new('L', img.size, 0)
    ImageDraw.Draw(clear).polygon([(grip_x(140, GRIP_L) + 4, 142), (grip_x(366, GRIP_L) + 4, 366),
                                   (grip_x(366, GRIP_R) - 4, 366), (grip_x(140, GRIP_R) - 4, 142)], fill=255)
    img = Image.composite(Image.new('L', img.size, 255), img, clear)
    lay = layer(); d = ImageDraw.Draw(lay)
    rise, gap = 16, 19
    y = 150
    while y < 380:
        yl, yr = y, y - rise
        xl, xr = grip_x(min(max(yl, 140), 368), GRIP_L), grip_x(min(max(yr, 140), 368), GRIP_R)
        d.line((xl, yl, xr, yr), fill=0, width=3)
        # shade the band below each seam, heavier toward the right (away from the light)
        for k in range(1, 6):
            t = k / 6
            hx = xl + (xr - xl) * (0.45 + 0.55 * t)
            hy = yl + (yr - yl) * (0.45 + 0.55 * t)
            d.line((hx, hy + 3, hx - 2, hy + gap - 4), fill=0, width=2)
        y += gap
    lay = Image.composite(lay, Image.new('L', img.size, 255), clear)
    return ImageChops.darker(img, lay)


def hatch(d, inside, cx, cy, r, step=5, ang=0.6):
    # diagonal hatching clipped by a predicate
    for k in range(-2 * r, 2 * r, step):
        for px in range(-r, r + 1):
            py = k + px * ang
            if -r <= py <= r and inside(px, py):
                d.point((cx + px, cy + py), fill=0)

def stone(style, cx, cy, r):
    """A set stone whose cut shows the item's build style."""
    lay = layer(); d = ImageDraw.Draw(lay)
    if style == 'blood':
        # teardrop: round bottom, sides running straight to a sharp point
        rr = r * .6; bx, by = cx, cy + r * .32; tx, ty = cx, cy - r * 1.05
        dist = by - ty; alpha = math.acos(rr / dist)        # tangent angle from the circle centre
        pts = [(tx, ty)]
        for i in range(0, 101):
            a = -math.pi / 2 + alpha + (2 * math.pi - 2 * alpha) * i / 100
            pts.append((bx + rr * math.cos(a), by + rr * math.sin(a)))
        d.polygon(pts, outline=0, width=4)
        poly = Image.new('L', lay.size, 0); ImageDraw.Draw(poly).polygon(pts, fill=255)
        pm = np.array(poly)
        hatch(d, lambda px, py: pm[int(cy + py), int(cx + px)] and not ((px + r * .3) ** 2 + (py + r * .1) ** 2 < (r * .22) ** 2), cx, cy, int(r * 1.3), step=3)
        return lay
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=0, width=4)
    inside = lambda px, py: px * px + py * py < (r - 3) ** 2
    if style == 'rime':
        # six-point star cut: alternate star facets shaded, like a snowflake
        outer = [(cx + (r - 2) * math.cos(math.radians(a)), cy + (r - 2) * math.sin(math.radians(a))) for a in range(-90, 270, 60)]
        inner = [(cx + r * .45 * math.cos(math.radians(a)), cy + r * .45 * math.sin(math.radians(a))) for a in range(-60, 300, 60)]
        star = [p for pair in zip(outer, inner) for p in pair]
        d.polygon(star, outline=0, width=3)
        for (ox, oy) in outer: d.line((cx, cy, ox, oy), fill=0, width=2)
        for (ix, iy) in inner: d.line((cx, cy, ix, iy), fill=0, width=1)
        sm = Image.new('L', lay.size, 0); ImageDraw.Draw(sm).polygon(star, fill=255); sa = np.array(sm)
        hatch(d, lambda px, py: inside(px, py) and not sa[int(cy + py), int(cx + px)], cx, cy, r, step=4)
    elif style == 'affliction':
        # serpent's eye: dark iris, slit pupil, a glint
        hatch(d, lambda px, py: inside(px, py) and px * px + py * py > (r * .25) ** 2, cx, cy, r, step=3, ang=-0.5)
        slit = [(cx, cy - r * .85), (cx + r * .2, cy), (cx, cy + r * .85), (cx - r * .2, cy)]
        d.polygon(slit, fill=0)
        d.ellipse((cx - r * .55, cy - r * .55, cx - r * .3, cy - r * .3), fill=255)
    elif style == 'retribution':
        # thorns around the setting
        for a in range(0, 360, 36):
            t = math.radians(a)
            base1 = (cx + (r + 1) * math.cos(t - .16), cy + (r + 1) * math.sin(t - .16))
            base2 = (cx + (r + 1) * math.cos(t + .16), cy + (r + 1) * math.sin(t + .16))
            tip = (cx + (r + 15) * math.cos(t), cy + (r + 15) * math.sin(t))
            d.polygon([base1, tip, base2], fill=0)
        d.ellipse((cx - r * .5, cy - r * .5, cx + r * .5, cy + r * .5), outline=0, width=3)
        hatch(d, lambda px, py: inside(px, py) and px + py > r * .3, cx, cy, r, step=5)
    elif style == 'riposte':
        # two crossed swords cut bright into a dark stone, set square to the blade.
        hatch(d, inside, cx, cy, r, step=3)
        def rect(ux, uy, a0, a1, hw):
            vx, vy = -uy, ux
            return [(cx + ux * a0 + vx * hw, cy + uy * a0 + vy * hw), (cx + ux * a1 + vx * hw, cy + uy * a1 + vy * hw),
                    (cx + ux * a1 - vx * hw, cy + uy * a1 - vy * hw), (cx + ux * a0 - vx * hw, cy + uy * a0 - vy * hw)]
        for deg in (-45, -135):  # the first design, drawn square to the sword so it turns with it
            t = math.radians(deg); ux, uy = math.cos(t), math.sin(t); vx, vy = -uy, ux
            hw = r * .13
            blade = [(cx + ux * r * .92, cy + uy * r * .92), (cx + ux * r * .6 + vx * hw, cy + uy * r * .6 + vy * hw),
                     (cx - ux * r * .4 + vx * hw, cy - uy * r * .4 + vy * hw), (cx - ux * r * .4 - vx * hw, cy - uy * r * .4 - vy * hw),
                     (cx + ux * r * .6 - vx * hw, cy + uy * r * .6 - vy * hw)]
            d.polygon(blade, fill=255, outline=0, width=2)
            guard = [(x - ux * r * .45, y - uy * r * .45) for x, y in rect(vx, vy, -r * .4, r * .4, r * .08)]
            d.polygon(guard, fill=255, outline=0, width=2)
            d.polygon(rect(ux, uy, -r * .82, -r * .5, r * .07), fill=255, outline=0, width=2)
            px, py = cx - ux * r * .86, cy - uy * r * .86
            d.ellipse((px - r * .11, py - r * .11, px + r * .11, py + r * .11), fill=255, outline=0, width=2)
    else:
        return gem(cx, cy, r)
    return lay

def build(rarity, style='plain'):
    rng = random.Random(7)
    img = BASE.copy()
    lv = ['common', 'uncommon', 'rare', 'epic', 'legendary'].index(rarity)
    if lv >= 1: img = leather(img)  # no blade etching (Mike, 2026-10-01)
    if lv >= 2:
        pass  # img = stamp(img, frost(rng, 650, 820 if lv == 2 else (1300 if lv == 3 else 2120), 75 if lv < 4 else 55), BLADE)
        g = stone(style, *POMMEL, 34)
        cx, cy = POMMEL
        clear = Image.new('L', img.size, 0); ImageDraw.Draw(clear).ellipse((cx - 39, cy - 39, cx + 39, cy + 39), fill=255)
        img = Image.composite(Image.new('L', img.size, 255), img, clear)
        img = ImageChops.darker(img, g)
    if lv >= 3: img = stamp(img, stipple(gild_mask(), rng))
    if lv >= 4:
        g2 = stone(style, 229, 440, 16)
        clear = Image.new('L', img.size, 0); ImageDraw.Draw(clear).ellipse((229 - 20, 440 - 20, 229 + 20, 440 + 20), fill=255)
        img = Image.composite(Image.new('L', img.size, 255), img, clear)
        img = ImageChops.darker(img, g2)
    return img, lv

def page(rarity, title, stats, style='plain'):
    art, lv = build(rarity, style)
    ang = 40
    big = 2.0  # supersample before the final downscale
    sil = SIL
    art_r = art.rotate(ang, resample=Image.BICUBIC, expand=True, fillcolor=255)
    sil_r = sil.rotate(ang, resample=Image.BICUBIC, expand=True, fillcolor=0)
    s = 0.6
    sz = (int(art_r.width * s), int(art_r.height * s))
    art_s = art_r.resize(sz, Image.LANCZOS); sil_s = sil_r.resize(sz, Image.LANCZOS)
    W, H = 758, 1024
    pg = Image.new('L', (W, H), 255)
    def rot(px, py):
        cxr, cyr = art.width / 2, art.height / 2
        a = math.radians(-ang)
        rx = (px - cxr) * math.cos(a) - (py - cyr) * math.sin(a) + art_r.width / 2
        ry = (px - cxr) * math.sin(a) + (py - cyr) * math.cos(a) + art_r.height / 2
        return rx * s, ry * s
    px, py = rot(*POMMEL)
    ox, oy = int(110 - px), int(95 - py)   # pommel near the top-left; the blade runs off the frame
    if lv >= 4:
        gx, gy = rot(229, 400)
        R = rays((W, H), (ox + gx, oy + gy), random.Random(3))
        hide = Image.new('L', (W, H), 0); hide.paste(sil_s.filter(ImageFilter.MaxFilter(9)), (ox, oy))
        R = Image.composite(Image.new('L', (W, H), 255), R, hide)
        pg = ImageChops.darker(pg, R)
    tmp = Image.new('L', (W, H), 255); tmp.paste(art_s, (ox, oy))
    ImageDraw.Draw(tmp).rectangle((0, 800, W, H), fill=255)
    pg = ImageChops.darker(pg, tmp)
    ImageDraw.Draw(pg).rectangle((0, 800, W, H), fill=255)
    F = '/usr/share/fonts/truetype/dejavu/'
    d = ImageDraw.Draw(pg)
    d.line((40, 812, W - 40, 812), fill=0, width=2)
    d.text((W // 2, 828), title, font=ImageFont.truetype(F + 'DejaVuSerif-Bold.ttf', 38), fill=0, anchor='mt')
    d.text((W // 2, 880), 'Main hand · ' + rarity.capitalize(), font=ImageFont.truetype(F + 'DejaVuSerif-Italic.ttf', 22), fill=85, anchor='mt')
    sm = ImageFont.truetype(F + 'DejaVuSerif.ttf', 22)
    for i, line in enumerate(stats):
        d.text((W // 2, 920 + i * 30), line, font=sm, fill=0, anchor='mt')
    return pg.point(lambda v: round(v / 17) * 17)

LADDER = [
    ('common', 'Plain Shortsword', ['+3 ATK']),
    ('uncommon', 'Tempered Shortsword', ['+4 ATK   +1 STR', '+5% crit chance']),
    ('rare', 'Runed Shortsword', ['+4 ATK   +2 ACU', '+1 cold damage   20% chance hits frost']),
    ('epic', 'Relic-bound Shortsword', ['+5 ATK   +2 STR   +2 ACU', '+2 cold damage   25% chance hits frost']),
    ('legendary', 'Mythic Shortsword', ['+6 ATK   +3 STR   +2 ACU', '+2 cold   30% frost   +25% vs frosted']),
]
if __name__ == '__main__':
    for r, t, st in LADDER:
        page(r, t, st).save('ladder_%s.png' % r, optimize=True)
    print('ok')
