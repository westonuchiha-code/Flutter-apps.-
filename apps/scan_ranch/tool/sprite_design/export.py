# Exports each silhouette as a 64x64 "material map" PNG for the app:
#   R = material id (see MATS), G = tone 0..4 (x50), A = 255 where drawn.
# The app recolours these with a palette per creature. Artists can redraw
# these PNGs (or replace them with full-colour art; see the app README).
import json, sys, os
from PIL import Image
from hd import *
from hd_drake import drake
from hd_hound import hound
from hd_more import gargoyle, wyrm, brute, scorpion
from hd_fix import beetle, mantis, wraith, harpy

MATS=['none','body','back','belly','accent','claw','mouth','outline','eye','eyeglow','pupil','tooth','toothshade','toothtip','claw_d','claw_tip']

def export(spr):
    tone=shade_grid(spr)
    img=Image.new('RGBA',(W,H),(0,0,0,0)); P=img.load()
    for y in range(H):
        for x in range(W):
            if tone[y][x] is None: continue
            mat,t=tone[y][x]
            base=int(t); frac=t-base
            if frac>=0.5: base=min(4,base+1)
            P[x,y]=(MATS.index(mat),base*50,0,255)
    for y in range(H):
        for x in range(W):
            if tone[y][x] is not None: continue
            nb=[(x+dx,y+dy) for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)) if 0<=x+dx<W and 0<=y+dy<H and tone[y+dy][x+dx] is not None]
            if nb:
                xx,yy=nb[0]; mat,t=tone[yy][xx]
                lit=any(ax>x or ay>y for ax,ay in nb) and t>=2
                # outline: G = tone of the neighbouring skin's material id; B=1 lit side
                P[x,y]=(MATS.index('outline'),MATS.index(mat),1 if lit else 0,255)
    for x,y,c in spr.details:
        if 0<=x<W and 0<=y<H: P[x,y]=(MATS.index(c),0,0,255)
    return img

out=sys.argv[1]  # e.g. ../../assets/monsters (approved set) -- move rejected ones to rejected/
os.makedirs(out,exist_ok=True)
names=[]
for f in [drake,hound,beetle,gargoyle,wyrm,brute,mantis,wraith,harpy,scorpion]:
    spr=f(); name=spr.name.lower(); names.append(name)
    export(spr).save(f'{out}/{name}.png')
json.dump({'materials':MATS,'silhouettes':names},open(f'{out}/manifest.json','w'),indent=1)
print(names)
