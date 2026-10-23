from PIL import Image, ImageDraw
SRC='source/'
spec = {
 'helm': dict(crop=(30,90,1295,1485), masks=[(895,90,990,150),(1175,370,1240,425),(275,475,325,520),(370,730,418,780),(1215,785,1270,840),(1005,920,1060,975),(315,1135,370,1195),(35,1300,180,1485),(1070,1165,1175,1205)]),
 'cuirass': dict(crop=(95,40,740,875), masks=[(120,20,340,63),(95,790,128,960),(445,856,606,895),(670,850,740,875)]),
 'shortsword': dict(crop=(480,100,745,1505), masks=[(735,1400,745,1505)]),
 'dagger': dict(crop=(560,50,965,2430), masks=[]),
}
def level(v, lo=55, hi=200):
    if v<=lo: return 0
    if v>=hi: return 255
    return int((v-lo)*255/(hi-lo))
lut=[level(i) for i in range(256)]
for n,s in spec.items():
    im=Image.open(SRC+n+'.png').convert('L')
    d=ImageDraw.Draw(im)
    for m in s['masks']: d.rectangle(m, fill=255)
    im=im.crop(s['crop']).point(lut)
    im.save(n+'_clean.png')
    print(n, im.size)
