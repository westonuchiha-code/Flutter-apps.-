# Pixel sprite authoring kit: build 32x32 grids from runs, render previews.
from PIL import Image
W=H=32
class S:
    def __init__(s,name): s.name=name; s.g=[['.']*W for _ in range(H)]; s.eye=None
    def r(s,y,x0,x1,c='b'):
        for x in range(x0,x1+1):
            if 0<=x<W and 0<=y<H: s.g[y][x]=c
        return s
    def p(s,x,y,c):
        if 0<=x<W and 0<=y<H: s.g[y][x]=c
        return s
    def rows(s,y0,spec):
        # spec: list of lists of (x0,x1,c)
        for i,runs in enumerate(spec):
            for (x0,x1,c) in runs: s.r(y0+i,x0,x1,c)
        return s
    def text(s): return [''.join(r) for r in s.g]

def hexc(h): h=h.lstrip('#'); return tuple(int(h[i:i+2],16) for i in (0,2,4))

def render(sprite, pal, eye=None, scale=8, bg=(40,40,48)):
    g=[row[:] for row in sprite.g]
    img=Image.new('RGB',(W*scale,H*scale),bg)
    filled=lambda x,y: 0<=x<W and 0<=y<H and g[y][x]!='.'
    # outline
    out=[[False]*W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            if g[y][x]=='.' and any(filled(x+dx,y+dy) for dx,dy in ((1,0),(-1,0),(0,1),(0,-1))): out[y][x]=True
    px=img.load()
    for y in range(H):
        for x in range(W):
            c=None
            if out[y][x]: c=pal['o']
            elif g[y][x]!='.': c=pal.get(g[y][x], (255,0,255))
            if c:
                for yy in range(scale):
                    for xx in range(scale): px[x*scale+xx,y*scale+yy]=c
    if eye and sprite.eye:
        ex,ey=sprite.eye
        for (dx,dy,c) in eye:
            x,y=ex+dx,ey+dy
            col=pal[c]
            for yy in range(scale):
                for xx in range(scale): px[x*scale+xx,y*scale+yy]=col
    return img

def art(name, rows, eye, top=0):
    """ASCII authoring: rows of up to 32 chars starting at y=top."""
    s=S(name)
    for i,row in enumerate(rows):
        for x,ch in enumerate(row):
            if ch not in '. ' and x<W: s.g[top+i][x]=ch
    s.eye=eye
    return s
