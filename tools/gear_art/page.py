from PIL import Image, ImageDraw, ImageFont
W,H=758,1024
F='/usr/share/fonts/truetype/dejavu/'
big=ImageFont.truetype(F+'DejaVuSerif-Bold.ttf',40); sm=ImageFont.truetype(F+'DejaVuSerif.ttf',26); it=ImageFont.truetype(F+'DejaVuSerif-Italic.ttf' if __import__('os').path.exists(F+'DejaVuSerif-Italic.ttf') else F+'DejaVuSerif.ttf',22)
items={'helm':('Helm','Head','+1 DEF   +2 HP'),'cuirass':('Cuirass','Chest','+2 DEF   +3 HP'),
       'shortsword':('Shortsword','Main hand','+3 ATK'),'dagger':('Dagger','Main hand','+2 ATK   +1 ACU')}
q=lambda v: round(v/17)*17   # 16 gray levels, as on the PW2
for n,(name,slot,stats) in items.items():
    art=Image.open(n+'_clean.png')
    bw,bh=680,760
    s=min(bw/art.width,bh/art.height)
    art=art.resize((int(art.width*s),int(art.height*s)),Image.LANCZOS)
    pg=Image.new('L',(W,H),255)
    pg.paste(art,((W-art.width)//2,30+(bh-art.height)//2))
    d=ImageDraw.Draw(pg)
    d.line((40,810,W-40,810),fill=0,width=2)
    d.text((W//2,830),name,font=big,fill=0,anchor='mt')
    d.text((W//2,885),slot+' · Common',font=it,fill=85,anchor='mt')
    d.text((W//2,930),stats,font=sm,fill=0,anchor='mt')
    pg.point(q).save('relic_gear_'+n+'.png',optimize=True)
