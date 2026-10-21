' MIDI monitor for the ZX Spectrum Next (ZX Basic / NextBuild). MIT licence.
' Shows every MIDI message that reaches GOLEM.DRV, in hexadecimal:
' - from a USB keyboard on the Golem, after ".golem set keys on";
' - from a DIN keyboard on a joystick port's MIDI IN adapter, after
'   ".golem output left" (or right).
' The Golem's own replies are not shown. SPACE ends.
#include "../lib/midiin.bas"

dim sysex(0 to 63) as ubyte
dim k,i as ubyte

sub fastcall PutChar(c as ubyte)
    asm
        push ix
        rst $10
        pop ix
    end asm
end sub

sub PutHex(v as ubyte)
    dim h as ubyte
    h=v>>4: if h<10 then PutChar(48+h) else PutChar(55+h)
    h=v band 15: if h<10 then PutChar(48+h) else PutChar(55+h)
    PutChar(32)
end sub

function fastcall DriverCall(fn as ubyte) as ubyte
    ' 1 on success, 0 on error
    asm
        push ix
        ld b,a
        ld c,$2d                ; GOLEM.DRV
        ld hl,0
        ld de,0
        rst $08
        db $92                  ; M_DRVAPI
        pop ix
        ld a,0
        jr c,driver_failed
        inc a
    driver_failed:
    end asm
end function

function SpacePressed() as ubyte
    return (in($7ffe) band 1)=0
end function

print "MIDI monitor - SPACE ends"
MiInit(@sysex(0),64)
if DriverCall(1)=0 then print "GOLEM.DRV missing or in use": stop
do
    k=MiGet()
    if k=MI_SHORT then
        PutHex(miStatus)
        if miLength>1 then PutHex(miData1)
        if miLength>2 then PutHex(miData2)
        PutChar(13)
    elseif k=MI_SYSEX then
        for i=0 to miLength-1
            PutHex(sysex(i))
        next i
        if miCut then print "...";
        PutChar(13)
    elseif k=MI_FAILED then
        print "driver error ";miError
        exit do
    end if
loop until SpacePressed()
DriverCall(5)                   ' RELEASE
