# 64x64 shaded sprite renderer: shapes -> masks -> SDF-based volume shading.
import math
from PIL import Image
W=H=64
BAYER=[0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5]

def ell(cx,cy,rx,ry,rot=0.0):
    c,s=math.cos(rot),math.sin(rot)
    def inside(x,y):
        dx,dy=x-cx,y-cy
        u=(dx*c+dy*s)/rx; v=(-dx*s+dy*c)/ry
        return u*u+v*v<=1
    return inside

def cap(pts):
    """Polyline of (x,y,r): a tapered tube."""
    def inside(x,y):
        for (x0,y0,r0),(x1,y1,r1) in zip(pts,pts[1:]):
            vx,vy=x1-x0,y1-y0; L2=vx*vx+vy*vy or 1e-9
            t=max(0,min(1,((x-x0)*vx+(y-y0)*vy)/L2))
            px,py=x0+vx*t,y0+vy*t; r=r0+(r1-r0)*t
            if (x-px)**2+(y-py)**2<=r*r: return True
        return False
    return inside

def poly(pts):
    def inside(x,y):
        ins=False; j=len(pts)-1
        for i in range(len(pts)):
            xi,yi=pts[i]; xj,yj=pts[j]
            if (yi>y)!=(yj>y) and x<(xj-xi)*(y-yi)/(yj-yi)+xi: ins=not ins
            j=i
        return ins
    return inside

def union(*fs): return lambda x,y: any(f(x,y) for f in fs)
def minus(a,b): return lambda x,y: a(x,y) and not b(x,y)

class Sprite:
    def __init__(s,name): s.name=name; s.shapes=[]; s.details=[]; s.eye=None; s.mouth=None; s.dy=0
    def add(s,mat,f,depth=1.0,flat=False,group=None):
        g=group if group is not None else 'auto%d'%len(s.shapes)
        dy=s.dy
        s.shapes.append((mat,(lambda x,y,f=f,dy=dy: f(x,y-dy)),depth,flat,g)); return s
    def px(s,x,y,c): s.details.append((x,y+s.dy,c)); return s

def lerp(a,b,t): return tuple(round(a[i]+(b[i]-a[i])*t) for i in range(3))
def hexc(h): h=h.lstrip('#'); return tuple(int(h[i:i+2],16) for i in (0,2,4))

def ramp(base, hue_cool, hue_warm):
    """5 tones: deep, shadow, base, light, highlight (hue shifted)."""
    b=hexc(base); cool=hexc(hue_cool); warm=hexc(hue_warm)
    return [lerp(b,cool,0.62),lerp(b,cool,0.33),b,lerp(b,warm,0.3),lerp(b,warm,0.58)]

def _dist(m):
    INF=99
    d=[[0 if not m[y][x] else INF for x in range(W)] for y in range(H)]
    for y in range(H):
        for x in range(W):
            if d[y][x]:
                for dx,dy,c in ((-1,0,1),(0,-1,1),(-1,-1,1.4),(1,-1,1.4)):
                    xx,yy=x+dx,y+dy
                    v=(d[yy][xx] if 0<=xx<W and 0<=yy<H else 0)+c
                    if v<d[y][x]: d[y][x]=v
    for y in range(H-1,-1,-1):
        for x in range(W-1,-1,-1):
            if d[y][x]:
                for dx,dy,c in ((1,0,1),(0,1,1),(1,1,1.4),(-1,1,1.4)):
                    xx,yy=x+dx,y+dy
                    v=(d[yy][xx] if 0<=xx<W and 0<=yy<H else 0)+c
                    if v<d[y][x]: d[y][x]=v
    return d

