from hd import *

def eye(s,x,y,big=False):
    if big:
        stamp(s,x,y,['###','#yy#','#yyP#',' ###'],{'#':'outline','y':'eye','P':'pupil'})
    else:
        stamp(s,x,y,['## ','#yy#',' #P#'],{'#':'outline','y':'eye','P':'pupil'})
    s.px(x+1,y+1,'eyeglow')

def claws(s,pts):
    for (x,y) in pts:
        s.px(x,y,'claw_d'); s.px(x+1,y+1,'claw_tip')

def beetle():
    s=Sprite('Beetle'); s.dy=-1
    # far legs
    for (a,b,c) in [((22,50),(17,55),(14,61)),((32,51),(30,56),(31,61)),((42,51),(45,56),(48,61))]:
        s.add('back',cap([(a[0]-2,a[1],2.2),(b[0]-2,b[1],1.6),(c[0]-2,c[1],1.2)]))
    # body under shell
    s.add('body',ell(30,46,17,8),group='core')
    # head + horn
    s.add('body',ell(49,44,7.5,6.5,0.1),group='head')
    s.add('accent',cap([(51,40,3.8),(56,31,2.6),(54,22,1.3)]),group='horn')
    s.add('accent',cap([(47,39,2.2),(46,33,1.2)]),group='horn2')
    # mandibles
    s.add('claw',poly([(55,47),(62,46),(58,51)]),depth=0.4)
    s.add('claw',poly([(54,49),(61,52),(56,53)]),depth=0.4)
    # shell (elytra)
    shell=ell(28,39,19,13,-0.05)
    s.add('accent',shell,group='shell')
    # near legs
    for (a,b,c) in [((22,51),(16,55),(13,61)),((32,52),(31,56),(33,61)),((42,51),(46,55),(50,61))]:
        s.add('body',cap([(a[0],a[1],2.4),(b[0],b[1],1.8),(c[0],c[1],1.3)]))
        s.px(c[0]+1,c[1],'claw_d'); s.px(c[0]+2,c[1]+1,'claw_tip')
    # elytra seam
    for x in range(12,44):
        y=round(37-((x-28)/19)**2*-3)
        s.px(x,y-2,'outline')
    eye(s,50,41)
    return s

def gargoyle():
    s=Sprite('Gargoyle'); s.dy=-1
    # wings (bat, behind)
    for side,dx in ((1,0),):
        s.add('accent',poly([(30,30),(16,10),(10,6),(4,14),(2,26),(8,24),(10,32),(16,30),(20,38),(26,36)]),group='wing')
        s.add('accent',poly([(36,28),(44,8),(50,4),(56,10),(60,20),(54,20),(54,28),(48,26),(46,34),(40,34)]),group='wing2')
    for (x0,y0,x1,y1) in [(30,30,10,6),(30,30,4,14),(30,31,8,24),(36,28,50,4),(36,28,60,20),(37,29,54,28)]:
        n=max(abs(x1-x0),abs(y1-y0))
        for i in range(n):
            s.px(round(x0+(x1-x0)*i/n),round(y0+(y1-y0)*i/n),'outline')
    # tail
    s.add('back',cap([(24,50,3),(14,54,2),(8,50,1.4)]))
    s.add('accent',poly([(4,46),(10,49),(5,53)]),depth=0.4)
    # back leg
    s.add('back',cap([(26,46,5),(32,52,3)]),group='bl')
    s.add('back',cap([(32,52,2.2),(26,57,1.6),(29,60.5,1.5)]),group='bl')
    s.add('back',cap([(28,61,1.3),(34,61,1)]),group='bl',depth=0.5)
    # torso
    s.add('body',ell(32,40,9.5,11,-0.2),group='core')
    s.add('body',ell(34,24,7.5,7),group='core')
    s.add('mouth',poly([(35,27),(42,27),(41,31),(36,31)]),flat=True)
    s.add('body',cap([(35,31,2.4),(41,31,1.6)]),depth=0.5)
    # horns
    s.add('accent',cap([(30,19,2.4),(26,13,1.6),(28,8,0.8)]),depth=0.5)
    s.add('accent',cap([(37,18,2.2),(39,12,1.4),(43,10,0.7)]),depth=0.5)
    # arm (long, knuckles down)
    s.add('body',cap([(37,33,3.6),(43,42,2.8),(45,51,2.4)]),group='arm')
    claws(s,[(44,53),(46,53),(48,52)])
    # front leg
    s.add('body',cap([(30,47,6),(38,52,3.4)]),group='fl')
    s.add('body',cap([(38,52,2.4),(31,57,1.8),(34,60.5,1.6)]),group='fl')
    s.add('body',cap([(33,61,1.5),(40,61,1.1)]),group='fl',depth=0.5)
    claws(s,[(41,60),(38,61)])
    for x,l,c in ((37,3,0),(40,2,0)): fang(s,x,27,l,True,c)
    fang(s,38,30,2,False)
    eye(s,36,21)
    return s

