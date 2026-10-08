' Harness test of the ZX Basic binding (src/lib/gseq.bas). The harness
' preloads the library bank (page 40) and the .GSQ file (pages 41 on), gives
' the driver its buffer in IX as NextZXOS does for programs, checks that the
' ROM is in MMU0/1 during driver calls, and exposes a millisecond counter on
' ports $0B0B (low) and $0C0B (high). Parameters at 23296: bank count, pause,
' resume and send times (ms), library slot NextReg, window NextReg, the
' offset of the sequence in its first bank and the cleanup channel mask. Not part of any product.
#include "../../src/lib/gseq.bas"

dim tx as uinteger
dim st,i,n,paused,sent as ubyte
dim t,pauseAt,resumeAt,sendAt,offset,channels as uinteger
dim libSlot,windowReg as ubyte
dim effect(0 to 2) as ubyte

function Clock() as uinteger
    asm
        ld bc,$0c0b
        in h,(c)
        ld bc,$0b0b
        in l,(c)
    end asm
end function

sub fastcall PutChar(c as ubyte)
    asm
        push ix
        rst $10
        pop ix
    end asm
end sub

sub OutNum(v as ubyte)
    PutChar(48+v/100): PutChar(48+(v/10) mod 10): PutChar(48+v mod 10)
end sub

sub Report(tag as ubyte,v as ubyte)
    PutChar(tag): PutChar(61): OutNum(v): PutChar(32)
end sub

function fastcall Driver(fn as ubyte) as ubyte
    asm
        push ix
        ld b,a
        ld c,$2d
        ld hl,0
        ld de,0
        rst $08
        db $92
        pop ix
        ld a,0
        jr c,driver_failed
        inc a
    driver_failed:
    end asm
end function

n=peek(23296)                          ' bank count left here by the harness
pauseAt=peek(23297)+cast(uinteger,peek(23298))*256
resumeAt=peek(23299)+cast(uinteger,peek(23300))*256
sendAt=peek(23301)+cast(uinteger,peek(23302))*256
effect(0)=$99: effect(1)=$2a: effect(2)=$40
libSlot=peek(23303): windowReg=peek(23304)
offset=peek(23305)+cast(uinteger,peek(23306))*256
channels=peek(23307)+cast(uinteger,peek(23308))*256

GsSetLibrary(40,libSlot)
st=GsInit(windowReg,1,channels): Report(73,st): Report(69,gsError)
gsBankTable(0)=n
for i=1 to n
    gsBankTable(i)=40+i
next i
st=GsOpen(offset): Report(79,st): Report(69,gsError)
if st=GS_FAILED then PutChar(13): END
Report(65,Driver(1))
st=GsStart(Clock()): Report(83,st)
paused=0: sent=0
do
    t=Clock()
    if paused=0 and pauseAt<>0 and t>=pauseAt then st=GsPause(t): paused=1: Report(80,st)
    if paused=1 and t>=resumeAt then st=GsResume(t): paused=2: Report(82,st)
    if sent=0 and sendAt<>0 and t>=sendAt then st=GsSend(@effect(0),3): sent=1: Report(68,st)
    st=GsPump(t,4)
    if st=GS_FAILED then exit do
loop until st=GS_ENDED or st=GS_ERROR
Report(81,st): Report(69,gsError)
st=GsStop()
do
    st=GsPump(Clock(),4)
    st=GsQuery()
loop while gsBusy<>0 and st<>GS_FAILED
Report(87,gsInfo(1))
Report(84,gsInfo(9))
Report(76,gsInfo(3))
Report(82,Driver(5))
PutChar(13)
