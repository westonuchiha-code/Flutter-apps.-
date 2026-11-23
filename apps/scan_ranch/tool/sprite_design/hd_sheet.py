import sys
from hd import *
from hd_drake import drake
from hd_hound import hound
PALS=[PAL_CRIMSON,
 {**PAL_CRIMSON,'body':ramp('#3f7d3a','#0b2a24','#d7ff7a'),'back':ramp('#2a5a2f','#071a16','#6fae48'),'belly':ramp('#c9d98a','#4a5a2a','#f8ffd0'),'accent':ramp('#6e2c8f','#1a0628','#d98aff'),'outline':hexc('#08130e'),'outline_lit':hexc('#1d3a22'),'eye':hexc('#ff3df2'),'eyeglow':hexc('#ffd6fb')},
 {**PAL_CRIMSON,'body':ramp('#41607f','#0b1424','#a8d8ff'),'back':ramp('#2c425b','#070d18','#5d84a8'),'belly':ramp('#c8d4e0','#4a5a70','#ffffff'),'accent':ramp('#d98a2b','#4a1a08','#ffd88a'),'outline':hexc('#070b14'),'outline_lit':hexc('#1c2c42'),'eye':hexc('#39e0ff'),'eyeglow':hexc('#e0fbff')},
]
specs=[drake(),hound()]
imgs=[[render(sp,p,scale=4) for p in PALS] for sp in specs]
w,h=imgs[0][0].size
out=Image.new('RGB',(w*3+20,h*2+10),(20,20,26))
for r,row in enumerate(imgs):
    for c,im in enumerate(row): out.paste(im,(c*(w+10),r*(h+10)))
out.save('hd_sheet.png')
