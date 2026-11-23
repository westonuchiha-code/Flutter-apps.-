from hd import *

def drake():
    s=Sprite('Drake')
    s.dy=-2
    # back leg (far side)
    s.add('back',cap([(23,40,6.5),(29,48,3.8)]),group='bleg')
    s.add('back',cap([(29,48,2.6),(22,55,1.6)]),group='bleg')
    s.add('back',cap([(22,55,1.6),(25,60,1.5)]),group='bleg')
    s.add('back',cap([(24,60.6,1.4),(31,60.8,1.0)]),group='bleg',depth=0.5)
    for (x,y,c) in [(32,60,'claw_d'),(33,60,'claw_d'),(34,61,'claw_tip')]: s.px(x,y,c)
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
    # mouth interior (behind jaws)
    s.add('mouth',poly([(46,20),(60,20),(57,30),(47,28)]),flat=True)
    # lower jaw
    s.add('body',cap([(44,26,4),(55,31,2.8)]),depth=0.6)
    # front arm
    s.add('body',cap([(39,33,3.6),(44,40,2.7),(48,38,2.3)]),depth=0.7)
    for (x,y) in [(49,36),(50,39)]:
        s.add('claw',poly([(x-1,y-1),(x+3,y+1),(x-1,y+2)]),depth=0.3)
    # front leg: heavy thigh, knee jutting forward, thin shin swept back
    # to a raised heel, long toes and hooked claws.
    s.add('body',cap([(28,40,8.5),(37,48,4.2)]),group='fleg')
    s.add('body',cap([(37,48,2.8),(29,55,1.9)]),group='fleg')
    s.add('body',cap([(29,55,1.9),(32,60,1.7)]),group='fleg')
    s.add('body',cap([(31,60.6,1.6),(40,60.6,1.1)]),group='ftoe',depth=0.5)
    s.add('back',cap([(31,61.4,1.1),(37,61.6,0.8)]),group='ftoe2',depth=0.4)
    for (x,y,c) in [(41,59,'claw_d'),(42,59,'claw_d'),(43,60,'claw_d'),(43,61,'claw_tip'),
                    (38,61,'claw_d'),(39,62,'claw_tip'),(29,60,'claw_d'),(28,61,'claw_tip')]:
        s.px(x,y,c)
    # head
    s.add('body',ell(46,16,9,7,-0.2),group='core')
    s.add('body',cap([(48,17,6),(59,20,4.2)]),group='core')
    s.add('accent',cap([(42,11,2.6),(36,6,1.7),(31,4,0.8)]),depth=0.5)
    s.add('accent',cap([(46,10,2.2),(43,4,1.2),(40,2,0.5)]),depth=0.5)
    # brow ridge
    s.add('accent',cap([(46,12,1.8),(53,13,1.4)]),depth=0.4)
    # teeth
    # upper fangs (one big canine), lower fangs pointing up
    for x,l,c in ((49,3,0),(53,4,1),(57,3,0)):
        fang(s,x,21,l,down=True,curve=c)
    for x,l,c in ((51,3,0),(55,3,1)):
        fang(s,x,28,l,down=False,curve=c)
    # nostril
    s.px(58,17,'outline')
    # eye: angular, glowing
    stamp(s,48,13,['  ##','#yyy#','#yP#',' ##'],{'#':'outline','y':'eye','P':'pupil'})
    s.px(49,14,'eyeglow')
    return s

if __name__=='__main__':
    drake_img=render(drake(),PAL_CRIMSON,scale=6)
    drake_img.save('hd_drake.png')
