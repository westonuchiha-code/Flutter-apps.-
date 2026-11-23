from hd import *

def hound():
    s=Sprite('Hound')
    s.dy=-2
    # far legs (behind)
    s.add('back',cap([(16,42,5),(13,50,3.5),(15,57,3),(13,61,2.5)]),group='bl1')
    s.add('back',cap([(11,61,2.2),(19,61,2.2)]),group='bl1',depth=0.5)
    s.add('back',cap([(40,42,4.5),(42,51,3.2),(41,61,2.6)]),group='bl2')
    s.add('back',cap([(39,61,2.2),(47,61,2.3)]),group='bl2',depth=0.5)
    # tail: thick, spiked
    s.add('body',cap([(12,36,5),(6,30,4.5),(4,23,3),(6,17,1.5)]),group='core')
    for (x,y,sz) in [(5,27,2.8),(3,21,2.4)]:
        s.add('accent',poly([(x+sz,y+2),(x-sz*1.4,y-sz*0.6),(x+sz*0.2,y-sz*1.5)]),depth=0.4)
    # mane spikes along the back and neck
    for (x,y,sz) in [(18,29,3.5),(24,27,4),(30,25,4.5),(36,23,5),(41,21,4.5)]:
        s.add('accent',poly([(x-sz,y+3),(x-sz*0.9,y-sz*1.4),(x+sz,y+2)]),depth=0.5)
    torso=union(ell(28,38,16,9,-0.08),ell(38,34,9,10,-0.3))
    s.add('body',torso,group='core')
    s.add('belly',inter(torso,ell(30,47,13,5)),group='core')
    # neck + head
    s.add('body',cap([(42,32,7.5),(48,27,6.5)]),group='core')
    s.add('body',ell(50,25,8,7,-0.15),group='core')
    s.add('mouth',poly([(51,27),(63,28),(61,37),(52,35)]),flat=True)
    s.add('body',cap([(51,24,5.5),(61,27,3.6)]),group='core')
    s.add('body',cap([(50,33,3.6),(60,37,2.4)]),depth=0.6)
    # ears
    s.add('accent',poly([(44,22),(41,13),(48,19)]),depth=0.5)
    s.add('body',poly([(48,20),(47,12),(52,19)]),depth=0.5)
    # near legs
    s.add('body',ell(20,44,7,8,0.2),group='fl1')
    s.add('body',cap([(20,49,4.2),(17,55,3.2),(19,60.5,2.8)]),group='fl1')
    s.add('body',cap([(16,61.5,2.3),(24,61.5,2.5)]),depth=0.5)
    s.add('body',ell(44,42,6,8,-0.1),group='fl2')
    s.add('body',cap([(45,48,3.8),(47,55,3.1),(46,60.5,2.8)]),group='fl2')
    s.add('body',cap([(44,61.5,2.3),(52,61.5,2.5)]),depth=0.5)
    for x in (25,53):
        s.px(x,60,'toothshade'); s.px(x+1,61,'tooth'); s.px(x+2,62,'toothtip')
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
