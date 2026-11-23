from hd import *
from hd_more import eye, claws

def beetle():
    s=Sprite('Beetle'); s.dy=-1
    # far legs (spiky)
    for (a,b,c) in [((20,48),(13,52),(10,60)),((30,50),(26,55),(26,61)),((40,50),(43,55),(45,61))]:
        s.add('back',cap([(a[0]-2,a[1],2.2),(b[0]-2,b[1],1.7),(c[0]-2,c[1],1.1)]))
    # underside
    s.add('back',ell(30,47,16,6),group='under')
    # head low in front, mandibles
    s.add('body',ell(53,47,6,5.5,0.1),group='head')
    s.add('claw',poly([(57,47),(63,45),(60,50)]),depth=0.4)
    s.add('claw',poly([(57,50),(63,53),(58,53)]),depth=0.4)
    # elytra: long low dome
    shell=ell(27,39,18,10.5,-0.08)
    s.add('body',shell,group='shell')
    # pronotum (armoured shield) with the great horn
    s.add('body',ell(45,40,8.5,8,0.1),group='pron')
    s.add('accent',cap([(48,35,3.8),(54,27,3),(57,19,2),(55,13,1)]),group='horn')
    s.add('accent',cap([(42,34,2.2),(41,29,1.2)]),group='horn2')
    # near legs with spurs
    for (a,b,c) in [((21,50),(14,53),(11,61)),((31,51),(28,56),(29,61)),((41,50),(45,55),(48,61))]:
        s.add('body',cap([(a[0],a[1],2.5),(b[0],b[1],1.9),(c[0],c[1],1.3)]),depth=0.6)
        s.px(c[0]+1,c[1],'claw_d'); s.px(c[0]+2,c[1]+1,'claw_tip')
        s.px(b[0],b[1]-2,'claw_d')
    # elytra seam + ridge highlight
    for x in range(12,42):
        t=(x-27)/18
        y=round(39-10.5*(1-t*t)**0.5)+5
        s.px(x,y,'outline')
    eye(s,52,44)
    return s

def mantis():
    s=Sprite('Mantis'); s.dy=-1
    # far legs
    s.add('back',cap([(24,48,1.8),(18,46,1.4),(14,61,1.1)]))
    s.add('back',cap([(30,48,1.8),(36,45,1.4),(39,61,1.1)]))
    # abdomen (curved, segmented)
    s.add('body',cap([(30,47,5),(22,44,6),(14,38,5),(9,32,3)]),group='core')
    for (x,y0) in ((13,34),(18,38),(23,41)):
        for y in range(y0,y0+9):
            if (y+x)%2==0: s.px(x,y,'outline')
    # folded wings over abdomen
    s.add('accent',poly([(32,41),(8,28),(9,34),(31,45)]),depth=0.4)
    # thorax rising
    s.add('body',cap([(31,45,4.2),(37,34,3.2),(40,26,3)]),group='core')
    # head: wide triangle, big compound eyes
    s.add('body',poly([(35,19),(50,18),(46,27),(39,27)]),group='head')
    s.add('accent',cap([(39,18,1),(34,9,0.6)]),depth=0.3)
    s.add('accent',cap([(46,18,1),(52,8,0.6)]),depth=0.3)
    # raised scythe arm: upper arm, forearm folded down with serrated blade
    s.add('body',cap([(39,31,3),(48,24,2.6)]),group='arm')
    s.add('body',cap([(48,24,2.4),(54,36,1.8)]),group='arm')
    s.add('claw',poly([(54,36),(58,30),(57,40),(52,42)]),depth=0.3)
    for (x,y) in [(50,28),(51,31),(52,34)]: s.px(x,y,'claw_tip')
    # near legs
    s.add('body',cap([(26,49,2),(19,47,1.5),(16,61,1.2)]))
    s.add('body',cap([(32,48,2),(38,46,1.5),(42,61,1.2)]))
    stamp(s,41,19,['##','#yy','#yyy',' ##'],{'#':'outline','y':'eye'})
    s.px(42,20,'eyeglow')
    s.add('mouth',poly([(44,25),(48,24),(46,27)]),flat=True)
    return s

