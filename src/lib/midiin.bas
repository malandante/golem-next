' MIDI input for ZX Basic (Boriel): whole MIDI messages through GOLEM.DRV.
' MIT licence. The work is done by midiin.s (include it with mt32_api.inc next
' to this file); see the comments there for the details.
'
'     #include "midiin.bas"
'     dim sysex(0 to 63) as ubyte
'     MiInit(@sysex(0),64)            ' SysEx buffer and its size (0: none)
'     ' ... ACQUIRE GOLEM.DRV ...
'     do
'         k=MiGet()
'         if k=MI_SHORT then
'             ' miStatus, miData1, miData2; miLength = 1, 2 or 3
'         elseif k=MI_SYSEX then
'             ' sysex(0 to miLength-1), F0 to F7; miCut=1 if it did not fit
'         elseif k=MI_FAILED then
'             ' driver error in miError (not acquired, for example)
'         end if
'     loop
'
' Call MiGet once per frame or more often: each call reads at most 16 bytes
' and returns one message. The Golem's own replies never reach the program.
' The program must be above $4000 (ZX Basic's default 32768 is fine), where
' miRx is, because GOLEM.DRV only writes there.

#define MI_NONE 0
#define MI_SHORT 1
#define MI_SYSEX 2
#define MI_FAILED 255

dim miRx(0 to 15) as ubyte
dim miStatus as ubyte
dim miData1 as ubyte
dim miData2 as ubyte
dim miLength as ubyte
dim miCut as ubyte
dim miError as ubyte
dim miRxAddress as uinteger
dim miSysExAddress as uinteger
dim miSysExSize as ubyte

sub MiInit(sysexAddress as uinteger,sysexSize as ubyte)
    miRxAddress=@miRx(0)
    miSysExAddress=sysexAddress
    miSysExSize=sysexSize
    ' The assembler below reads these; reading them here as well keeps ZX
    ' Basic from removing them as unused.
    miError=cast(ubyte,miRxAddress) bxor cast(ubyte,miSysExAddress) bxor miSysExSize
    asm
        ld hl,(_miRxAddress)
        ld de,(_miSysExAddress)
        ld a,(_miSysExSize)
        ld b,a
        call mi_init
    end asm
end sub

function MiGet() as ubyte
    miError=miLength bxor miCut bxor miStatus bxor miData1 bxor miData2
    asm
        PROC
        LOCAL failed,done
        push ix
        call mi_get
        pop ix
        jr c,failed
        push af
        ld a,b
        ld (_miLength),a
        ld a,c
        ld (_miCut),a
        ld hl,mi_message
        ld de,_miStatus
        ldi
        ld de,_miData1
        ldi
        ld de,_miData2
        ldi
        pop af
        jr done
    failed:
        ld (_miError),a
        ld a,255
    done:
        ENDP
    end asm
end function

asm
        jp mi_library_end
#include once "mt32_api.inc"
#include once "midiin.s"
mi_library_end:
end asm
