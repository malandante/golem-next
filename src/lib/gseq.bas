' GSEQ player for ZX Basic (Boriel), M6 phase 1 (docs/m6-gseq.md). MIT licence.
'
' The library itself is an 8K bank built from src/lib/gseq_bank.s for one slot
' (GSEQ4000.BIN ... GSEQE000.BIN). Load it into a bank, load the .GSQ file into
' banks of its own, and tell this binding where they are:
'
'     LoadSDBank("GSEQC000.BIN",0,0,0,60)    ' NextBuild, or any loader
'     GsSetLibrary(60,$56)                   ' bank 60, mapped in slot 6 ($C000)
'     if GsInit($54,1,0)=GS_FAILED then ...  ' data window in slot 4, key table, all channels
'     gsBankTable(0)=3: gsBankTable(1)=61 ... ' count, then the banks of the file
'     if GsOpen(0)=GS_FAILED then ...         ' 0: the file starts its first bank
'
' Every call maps the library bank in its slot, calls it and puts back what
' the slot held before; the library puts the ROM in MMU0/1 for the call and
' restores them too. So this file may run from paged code in slot 1, and the
' data window may be slot 0 or 1. The stack, the interrupt routine, gsBankTable
' and the message passed to GsSend must not be in MMU0/1, in the library slot
' or in the data window.
'
' The program acquires GOLEM.DRV before GsStart and releases it when GsQuery
' reports idle after GsStop or the end (see mt32-next include/mt32_api.inc).
'
' Results: each function returns the state (GS_*) or 255 on error; the error
' code is then in gsError (GS_ERR_*). "now" is a free-running millisecond
' counter; only differences modulo 65536 are used.

#define GS_STOPPED 0
#define GS_PLAYING 1
#define GS_PAUSED 2
#define GS_ENDED 3
#define GS_ERROR 4
#define GS_FAILED 255

#define GS_ERR_FORMAT 1
#define GS_ERR_VERSION 2
#define GS_ERR_CHECKSUM 3
#define GS_ERR_RECORD 4
#define GS_ERR_DRIVER 5
#define GS_ERR_STATE 6
#define GS_ERR_LIBRARY 7

dim gsLibraryBank as ubyte=0
dim gsLibrarySlot as ubyte=$56
dim gsError as ubyte=0
dim gsBusy as ubyte=0
' Bank table for GsOpen: count, then the banks. A program short of fixed
' memory can #define GS_MAX_BANKS before including this file.
#ifndef GS_MAX_BANKS
#define GS_MAX_BANKS 224
#endif
dim gsBankTable(0 to GS_MAX_BANKS) as ubyte
' Copy of the information block after GsQuery: state, error, notice,
' loops (2 bytes), time in ms (4 bytes), target synth (0 any, 1 MT-32, 2 GM).
dim gsInfo(0 to 9) as ubyte

' Registers for the call and its results.
dim gsEntry as ubyte
dim gsRegA as ubyte
dim gsRegB as ubyte
dim gsRegDE as uinteger
dim gsRegHL as uinteger
dim gsResultA as ubyte
dim gsResultCarry as ubyte
dim gsResultZero as ubyte
dim gsInfoAddress as uinteger

sub GsSetLibrary(bank as ubyte,slotReg as ubyte)
    gsLibraryBank=bank
    gsLibrarySlot=slotReg
end sub