def wyrm():
    s=Sprite('Wyrm'); s.dy=-1
    body=cap([(4,58,2),(12,59,4.5),(22,60,6),(33,58,7),(41,51,6.5),(40,42,6),(43,33,5.5),(48,25,5.2)])
    s.add('body',body,group='core')
    s.add('belly',inter(body,cap([(12,62,3),(24,64,5),(36,62,5),(46,52,4),(46,42,4),(49,33,3.5),(53,27,3)])),group='core')
    # neck frill
    for (x,y,sz) in [(36,36,4),(36,28,4.5),(40,21,4.5)]:
        s.add('accent',poly([(x+1,y+3),(x-sz*1.6,y-sz*0.4),(x+2,y-sz*0.6)]),depth=0.4)
    s.add('body',ell(51,19,7,6,-0.15),group='head')
    s.add('mouth',poly([(52,21),(63,21),(61,28),(53,26)]),flat=True)
    s.add('body',cap([(51,19,5),(61,21,3.2)]),group='head')
    s.add('body',cap([(51,26,3),(60,28,2)]),depth=0.5)
    s.add('accent',cap([(47,15,2),(42,9,1),]),depth=0.5)
    for x,l,c in ((54,4,1),(58,3,0)): fang(s,x,23,l,True,c)
    fang(s,56,27,2,False)
    # tail spike
    s.add('accent',poly([(0,56),(5,56),(3,60)]),depth=0.3)
    # belly segment lines
    for (x,y) in [(18,63),(26,63),(34,62),(42,56),(45,48),(46,40),(49,32)]:
        s.px(x,y-2,'outline')
    eye(s,51,16)
    return s

def brute():
    s=Sprite('Brute'); s.dy=-1
    # back arm
    s.add('back',cap([(22,30,6),(16,42,4.8),(15,52,4.5)]),group='barm')
    # legs
    s.add('back',cap([(24,48,5.5),(22,56,4),(22,60,3.5)]),group='bleg')
    s.add('body',cap([(34,48,6),(36,56,4.4),(37,60,4)]),group='fleg')
    s.add('body',cap([(32,61,2.5),(44,61,2.2)]),group='fleg',depth=0.5)
    # torso + hump
    s.add('body',ell(30,40,13,11),group='core')
    s.add('body',ell(28,28,16,10,-0.1),group='core')
    s.add('belly',inter(ell(30,40,13,11),ell(37,46,5,6)),group='core')
    # head low and forward
    s.add('body',ell(45,25,6.5,6),group='head')
    s.add('body',cap([(43,30,4.5),(51,30,3.5)]),group='jaw')
    s.add('claw',poly([(46,27),(47,22),(49,27)]),depth=0.3)
    s.add('claw',poly([(50,27),(52,23),(52,28)]),depth=0.3)
    # shoulder plates
    for (x,y,sz) in [(18,20,4),(25,17,4.5),(32,17,4.5)]:
        s.add('accent',poly([(x-sz,y+4),(x,y-sz),(x+sz,y+4)]),depth=0.5)
    # front arm: massive
    s.add('body',cap([(38,28,7),(46,40,5.5),(48,51,5.5)]),group='farm')
    s.add('body',ell(49,55,6,5),group='farm')
    claws(s,[(53,57),(51,59),(48,60)])
    eye(s,45,22)
    return s

