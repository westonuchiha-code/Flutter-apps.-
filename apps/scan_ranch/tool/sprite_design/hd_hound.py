from hd import *

def hound():
    s=Sprite('Hound')
    s.dy=-2
    # far legs (behind): hind leg with a backward hock, slim foreleg
    s.add('back',cap([(17,40,6),(13,48,3.4)]),group='bl1')
    s.add('back',cap([(13,48,2.4),(16,55,1.7)]),group='bl1')
    s.add('back',cap([(16,55,1.7),(14,60,1.6)]),group='bl1')
    s.add('back',cap([(12,60.6,1.4),(19,60.8,1.0)]),group='bl1',depth=0.5)
    s.add('back',cap([(41,42,4.5),(43,50,2.4),(42,58,1.9),(43,60,1.7)]),group='bl2')
    s.add('back',cap([(41,60.6,1.4),(48,60.8,1.0)]),group='bl2',depth=0.5)
    # tail: thick, spiked
    s.add('body',cap([(12,36,5),(6,30,4.5),(4,23,3),(6,17,1.5)]),group='core')
    for (x,y,sz) in [(5,27,2.8),(3,21,2.4)]:
        s.add('accent',poly([(x+sz,y+2),(x-sz*1.4,y-sz*0.6),(x+sz*0.2,y-sz*1.5)]),depth=0.4)
    # mane spikes along the back and neck
    for (x,y,sz) in [(18,29,3.5),(24,27,4),(30,25,4.5),(36,23,5),(41,21,4.5)]:
        s.add('accent',poly([(x-sz,y+3),(x-sz*0.9,y-sz*1.4),(x+sz,y+2)]),depth=0.5)
    torso=union(ell(28,38,16,9,-0.08),ell(38,34,9,10,-0.3))
    s.add('body',torso,group='core')
    # neck + head
    s.add('body',cap([(42,32,7.5),(48,27,6.5)]),group='core')
    s.add('body',ell(50,25,8,7,-0.15),group='core')
    s.add('mouth',poly([(51,27),(63,28),(61,37),(52,35)]),flat=True)
    s.add('body',cap([(51,24,5.5),(61,27,3.6)]),group='core')
    s.add('body',cap([(50,33,3.6),(60,37,2.4)]),depth=0.6)
    # ears
    s.add('accent',poly([(44,22),(41,13),(48,19)]),depth=0.5)
    s.add('body',poly([(48,20),(47,12),(52,19)]),depth=0.5)
    # near legs: muscular haunch -> hock angled back -> long foot
    s.add('body',cap([(21,41,7.5),(17,49,3.6)]),group='fl1')
    s.add('body',cap([(17,49,2.6),(21,56,1.9)]),group='fl1')
    s.add('body',cap([(21,56,1.8),(19,60.5,1.7)]),group='fl1')
    s.add('body',cap([(18,60.8,1.6),(26,60.8,1.1)]),group='ft1',depth=0.5)
    # foreleg: shoulder, straight forearm, wrist bend, paw
    s.add('body',cap([(45,39,6),(47,47,3.2)]),group='fl2')
    s.add('body',cap([(47,47,2.7),(46,56,2.0),(48,60,1.8)]),group='fl2')
    s.add('body',cap([(46,60.8,1.6),(54,60.8,1.1)]),group='ft2',depth=0.5)
    for x in (27,55,20,49):
        s.px(x,60,'claw_d'); s.px(x+1,61,'claw_d'); s.px(x+1,62,'claw_tip')
    # teeth (snarl)
    for x,l,c in ((53,4,1),(57,3,0),(60,2,0)):
        fang(s,x,28,l,down=True,curve=c)
    for x,l,c in ((55,3,1),(59,2,0)):
        fang(s,x,35,l,down=False,curve=c)
    s.px(62,25,'outline')
    # eye
    stamp(s,50,21,['##  ','#yy#',' #P#'],{'#':'outline','y':'eye','P':'pupil'})
    s.px(51,22,'eyeglow')
    return s
