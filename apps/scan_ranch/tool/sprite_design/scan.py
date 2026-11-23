from PIL import Image, ImageFilter, ImageChops
from hd import *
from hd_drake import drake
from hd_hound import hound
from hd_sheet import PALS

def scanlines(img, period, dark, thick=1):
    """Darken `thick` rows out of every `period` screen rows."""
    out=img.copy(); P=out.load(); w,h=out.size
    for y in range(h):
        if y % period >= period-thick:
            for x in range(w):
                r,g,b=P[x,y]; P[x,y]=(int(r*dark),int(g*dark),int(b*dark))
    return out

def crt(img, period):
    glow=img.filter(ImageFilter.GaussianBlur(3))
    base=ImageChops.add(img, glow.point(lambda v:int(v*0.45)))
    base=scanlines(base, period, 0.45, thick=max(1,period//2))
    # vignette
    w,h=base.size; P=base.load()
    for y in range(h):
        for x in range(w):
            dx=(x-w/2)/(w/2); dy=(y-h/2)/(h/2); f=max(0.55,1-0.35*(dx*dx+dy*dy))
            r,g,b=P[x,y]; P[x,y]=(int(r*f),int(g*f),int(b*f))
    return base

if __name__=="__main__":
  scale=6
  rows=[]
  for spr,pal in [(drake(),PALS[0]),(hound(),PALS[2])]:
      img=render(spr,pal,scale=scale,bg=(14,14,18))
      rows.append([img, scanlines(img,3,0.55), scanlines(img,scale,0.35,thick=2), crt(img,3)])
  w,h=rows[0][0].size
  out=Image.new('RGB',(w*4+30,h*2+10),(8,8,10))
  for r,row in enumerate(rows):
      for c,im in enumerate(row): out.paste(im,(c*(w+10),r*(h+10)))
  out.save('scan.png')