def shade_grid(spr, light=(-0.55,-0.65,0.55)):
    """Returns per-pixel (material, tone 0..4) or None, plus outline info."""
    owner=[[-1]*W for _ in range(H)]
    masks=[]
    for i,(mat,f,depth,flat,g) in enumerate(spr.shapes):
        m=[[f(x+0.5,y+0.5) for x in range(W)] for y in range(H)]
        masks.append(m)
        for y in range(H):
            for x in range(W):
                if m[y][x]: owner[y][x]=i
    groups={}
    for i,(mat,f,depth,flat,g) in enumerate(spr.shapes):
        groups.setdefault(g,[]).append(i)
    gdist={}; gdepth={}
    for g,idx in groups.items():
        um=[[any(masks[i][y][x] for i in idx) for x in range(W)] for y in range(H)]
        gdist[g]=_dist(um); gdepth[g]=max(spr.shapes[i][2] for i in idx)
    lx,ly,lz=light; ln=math.sqrt(lx*lx+ly*ly+lz*lz); lx,ly,lz=lx/ln,ly/ln,lz/ln
    tone=[[None]*W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            i=owner[y][x]
            if i<0: continue
            mat,f,depth,flat,g=spr.shapes[i]
            if flat: tone[y][x]=(mat,2.0); continue
            d=gdist[g]; R=min(max(max(r) for r in d) or 1, 7*gdepth[g])
            def h(xx,yy):
                if not(0<=xx<W and 0<=yy<H): return 0
                v=min(d[yy][xx],R)/R
                return math.sqrt(max(0,1-(1-v)**2))
            gx=(h(x+1,y)-h(x-1,y))/2; gy=(h(x,y+1)-h(x,y-1))/2
            nx,ny,nz=-gx*R*0.9,-gy*R*0.9,1.0
            nn=math.sqrt(nx*nx+ny*ny+nz*nz); nx,ny,nz=nx/nn,ny/nn,nz/nn
            lit=nx*lx+ny*ly+nz*lz-(y/H)*0.25
            t=max(0,min(4,(lit-0.05)/0.7*4))
            # inner line against a different group drawn in front
            line=False
            for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
                xx,yy=x+dx,y+dy
                if 0<=xx<W and 0<=yy<H:
                    j=owner[yy][xx]
                    if j>i and spr.shapes[j][4]!=g: line=True
            tone[y][x]=(mat,-1 if line else t)
    return tone

def render(spr, pal, scale=5, bg=(26,26,32), light=(-0.55,-0.65,0.55)):
    tone=shade_grid(spr,light)
    out=[[None]*W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            if tone[y][x] is None: continue
            mat,t=tone[y][x]; r=pal[mat]
            if t<0: out[y][x]=r[0]; continue
            base=int(t); frac=t-base
            if base<4 and 0.42<frac<0.58 and (x+y)%2==0: base+=1
            elif frac>=0.58: base=min(4,base+1)
            out[y][x]=r[base]
    for y in range(H):
        for x in range(W):
            if tone[y][x] is not None: continue
            nb=[(x+dx,y+dy) for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)) if 0<=x+dx<W and 0<=y+dy<H and tone[y+dy][x+dx] is not None]
            if nb:
                lit_side=any(xx>x or yy>y for xx,yy in nb)
                out[y][x]=pal['outline_lit'] if lit_side and y<H*0.75 else pal['outline']
    for x,y,c in spr.details:
        if 0<=x<W and 0<=y<H: out[y][x]=pal[c] if isinstance(c,str) else c
    img=Image.new('RGB',(W*scale,H*scale),bg); P=img.load()
    for y in range(H):
        for x in range(W):
            if out[y][x]:
                for yy in range(scale):
                    for xx in range(scale): P[x*scale+xx,y*scale+yy]=out[y][x]
    return img

def inter(a,b): return lambda x,y: a(x,y) and b(x,y)

PAL_CRIMSON={
 'body':ramp('#b3263e','#2a0b2e','#ff9c6a'),
 'back':ramp('#7d1a33','#1a0820','#c2455a'),
 'belly':ramp('#e3b48f','#7a3b3b','#fff1d6'),
 'accent':ramp('#2f3040','#07070f','#7a7f9a'),
 'claw':ramp('#e9e4d4','#6b6370','#ffffff'),
 'mouth':ramp('#3a0b16','#12030a','#5a1626'),
 'outline':hexc('#12060c'),'outline_lit':hexc('#4a1222'),
 'eye':hexc('#ffd23f'),'eyeglow':hexc('#fff6c4'),'pupil':hexc('#12060c'),'tooth':hexc('#f6f1e4'),
}

def stamp(spr, x0, y0, rows, key):
    for j,row in enumerate(rows):
        for i,ch in enumerate(row):
            if ch in key: spr.px(x0+i,y0+j,key[ch])