def mantis():
    s=Sprite('Mantis'); s.dy=-1
    # far legs
    s.add('back',cap([(24,48,1.6),(18,54,1.2),(14,61,1)]))
    s.add('back',cap([(30,48,1.6),(34,55,1.2),(36,61,1)]))
    # abdomen
    ab=ell(17,44,13,6.5,-0.25)
    s.add('body',ab,group='core')
    for x in (10,15,20):
        s.px(x,45+(x-10)//6,'outline'); s.px(x,46+(x-10)//6,'outline')
    # folded wings
    s.add('accent',poly([(30,38),(4,40),(8,44),(30,42)]),depth=0.4)
    # thorax
    s.add('body',cap([(28,44,4),(36,32,3.2),(40,24,2.8)]),group='core')
    # head (triangular)
    s.add('body',poly([(37,17),(49,19),(45,27),(39,26)]),group='head')
    s.add('accent',cap([(40,17,1),(36,9,0.6)]),depth=0.3)
    s.add('accent',cap([(44,18,1),(48,10,0.6)]),depth=0.3)
    # scythe arm
    s.add('body',cap([(40,30,2.6),(46,38,2.2)]),group='arm')
    s.add('body',cap([(46,38,2),(50,26,1.6)]),group='arm')
    s.add('claw',poly([(50,26),(55,30),(52,24),(50,20)]),depth=0.3)
    for (x,y) in [(48,30),(49,33),(47,35)]: s.px(x,y,'claw_tip')
    # near legs
    s.add('body',cap([(26,48,1.8),(20,54,1.4),(17,61,1.1)]))
    s.add('body',cap([(32,47,1.8),(38,54,1.4),(41,61,1.1)]))
    stamp(s,43,19,['##','#yy','#yyy','##'],{'#':'outline','y':'eye'})
    s.px(44,20,'eyeglow')
    s.add('mouth',poly([(45,25),(48,24),(46,27)]),flat=True)
    return s

def wraith():
    s=Sprite('Wraith')
    cloak=poly([(30,12),(42,16),(48,30),(50,46),(46,52),(48,58),(42,55),(40,60),(35,54),(31,59),(28,53),(22,57),(22,48),(16,50),(20,34),(22,22)])
    s.add('accent',cloak,group='cloak')
    hood=ell(34,22,10,10,0.1)
    s.add('accent',hood,group='cloak')
    s.add('mouth',ell(37,24,6.5,7.5),flat=True)
    s.add('belly',ell(38,24,5,6),group='skull')
    s.add('mouth',poly([(35,28),(42,28),(41,32),(36,32)]),flat=True)
    for x in (36,38,40): fang(s,x,28,3,True)
    # bony arms reaching forward
    s.add('belly',cap([(44,34,2),(52,36,1.4),(56,33,1.1)]),group='arm')
    s.add('belly',cap([(42,40,2),(50,44,1.4),(55,42,1.1)]),group='arm2')
    claws(s,[(57,31),(57,33),(56,41),(56,43)])
    stamp(s,35,21,['#y#y'],{'#':'outline','y':'eye'})
    s.px(36,21,'eyeglow'); s.px(38,21,'eyeglow')
    return s

def harpy():
    s=Sprite('Harpy'); s.dy=-1
    # wing behind
    s.add('accent',poly([(28,30),(12,6),(6,8),(4,18),(8,20),(6,28),(12,28),(12,36),(20,34)]),group='wing')
    # tail feathers
    s.add('accent',poly([(22,44),(4,50),(6,54),(10,52),(10,56),(22,48)]),group='tail')
    # far leg
    s.add('back',cap([(28,48,3),(26,55,1.6),(28,60,1.4)]),group='bl')
    # body
    s.add('body',ell(30,38,10,12,-0.4),group='core')
    s.add('belly',inter(ell(30,38,10,12,-0.4),ell(36,42,6,9,-0.4)),group='core')
    s.add('body',ell(42,22,7,6.5),group='core')
    # crest
    for (x,y) in [(38,16),(35,17),(32,19)]:
        s.add('accent',poly([(x+2,y+2),(x-5,y-4),(x+1,y-1)]),depth=0.3)
    # hooked beak
    s.add('claw',poly([(47,20),(56,22),(55,27),(52,25),(47,25)]),depth=0.4)
    s.px(54,26,'outline'); s.px(48,23,'outline')
    # near wing folded over body
    s.add('accent',poly([(28,30),(38,32),(34,44),(24,50),(20,42)]),group='wing2')
    # leg + talons
    s.add('body',cap([(34,47,4),(36,53,2)]),group='fl')
    s.add('back',cap([(36,53,1.7),(33,58,1.4),(35,60.5,1.3)]),group='fl2')
    claws(s,[(37,60),(39,60),(32,60)])
    eye(s,42,19)
    return s

def scorpion():
    s=Sprite('Scorpion'); s.dy=-1
    # far legs
    for x in (20,26,32,38):
        s.add('back',cap([(x,50,1.6),(x-3,55,1.2),(x-5,61,1)]))
    # tail arching over
    s.add('body',cap([(16,46,5),(8,38,4.4),(8,28,4),(14,19,3.6),(23,14,3.2),(31,14,2.8)]),group='tail')
    for (x,y) in [(9,40),(7,31),(11,23),(18,16),(26,13)]:
        s.px(x,y,'outline')
    s.add('accent',poly([(30,11),(38,15),(36,21),(33,17),(30,18)]),depth=0.4)
    s.px(36,21,'claw_tip'); s.px(37,22,'claw_tip')
    # body segments
    s.add('body',cap([(16,48,6),(30,48,6.5),(42,47,6)]),group='core')
    for x in (21,27,33): 
        for y in range(43,53): s.px(x,y,'outline') if y%2==0 else None
    # claw arm
    s.add('body',cap([(44,44,3),(50,38,2.6),(54,36,2.4)]),group='arm')
    s.add('accent',poly([(53,33),(62,30),(63,34),(58,35),(62,38),(54,40)]),group='pincer')
    s.px(58,35,'outline'); s.px(59,35,'outline')
    # near legs
    for x in (22,28,34,40):
        s.add('body',cap([(x,51,1.8),(x+2,56,1.3),(x+4,61,1)]))
    # head / face
    s.add('body',ell(46,48,5,5),group='head')
    for x,l in ((48,3),(50,2)): fang(s,x,51,l,True)
    eye(s,46,45)
    return s
