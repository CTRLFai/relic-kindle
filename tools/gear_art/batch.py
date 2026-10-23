"""Gear art batch 1 (picked 2026-10-02..05, sources downloaded 2026-10-07).

Every picture is cut out of its plate by connected components: the plate is
thresholded, strokes are joined with a dilation, and only the pieces named in
PICK are kept. Everything else on the plate (letters, figure numbers, scale
bars, signatures, neighbouring figures) turns white, so no hand masks.

  python3 -I batch.py analyze SRC_DIR OUT_DIR   numbered component sheets, to choose PICK
  python3 -I batch.py build   SRC_DIR           writes relic.koplugin/gear_art/<file>.png

SRC_DIR holds the downloaded sources (get-gear-sources.sh): <LABEL>.png from
Wikimedia, ia_<item>_n<page>.jpg from the Internet Archive.
"""
import os
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'relic.koplugin', 'gear_art')
SIZE = 600

V5, V6 = None, None
T2, T3, T4 = 'dictionnairerai02violuoft', 'dictionnairerai03violuoft', 'dictionnairerai04violuoft'
EVANS, BOUCHOT, MEYER = 'ancientbronzeimp00evanuoft', 'cu31924029482019', 'handbookoforname1900meye'

# label: (source, box as page fractions x0,y0,x1,y1 or None for the whole plate)
# Boxes for Internet Archive pages are the measured ones from candidates.md.
SRC = {
    'S1': ('S1.png', None), 'S2': ('S2.png', None), 'S3': ('S3.png', None),
    'D1': ('D1.png', None), 'D2': ('D2.png', None), 'H1': ('H1.png', None),
    'T1': ('T1.png', None), 'T2': ('T2.png', None), 'T3': ('T3.png', None),
    'W1': ('W1.png', None), 'W2': ('W2.png', None), 'W3': ('W3.png', None),
    'M1': ('M1.png', None), 'M2': ('M2.png', None), 'M3': ('M3.png', None),
    'HE1': ('HE1.png', None), 'HE2': ('HE2.png', None), 'HE3': ('HE3.png', None),
    'CU1': ('CU1.png', None), 'CU2': ('CU2.png', None),
    'BU1': ('BU1.png', None), 'BU2': ('BU2.png', None), 'BU3': ('BU3.png', None),
    'GA1': ('GA1.png', None), 'GA2': ('GA2.png', None), 'GA3': ('GA3.png', None),
    'GL1': ('GL1.png', None), 'GL2': ('GL2.png', None),
    'LE1': ('LE1.png', None), 'LE2': ('LE2.png', None),
    'BO1': ('BO1.png', None), 'BO2': ('BO2.png', None), 'BO3': ('BO3.png', None),
    'ST1': ('ST1.png', None), 'ST2': ('ST2.png', None),
    'TR1': ('TR1.png', None), 'TR2': ('TR2.png', None),
    'RI1': ('ia_%s_n31.jpg' % T3, (.12, .18, .58, .45)),
    'RI2': ('ia_%s_n31.jpg' % T3, (.68, .19, .99, .42)),
    'RI3': ('ia_%s_n30.jpg' % T3, (.21, .58, .58, .78)),
    'SI1': ('ia_%s_n32.jpg' % T3, (.29, .27, .60, .59)),
    'BA1': ('ia_%s_n32.jpg' % T3, (.29, .41, .60, .59)),
    'AM1': ('ia_%s_n13.jpg' % T3, (.31, .19, .88, .54)),
    'AM2': ('ia_%s_n16.jpg' % T3, (.06, .20, .81, .68)),
    'AM3': ('ia_%s_n17.jpg' % T3, (.36, .11, .77, .47)),
    'CI1': ('ia_%s_n335.jpg' % T3, (.15, .12, .88, .48)),
    'CI2': ('ia_%s_n335.jpg' % T3, (.15, .53, .85, .88)),
    'CI3': ('ia_%s_n336.jpg' % T3, (.07, .15, .89, .48)),
    'CH1': ('ia_%s_n170.jpg' % T3, (.22, .31, .57, .78)),
    'CH2': ('ia_%s_n177.jpg' % T3, (.28, .20, .80, .56)),
    'GB1': ('ia_%s_n304.jpg' % T3, (.05, .20, .78, .53)),
    'CL1': ('ia_%s_n121.jpg' % T4, (.24, .27, .82, .69)),
    'CL2': ('ia_%s_n122.jpg' % T4, (.04, .08, .87, .71)),
    'MN1': ('ia_%s_n123.jpg' % T4, (.28, .10, .74, .48)),
    'MN2': ('ia_%s_n123.jpg' % T4, (.30, .46, .75, .75)),
    'SK1': ('ia_%s_n568.jpg' % T2, (.10, .58, .66, .88)),
    'MA1': ('ia_%s_n111.jpg' % MEYER, (.16, .32, .35, .50)),
    'MA3': ('ia_%s_n111.jpg' % MEYER, (.66, .53, .88, .70)),
    'MA4': ('ia_%s_n111.jpg' % MEYER, (.64, .10, .88, .32)),
    'TO1': ('ia_%s_n398.jpg' % EVANS, (.117, .261, .831, .718)),
    'TO2': ('ia_%s_n400.jpg' % EVANS, (.162, .306, .776, .662)),
    'TO3': ('ia_%s_n402.jpg' % EVANS, (.155, .296, .800, .610)),
    'TM1': ('ia_%s_n298.jpg' % BOUCHOT, (.134, .167, .866, .762)),
    'TM2': ('ia_%s_n300.jpg' % BOUCHOT, (.214, .239, .786, .764)),
    'TM3': ('ia_%s_n314.jpg' % BOUCHOT, (.207, .225, .783, .749)),
}

