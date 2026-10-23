"""Build the plugin's gear art from the approved sources (run after prep.py; ladder.py's sword input is made here).

Writes relic.koplugin/gear_art/<key>.png: 600x600, 16 grays (the PW2's), white ground.
  shortsword_<rarity>  the approved rarity ladder on the long sword (Mike, 2026-10-01)
  dagger, holdout      long weapons as a diagonal, per the approved look
  helm, cuirass        engravings, same picture at every rarity for now
Run from tools/gear_art:  python3 prep.py && python3 build_plugin.py
"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'relic.koplugin', 'gear_art')
SIZE = 600
q = lambda v: round(v / 17) * 17


def fit(im, box=SIZE, pad=20):
    im = im.convert('L')
    # trim white margins
    inv = im.point(lambda v: 255 if v < 235 else 0)
    bb = inv.getbbox()
    if bb:
        im = im.crop(bb)
    s = min((box - 2 * pad) / im.width, (box - 2 * pad) / im.height)
    im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
    pg = Image.new('L', (box, box), 255)
    pg.paste(im, ((box - im.width) // 2, (box - im.height) // 2))
    return pg.point(q)


def diagonal(im, ang=40):
    return im.convert('L').rotate(ang, resample=Image.BICUBIC, expand=True, fillcolor=255)


def sword_input():
    p = os.path.join(HERE, 'sword_lv_170.png')
    if not os.path.exists(p):
        im = Image.open(os.path.join(HERE, 'source', 'sword.png')).convert('L').crop((295, 118, 760, 2410))
        lo, hi = 60, 170
        im.point(lambda v: 0 if v <= lo else 255 if v >= hi else int((v - lo) * 255 / (hi - lo))).save(p)


def main():
    os.makedirs(OUT, exist_ok=True)
    os.chdir(HERE)
    sword_input()
    import ladder
    for r, title, stats in ladder.LADDER:
        page = ladder.page(r, title, stats).crop((0, 0, 758, 790))   # art only, no text band
        fit(page, pad=0).save(os.path.join(OUT, 'shortsword_%s.png' % r), optimize=True)
    fit(diagonal(Image.open('dagger_clean.png'))).save(os.path.join(OUT, 'dagger.png'), optimize=True)
    fit(diagonal(Image.open('shortsword_clean.png'))).save(os.path.join(OUT, 'holdout.png'), optimize=True)
    fit(Image.open('helm_clean.png')).save(os.path.join(OUT, 'helm.png'), optimize=True)
    fit(Image.open('cuirass_clean.png')).save(os.path.join(OUT, 'cuirass.png'), optimize=True)
    for f in sorted(os.listdir(OUT)):
        print(f, os.path.getsize(os.path.join(OUT, f)) // 1024, 'KB')


if __name__ == '__main__':
    main()