' Map the library, call entry gsEntry with gsRegA/B/DE/HL, restore the slot.
' After a query the 10-byte block is copied to gsInfo while still mapped.
' Entry 255 only copies the 6 signature bytes at slot address + 27.
sub GsCall()
    ' The assembler below reads these variables; reading them here as well
    ' keeps ZX Basic from removing them as unused.
    gsResultA=gsEntry bxor gsRegA bxor gsRegB bxor cast(ubyte,gsRegDE) bxor cast(ubyte,gsRegHL)
    gsInfoAddress=@gsInfo(0)
    gsResultA=cast(ubyte,gsInfoAddress)
    asm
        PROC
        LOCAL call_ix,back,no_carry,not_zero,copy_done,signature
        push ix
        ld bc,$243b
        in a,(c)
        push af                         ; NextReg selector
        ld a,(_gsLibrarySlot)
        out (c),a
        inc b
        in a,(c)
        push af                         ; bank that was in the slot
        ld a,(_gsLibraryBank)
        out (c),a
        ld a,(_gsLibrarySlot)           ; slot address = (reg - $50) x $2000
        sub $50
        rrca
        rrca
        rrca
        and $e0
        ld h,a
        ld a,(_gsEntry)
        cp 255
        jr z,signature
        ld l,a
        add a,a
        add a,l                         ; entry x 3
        ld l,a
        push hl
        pop ix                          ; IX = entry address
        ld a,(_gsRegB)
        ld b,a
        ld de,(_gsRegDE)
        ld hl,(_gsRegHL)
        ld a,(_gsRegA)
        call call_ix
        jr back
    call_ix:
        jp (ix)
    signature:
        ld l,27
        ld de,(_gsInfoAddress)
        ld bc,6
        ldir
        jr copy_done
    back:
        push af
        ld a,0
        jr nc,no_carry
        inc a
    no_carry:
        ld (_gsResultCarry),a
        pop af
        push af
        ld a,0
        jr nz,not_zero
        inc a
    not_zero:
        ld (_gsResultZero),a
        pop af
        ld (_gsResultA),a
        ld a,(_gsEntry)
        cp 8
        jr nz,copy_done
        ld de,(_gsInfoAddress)
        ld bc,10
        ldir
    copy_done:
        ld bc,$243b
        ld a,(_gsLibrarySlot)
        out (c),a
        inc b
        pop af
        out (c),a                       ; bank back in the slot
        dec b
        pop af
        out (c),a                       ; selector
        pop ix
        ENDP
    end asm
end sub

function GsResult() as ubyte
    if gsResultCarry<>0 then
        gsError=gsResultA
        return GS_FAILED
    end if
    gsError=0
    return gsResultA
end function

function GsRun(entry as ubyte) as ubyte
    if gsLibraryBank=0 or gsLibrarySlot<$52 or gsLibrarySlot>$57 then
        gsError=GS_ERR_LIBRARY
        return GS_FAILED
    end if
    gsEntry=entry
    GsCall()
    return GsResult()
end function

' Check the signature at slot address + 27 ("GSEQ", major 1), then init.
' windowReg: MMU NextReg of the data window ($50-$57, not the library slot).
' keys=0 skips the key table (no re-strike on resume).
' channels: the MIDI channels the start, pause, resume and stop cleanups may
' touch (bit n = channel n+1); 0 means all 16. Leave out the channels a
' program keeps for its own sound effects.
function GsInit(windowReg as ubyte,keys as ubyte,channels as uinteger) as ubyte
    if gsLibraryBank=0 or gsLibrarySlot<$52 or gsLibrarySlot>$57 or windowReg<$50 or windowReg>$57 or windowReg=gsLibrarySlot then
        gsError=GS_ERR_LIBRARY
        return GS_FAILED
    end if
    gsEntry=255
    GsCall()
    if gsInfo(0)<>71 or gsInfo(1)<>83 or gsInfo(2)<>69 or gsInfo(3)<>81 or gsInfo(4)<>1 then
        gsError=GS_ERR_LIBRARY
        return GS_FAILED
    end if
    gsRegA=windowReg
    gsRegB=keys
    gsRegHL=channels
    return GsRun(0)
end function

' offset: where the sequence starts in the first bank (0-8191), so that
' several short sequences, or a sequence and other data, can share banks.
function GsOpen(offset as uinteger) as ubyte
    gsRegHL=@gsBankTable(0)
    gsRegDE=offset
    return GsRun(1)
end function

function GsStart(now as uinteger) as ubyte
    gsRegDE=now
    return GsRun(2)
end function

' budget: WRITEs of up to 16 bytes this call may make (0 counts as 1).
' Once per frame, 1 gives 800 bytes/s and 4 covers the cable.
function GsPump(now as uinteger,budget as ubyte) as ubyte
    gsRegDE=now
    gsRegB=budget
    return GsRun(3)
end function

function GsPause(now as uinteger) as ubyte
    gsRegDE=now
    return GsRun(4)
end function

function GsResume(now as uinteger) as ubyte
    gsRegDE=now
    return GsRun(5)
end function

function GsStop() as ubyte
    return GsRun(6)
end function

' A direct message (an effect) of 1 to 16 bytes at address, sent before the
' music in the next pump. It must not lie in the library slot.
function GsSend(address as uinteger,length as ubyte) as ubyte
    gsRegHL=address
    gsRegB=length
    return GsRun(7)
end function

' State, with gsInfo filled in and gsBusy=1 while bytes or a cleanup are
' still pending.
function GsQuery() as ubyte
    dim state as ubyte
    state=GsRun(8)
    gsBusy=1-gsResultZero
    return state
end function