# Points (fractions of the cut-out region) on the object to keep; every component whose
# box holds a point is kept. Default: the biggest component.
PICK = {
    'S1': [(0.62, 0.5)], 'S2': [(0.52, 0.5)], 'D1': [(0.72, 0.5)], 'D2': [(0.55, 0.5)], 'H1': [(0.7, 0.4)],
    'T1': [(0.55, 0.5)], 'T3': [(0.3, 0.3), (0.15, 0.75)], 'W1': [(0.55, 0.5)], 'W2': [(0.73, 0.7)],
    'W3': [(0.57, 0.6)], 'M1': [(0.8, 0.5)], 'M2': [(0.64, 0.55)], 'M3': [(0.74, 0.5)], 'HE2': [(0.72, 0.6)],
    'BU3': [(0.5, 0.2)], 'GL2': [(0.5, 0.45)], 'LE1': [(0.25, 0.5)], 'RI1': [(0.68, 0.3)],
    'SI1': [(0.5, 0.28)], 'CL2': [(0.33, 0.56), (0.69, 0.39)], 'SK1': [(0.19, 0.43)],
}
# Extra per-label options: 'diag' (long weapon shown on the diagonal), 'join' (dilation px at 1000 px wide)
OPTS = {'S3': {'join': 20, 'diag': 40}, 'GA3': {'join': 20}, 'HE2': {'join': 4},
        # weapons lie on the diagonal like the first batch: grip top-left, point bottom-right
        'S1': {'diag': 220}, 'S2': {'diag': 220}, 'H1': {'diag': 220},
        'D1': {'diag': 40}, 'D2': {'diag': 40}, 'T3': {'diag': 40}, 'W1': {'diag': 40}, 'W2': {'diag': 40},
        'W3': {'diag': 40}, 'M1': {'diag': 40}, 'M2': {'diag': 40}, 'M3': {'diag': 40}}


def load(src_dir, label):
    name, box = SRC[label]
    im = Image.open(os.path.join(src_dir, name)).convert('L')
    if box:
        w, h = im.size
        im = im.crop((int(box[0] * w), int(box[1] * h), int(box[2] * w), int(box[3] * h)))
    # whiten the paper: map the paper tone (bright mode) to white, ink stays dark
    a = np.asarray(im, dtype=np.float32)
    paper = np.percentile(a, 90)
    lo = min(60.0, paper - 60)
    hi = paper - 18
    a = np.clip((a - lo) * 255.0 / max(1.0, hi - lo), 0, 255)
    return Image.fromarray(a.astype(np.uint8))


def components(im, label):
    a = np.asarray(im)
    ink = a < 150
    scale = im.width / 1000.0
    join = int(round(OPTS.get(label, {}).get('join', 9) * scale)) or 1
    joined = ndimage.binary_dilation(ink, iterations=join)
    lab, n = ndimage.label(joined)
    sizes = ndimage.sum(ink, lab, range(1, n + 1))
    order = [i + 1 for i in np.argsort(-sizes) if sizes[i] > 40 * scale * scale]
    return lab, order, sizes


def analyze(src_dir, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    font = ImageFont.load_default()
    for label in SRC:
        im = load(src_dir, label)
        lab, order, sizes = components(im, label)
        rgb = im.convert('RGB')
        d = ImageDraw.Draw(rgb)
        for k, ci in enumerate(order[:12], 1):
            ys, xs = np.where(lab == ci)
            d.rectangle((xs.min(), ys.min(), xs.max(), ys.max()), outline=(220, 0, 0), width=max(2, im.width // 300))
        for i in range(1, 10):   # 10% grid (blue), 50% lines darker, to read pick points
            x, y = im.width * i // 10, im.height * i // 10
            c = (0, 0, 200) if i == 5 else (120, 160, 255)
            d.line((x, 0, x, im.height), fill=c, width=max(1, im.width // 500))
            d.line((0, y, im.width, y), fill=c, width=max(1, im.width // 500))
        rgb.thumbnail((300, 400))
        rgb.save(os.path.join(out_dir, label + '.png'))
        print(label, len(order), 'components')


def cut(src_dir, label):
    im = load(src_dir, label)
    lab, order, _ = components(im, label)
    keep = set()
    for (fx, fy) in PICK.get(label, []):
        px, py = int(fx * im.width), int(fy * im.height)
        best = None
        for ci in order:
            ys, xs = np.where(lab == ci)
            if xs.min() <= px <= xs.max() and ys.min() <= py <= ys.max():
                area = (xs.max() - xs.min()) * (ys.max() - ys.min())
                if best is None or area < best[0]:
                    best = (area, ci)
        if best:
            keep.add(best[1])
    if not keep:
        keep = {order[0]}
    mask = np.isin(lab, list(keep))
    a = np.asarray(im).copy()
    a[~mask] = 255
    ys, xs = np.where(mask)
    out = Image.fromarray(a).crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    if OPTS.get(label, {}).get('diag'):
        out = out.rotate(OPTS[label]['diag'], resample=Image.BICUBIC, expand=True, fillcolor=255)
    return out


q = lambda v: round(v / 17) * 17


def fit(im, box=SIZE, pad=20):
    s = min((box - 2 * pad) / im.width, (box - 2 * pad) / im.height)
    im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
    pg = Image.new('L', (box, box), 255)
    pg.paste(im, ((box - im.width) // 2, (box - im.height) // 2))
    return pg.point(q)


def build(src_dir):
    os.makedirs(OUT, exist_ok=True)
    for label in SRC:
        fit(cut(src_dir, label)).save(os.path.join(OUT, label.lower() + '.png'), optimize=True)
        print(label, 'ok')


if __name__ == '__main__':
    if sys.argv[1] == 'analyze':
        analyze(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == 'build':
        build(sys.argv[2])
