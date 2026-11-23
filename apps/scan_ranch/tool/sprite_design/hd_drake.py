from hd import *

def drake():
    s=Sprite('Drake')
    s.dy=-2
    # back leg
    s.add('back',ell(25,43,7,9,0.35),group='bleg')
    s.add('back',cap([(25,49,4),(22,55,3),(24,60,2.5)]),group='bleg')
    s.add('back',cap([(19,61,2),(29,61,2.2)]),depth=0.5)
    # tail
    s.add('body',cap([(24,40,7.5),(14,36,5.5),(7,30,3.8),(2,23,1.6)]),group='core')
    for (x,y,sz) in [(16,31,3),(10,26,2.5),(5,20,2)]:
        s.add('accent',poly([(x-sz,y+2),(x-sz*0.4,y-sz*1.6),(x+sz,y+1)]),depth=0.4)
    # back spikes
    for (x,y,sz) in [(24,26,3.5),(29,22,4),(34,18,4),(39,14,3.5)]:
        s.add('accent',poly([(x-sz,y+3),(x-sz*0.6,y-sz*1.3),(x+sz*0.9,y+2)]),depth=0.5)
    torso=ell(31,35,12.5,11,-0.55)
    s.add('body',torso,group='core')
    s.add('body',cap([(35,31,6.5),(42,22,5.8)]),group='core')
    s.add('belly',inter(union(torso,cap([(35,31,6.5),(42,22,5.8)])),cap([(47,20,3.5),(44,30,4.5),(40,40,5)])),group='core')
    # mouth interior (behind jaws)
    s.add('mouth',poly([(47,20),(60,20),(58,27),(48,26)]),flat=True)
    # lower jaw
    s.add('body',cap([(45,24,4),(55,27,2.8)]),depth=0.6)
    # front arm
    s.add('body',cap([(39,33,3.6),(44,40,2.7),(48,38,2.3)]),depth=0.7)
    for (x,y) in [(49,36),(50,39)]:
        s.add('claw',poly([(x-1,y-1),(x+3,y+1),(x-1,y+2)]),depth=0.3)
    # front leg
    s.add('body',ell(32,46,8,10.5,0.4),group='fleg')
    s.add('body',cap([(34,52,4.2),(31,57,3),(33,60.5,2.6)]),group='fleg')
    s.add('body',cap([(30,61.5,2.3),(40,61.5,2.5)]),depth=0.5)
    for x in (41,44):
        s.add('claw',poly([(x-2,59.5),(x+2.5,61.5),(x-2,63)]),depth=0.3)
    # head
    s.add('body',ell(46,16,9,7,-0.2),group='core')
    s.add('body',cap([(48,17,6),(59,20,4.2)]),group='core')
    s.add('accent',cap([(42,11,2.6),(36,6,1.7),(31,4,0.8)]),depth=0.5)
    s.add('accent',cap([(46,10,2.2),(43,4,1.2),(40,2,0.5)]),depth=0.5)
    # brow ridge
    s.add('accent',cap([(46,12,1.8),(53,13,1.4)]),depth=0.4)
    # teeth
    for x in (50,53,56,59):
        s.px(x,22,'tooth'); s.px(x,23,'tooth')
    for x in (51,54):
        s.px(x,25,'tooth'); s.px(x,24,'tooth')
    # nostril
    s.px(58,17,'outline')
    # eye: angular, glowing
    stamp(s,48,13,['  ##','#yyy#','#yP#',' ##'],{'#':'outline','y':'eye','P':'pupil'})
    s.px(49,14,'eyeglow')
    return s

if __name__=='__main__':
    drake_img=render(drake(),PAL_CRIMSON,scale=6)
    drake_img.save('hd_drake.png')
