S=24; X0=200; Y0=90
cols="abcdefghij"
def cx(c):
    i=cols.index(c); return X0+i*S+(S*1.4 if i>=5 else 0)
def ry(r): return Y0+(r-1)*S
RL_M,RL_P=X0-2.4*S,X0-1.4*S
RR_P,RR_M=cx('j')+1.4*S,cx('j')+2.4*S
rows=24
LEGX=RR_M+60
W=int(LEGX+420); H=int(ry(rows)+90)
o=[];a=o.append
GND,VCC='#2563eb','#dc2626'
a(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" font-family="Arial, sans-serif">')
a(f'<rect width="{W}" height="{H}" fill="#fff"/>')
a(f'<rect x="{RL_M-38}" y="{Y0-48}" width="{RR_M-RL_M+60}" height="{ry(rows)-Y0+80}" rx="10" fill="#1f4d2e"/>')
for x,col,lab in ((RL_M,GND,'−'),(RL_P,VCC,'+'),(RR_P,VCC,'+'),(RR_M,GND,'−')):
    a(f'<line x1="{x}" y1="{Y0-22}" x2="{x}" y2="{ry(rows)+14}" stroke="{col}" stroke-width="4" opacity="0.55"/>')
    a(f'<text x="{x}" y="{Y0-28}" fill="#fff" font-size="15" font-weight="bold" text-anchor="middle">{lab}</text>')
    for r in range(1,rows+1): a(f'<circle cx="{x}" cy="{ry(r)}" r="3.4" fill="#d4af37"/>')
for r in range(1,rows+1):
    for half in ('abcde','fghij'):
        a(f'<rect x="{cx(half[0])-8}" y="{ry(r)-8}" width="{cx(half[-1])-cx(half[0])+16}" height="16" rx="7" fill="#2f6a42"/>')
        for c in half: a(f'<circle cx="{cx(c)}" cy="{ry(r)}" r="3.6" fill="#d4af37"/>')
    a(f'<text x="{RL_M-16}" y="{ry(r)+4}" fill="#cfe" font-size="12" text-anchor="end">{r}</text>')
for c in cols: a(f'<text x="{cx(c)}" y="{Y0-14}" fill="#cfe" font-size="12" text-anchor="middle">{c}</text>')
def jumper(x1,y1,x2,y2,col):
    mx=(x1+x2)/2; my=min(y1,y2)-14
    a(f'<path d="M{x1},{y1} Q{mx},{my} {x2},{y2}" fill="none" stroke="{col}" stroke-width="3" stroke-linecap="round"/>')
    for x,y in ((x1,y1),(x2,y2)): a(f'<circle cx="{x}" cy="{y}" r="4" fill="{col}"/>')
def leads(x1,y1,x2,y2): a(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="#aaa" stroke-width="2"/>')
def res(x1,y1,x2,y2,lab):
    leads(x1,y1,x2,y2); mx,my=(x1+x2)/2,(y1+y2)/2; v=abs(y2-y1)>abs(x2-x1)
    a(f'<rect x="{mx-(6 if v else 15)}" y="{my-(15 if v else 6)}" width="{12 if v else 30}" height="{30 if v else 12}" rx="4" fill="#e8c27a" stroke="#8a6"/>')
    left = v and x1 < cx('e')
    tx = mx+((-11 if left else 11) if v else 0); ty = my+(4 if v else -11); w = len(lab)*7+8
    bx = tx-w if left and v else (tx if v else tx-w/2)
    a(f'<rect x="{bx-(4 if left else -4) if v else bx}" y="{ty-13}" width="{w}" height="18" rx="4" fill="#123" opacity="0.9"/>')
    a(f'<text x="{tx}" y="{ty}" font-size="12" fill="#fff" text-anchor="{("end" if left else "start") if v else "middle"}">{lab}</text>')
def cap(x1,y1,x2,y2,lab,tx,ty):
    leads(x1,y1,x2,y2); mx,my=(x1+x2)/2,(y1+y2)/2
    a(f'<ellipse cx="{mx}" cy="{my}" rx="8" ry="6" fill="#d97706"/>')
    a(f'<text x="{tx}" y="{ty}" font-size="12" fill="#fff" text-anchor="middle">{lab}</text>')
def chip(r1,n,t1,t2):
    x=cx('e')-7; w=cx('f')-cx('e')+14; y=ry(r1)-11; h=(n-1)*S+22
    a(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="3" fill="#222"/>')
    a(f'<path d="M{x+w/2-7},{y} A7,7 0 0 0 {x+w/2+7},{y}" fill="#666"/>')
    a(f'<circle cx="{x+8}" cy="{ry(r1)}" r="3" fill="#fff"/>')
    a(f'<text x="{x+w/2}" y="{y+h/2-4}" fill="#fff" font-size="12" text-anchor="middle">{t1}</text>')
    a(f'<text x="{x+w/2}" y="{y+h/2+11}" fill="#bbb" font-size="10" text-anchor="middle">{t2}</text>')
marks=[]
def ext(c,r,num,lab,col,x=None):
    x=x if x is not None else cx(c); y=ry(r)
    a(f'<circle cx="{x}" cy="{y}" r="9" fill="{col}" stroke="#fff" stroke-width="1.5"/>')
    a(f'<text x="{x}" y="{y+4}" font-size="11" font-weight="bold" fill="#fff" text-anchor="middle">{num}</text>')
    marks.append((num,lab,col))
# rails joined (jumpers over the top of the board)
jumper(RL_P,ry(1),RR_P,ry(1),VCC); jumper(RL_M,ry(2),RR_M,ry(2),GND)
chip(3,7,'74HCT125','zócalo de 14')
for r,rail in ((3,RL_M),(7,RL_M),(9,RL_M)): jumper(cx('a'),ry(r),rail,ry(r),GND)
jumper(cx('a'),ry(6),RL_P,ry(6),VCC)
for r in (3,4,7): jumper(cx('j'),ry(r),RR_P,ry(r),VCC)
for r in (5,8): jumper(cx('j'),ry(r),RR_M,ry(r),GND)
cap(RR_P,ry(6),RR_M,ry(6),'C1',(RR_P+RR_M)/2,ry(6)-11)
res(cx('c'),ry(5),cx('c'),ry(11),'R2 220 Ω')
jumper(cx('a'),ry(12),RL_P,ry(12),VCC)
res(cx('d'),ry(12),cx('d'),ry(14),'R1 220 Ω')
chip(15,4,'H11L1','zócalo de 8')
res(cx('c'),ry(15),cx('c'),ry(20),'R3 220 Ω')
leads(cx('b'),ry(15),cx('b'),ry(16))
a(f'<rect x="{cx("b")-5}" y="{ry(15)+3}" width="10" height="18" fill="#eee" stroke="#333"/>')
a(f'<rect x="{cx("b")-5}" y="{ry(15)+3}" width="10" height="5" fill="#111"/>')
a(f'<text x="{cx("b")}" y="{ry(15)-12}" font-size="12" fill="#fff" text-anchor="middle">D1</text>')
jumper(cx('j'),ry(15),RR_P,ry(15),VCC); jumper(cx('j'),ry(16),RR_M,ry(16),GND)
cap(cx('h'),ry(15),cx('h'),ry(16),'C2',cx('h')-16,ry(15)+16)
res(cx('i'),ry(17),cx('i'),ry(22),'R4 470 Ω')
ext('b',4,'1','DB9 patilla 7 (TX del Next)','#16a34a')
ext('a',11,'2','DIN OUT patilla 5','#9333ea')
ext('a',14,'3','DIN OUT patilla 4','#9333ea')
ext(None,23,'4','DIN OUT patilla 2 (malla)','#9333ea',x=RL_M)
ext('a',16,'5','DIN IN patilla 5','#ea580c')
ext('a',20,'6','DIN IN patilla 4','#ea580c')
ext('j',22,'7','DB9 patilla 9 (RX del Next)','#16a34a')
ext(None,21,'8','DB9 patilla 8 (masa)','#16a34a',x=RL_M)
ext(None,24,'9','DB9 patilla 5 (+5 V)','#16a34a',x=RL_P)
# legend
y=Y0
a(f'<text x="{LEGX}" y="{y}" font-size="16" font-weight="bold" fill="#111">Hilos que salen de la placa</text>'); y+=26
for num,lab,col in marks:
    a(f'<circle cx="{LEGX+10}" cy="{y-5}" r="9" fill="{col}"/><text x="{LEGX+10}" y="{y-1}" font-size="11" font-weight="bold" fill="#fff" text-anchor="middle">{num}</text>')
    a(f'<text x="{LEGX+28}" y="{y}" font-size="14" fill="#111">{lab}</text>'); y+=24
y+=12
a(f'<text x="{LEGX}" y="{y}" font-size="16" font-weight="bold" fill="#111">Leyenda</text>'); y+=24
for t in ('Curvas rojas/azules: puentes de hilo a + / −.',
          'Pasan por encima, no tocan nada más.',
          'Punto blanco del chip = patilla 1, hacia arriba.',
          'Muesca del zócalo hacia arriba (fila 3 y 15).',
          'H11L1 en zócalo de 8: ocupa filas 15–17,',
          'la fila 18 del zócalo queda vacía.',
          'D1: la franja negra hacia la fila 15.',
          'C1 entre los raíles + y − de la derecha (fila 6).',
          'Raíles: sigue las marcas + / − impresas en la placa.',
          'Filas 1 y 2: unen los raíles izquierdo y derecho.',
          'La malla (patilla 2) del DIN IN no se conecta.'):
    a(f'<text x="{LEGX}" y="{y}" font-size="13" fill="#333">{t}</text>'); y+=20
a('</svg>')
open('hardware/joystick-midi/montaje-perma-proto.svg','w').write("\n".join(o))
