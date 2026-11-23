from hd import *
from hd_drake import drake
from hd_hound import hound
from hd_more import *
from hd_fix import beetle, mantis, wraith, harpy
from hd_sheet import PALS
from scan import crt
specs=[drake(),hound(),beetle(),gargoyle(),wyrm(),brute(),mantis(),wraith(),harpy(),scorpion()]
imgs=[crt(render(sp,PALS[i%3],scale=4,bg=(14,14,18)),3) for i,sp in enumerate(specs)]
w,h=imgs[0].size; cols=5
out=Image.new('RGB',(w*cols+10*(cols-1),h*2+10),(8,8,10))
for i,im in enumerate(imgs): out.paste(im,((i%cols)*(w+10),(i//cols)*(h+10)))
out.save('all10.png')
