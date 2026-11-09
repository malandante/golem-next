' Harness test of the ZX Basic binding (src/lib/gparam.bas), run by
' tools/ci/test_gparam_bas.py: the harness preloads the library bank (40,
' GPARC000.BIN, mapped in slot 6) and models GOLEM.DRV and a Golem. File
' banks 50-51 go through slot 4. Not part of any product.
#include "../../src/lib/gparam.bas"

dim st,i as ubyte
dim buf(0 to 47) as ubyte
dim vals(0 to 1) as ubyte
dim table(0 to 2) as ubyte

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

function Wait() as ubyte
    dim s as ubyte
    do
        s=GpUpdate(4)
    loop while s=GP_BUSY
    s=GpResult()
    return s
end function

GpSetLibrary(40,$56)
st=GpInit(): Report(73,st): Report(69,gpError)

' I: the name, page 1
st=GpInfo(1,@buf(0),40)
st=Wait(): Report(78,st)
for i=0 to cast(ubyte,gpCount)-1
    PutChar(buf(i))
next i
PutChar(32)

' W: write two settings, confirmed; R: read them back
vals(0)=1: vals(1)=0
GpRequest(GP_AREA_SETTINGS,3,@vals(0),2,GP_FLAG_CONFIRM)
st=GpWrite(): st=Wait(): Report(87,st)
buf(0)=99: buf(1)=99
GpRequest(GP_AREA_SETTINGS,3,@buf(0),2,0)
st=GpRead(): st=Wait(): Report(82,st): Report(97,buf(0)): Report(98,buf(1))

' X: a refused value, its error and position
vals(0)=1: vals(1)=101
GpRequest(GP_AREA_SETTINGS,5,@vals(0),2,GP_FLAG_CONFIRM)
st=GpWrite(): st=Wait(): Report(88,st): Report(69,gpError): Report(80,cast(ubyte,gpDetail))

' G: the bank into banks 50-51, P: back out of them
table(0)=2: table(1)=50: table(2)=51
GpFileBlock(GP_FILE_WOPL,0,16384,@table(0),0,$54)
st=GpBlobGet(): st=Wait(): Report(71,st): Report(76,cast(ubyte,gpCount)): Report(72,cast(ubyte,gpCount>>8))
GpFileBlock(GP_FILE_WOPL,0,gpCount,@table(0),0,$54)
st=GpBlobPut(): st=Wait(): Report(85,st): Report(69,gpError)
PutChar(13)