def wraith():
    s=Sprite('Wraith')
    # tall pointed hood + tattered cloak with sharp hem
    cloak=poly([(33,4),(40,10),(46,24),(50,40),(52,52),(48,50),(47,60),(43,53),(40,62),(37,54),(33,61),(30,53),(26,59),(25,50),(20,54),(22,40),(24,24),(28,10)])
    s.add('accent',cloak,group='cloak')
    # dark face cavity
    s.add('mouth',ell(39,22,6,8,0.15),flat=True)
    # skull jaw glimpsed in the dark + glowing eyes
    s.add('belly',poly([(36,26),(44,25),(43,30),(37,30)]),group='jaw')
    for x in (37,39,41): fang(s,x,30,3,True)
    stamp(s,36,18,['y..y'],{'y':'eye'})
    s.px(36,18,'eyeglow'); s.px(39,18,'eyeglow')
    s.px(37,18,'eye'); s.px(40,18,'eye')
    # skeletal arms, long claws
    s.add('belly',cap([(44,34,2),(52,30,1.4),(57,27,1)]),group='arm')
    s.add('belly',cap([(45,40,2),(53,42,1.4),(58,39,1)]),group='arm2')
    for (x,y) in [(58,25),(59,27),(59,37),(60,39),(58,41)]:
        s.px(x,y,'claw_d'); s.px(x+1,y-1,'claw_tip')
    # cloak fold lines
    for (x0,y0,x1,y1) in [(30,20,28,52),(36,34,36,56),(44,30,46,50)]:
        n=max(abs(x1-x0),abs(y1-y0))
        for i in range(0,n,1):
            s.px(round(x0+(x1-x0)*i/n),round(y0+(y1-y0)*i/n),'outline')
    return s

def harpy():
    s=Sprite('Harpy'); s.dy=-1
    # raised wing behind, feathered tips
    s.add('back',poly([(30,32),(22,12),(14,2),(8,6),(10,10),(4,12),(8,16),(2,20),(8,24),(4,30),(12,32),(10,38),(20,38)]),group='wing')
    for (x0,y0,x1,y1) in [(28,32,12,6),(26,33,6,18),(24,35,8,30)]:
        n=max(abs(x1-x0),abs(y1-y0))
        for i in range(n): s.px(round(x0+(x1-x0)*i/n),round(y0+(y1-y0)*i/n),'outline')
    # tail fan
    s.add('accent',poly([(24,46),(6,52),(8,56),(12,53),(12,58),(18,54),(26,50)]),group='tail')
    # far leg
    s.add('back',cap([(29,49,3),(27,55,1.5),(28,60,1.3)]),group='bl')
    # lean body
    s.add('body',ell(32,38,9,12,-0.45),group='core')
    s.add('belly',inter(ell(32,38,9,12,-0.45),ell(37,42,5,8,-0.45)),group='core')
    # near wing, raised
    s.add('accent',poly([(32,32),(30,10),(34,2),(38,6),(38,10),(42,8),(42,14),(46,14),(42,22),(40,34),(36,38)]),group='wing2')
    for (x0,y0,x1,y1) in [(34,32,34,4),(37,32,41,10)]:
        n=max(abs(x1-x0),abs(y1-y0))
        for i in range(n): s.px(round(x0+(x1-x0)*i/n),round(y0+(y1-y0)*i/n),'outline')
    s.add('body',cap([(36,28,5),(42,22,5)]),group='core')
    s.add('body',ell(44,20,6.5,6),group='core')
    # crest spikes
    for (x,y) in [(40,15),(37,17),(34,20)]:
        s.add('accent',poly([(x+2,y+2),(x-6,y-5),(x+1,y-1)]),depth=0.3)
    # hooked beak
    s.add('claw',poly([(48,18),(57,20),(58,24),(55,27),(54,23),(48,23)]),depth=0.4)
    s.px(49,21,'outline')
    # leg: feathered thigh, scaly shin, big talons
    s.add('body',cap([(35,47,4),(37,53,2.2)]),group='fl')
    s.add('back',cap([(37,53,1.8),(35,58,1.5),(37,60.5,1.4)]),group='fl2')
    claws(s,[(39,60),(41,60),(33,60)])
    eye(s,44,17)
    return s
