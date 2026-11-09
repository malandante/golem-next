' Golem sound parameters for ZX Basic (Boriel): the gp_* library
' (docs/sound-params.md 10), MIT licence.
'
' The library is an 8K bank built from src/lib/gparam_bank.s for one slot
' (GPAR4000.BIN ... GPARE000.BIN). Load it into a bank and tell this binding
' where it is:
'
'     LoadSDBank("GPARC000.BIN",0,0,0,62)    ' NextBuild, or any loader
'     GpSetLibrary(62,$56)                   ' bank 62, mapped in slot 6 ($C000)
'     if GpInit()=GP_FAILED then ...         ' after ACQUIRE of GOLEM.DRV
'
' Then start one operation at a time and call GpUpdate(4) once per frame
' until it is no longer GP_BUSY:
'
'     GpRequest(GP_AREA_OPL3_INSTR,$26,@level,1,GP_FLAG_CONFIRM)
'     if GpWrite()=GP_FAILED then ...
'     do: st=GpUpdate(4): loop while st=GP_BUSY  ' with a frame wait inside
'     st=GpResult()                          ' gpError, gpDetail, gpCount
'
' Every call maps the library bank in its slot, calls it and puts back what
' the slot held; the library puts the ROM in MMU0/1 for the call and restores
' them too. What an operation reads or fills (gpReq, gpFile, the data, the
' destination, the bank table) is used during the later GpUpdate calls as
' well: keep it out of MMU0/1, the library slot and the file's MMU slot until
' the operation ends. So must the stack. The library writes and reads with
' GOLEM.DRV itself: it is not for use while GSEQ plays (use the assembler
' library with gp_set_sender and gs_send_long for that).
'
' Results: each function returns the state (GP_*); GP_FAILED (3) with the
' error in gpError: below $20 the Golem's, from $20 the library's, $30 this
' binding's (library bank missing or wrong).

#define GP_IDLE 0
#define GP_BUSY 1
#define GP_DONE 2
#define GP_FAILED 3

#define GP_ERR_TIMEOUT $20
#define GP_ERR_DRIVER $21
#define GP_ERR_SIZE $22
#define GP_ERR_BUSY $23
#define GP_ERR_REPLY $24
#define GP_ERR_VALUE $25
#define GP_ERR_LIBRARY $30

#define GP_AREA_MT32 $00
#define GP_AREA_OPL3_INSTR $01
#define GP_AREA_OPL3_BANKS $02
#define GP_AREA_MT32_ROM $04
#define GP_AREA_SETTINGS $10
#define GP_FILE_WOPL $01
#define GP_FILE_FX $03
#define GP_FILE_MT32 $04
#define GP_FLAG_CONFIRM 1

dim gpLibraryBank as ubyte
dim gpLibrarySlot as ubyte
dim gpEntry as ubyte
dim gpRegA as ubyte
dim gpRegB as ubyte
dim gpRegDE as uinteger
dim gpRegHL as uinteger
dim gpResultA as ubyte
dim gpResultB as ubyte
dim gpResultC as ubyte
dim gpResultDE as uinteger
dim gpResultHL as uinteger
dim gpResultCarry as ubyte
dim gpError as ubyte
dim gpDetail as uinteger
dim gpCount as ulong
dim gpSignature(0 to 5) as ubyte
dim gpSignatureAddress as uinteger
' Request block (gp_write, gp_read): area, address (3 bytes), data or
' destination, length, flags. File block (gp_blob_*): type, slot, size or room
' (3 bytes), bank table, offset in its first bank, MMU slot.
dim gpReq(0 to 8) as ubyte
dim gpFile(0 to 9) as ubyte

sub GpSetLibrary(bank as ubyte,slotReg as ubyte)
    gpLibraryBank=bank
    gpLibrarySlot=slotReg
end sub

' Map the library, call entry gpEntry with gpRegA/B/DE/HL, keep A, B, C, DE,
' HL and carry, restore the slot. Entry 255 copies the 6 signature bytes at
' slot address + 27 to gpSignature.
sub GpCall()
    ' The assembler below reads these variables; reading them here as well
    ' keeps ZX Basic from removing them as unused.
    gpResultA=gpEntry bxor gpRegA bxor gpRegB bxor cast(ubyte,gpRegDE) bxor cast(ubyte,gpRegHL)
    gpSignatureAddress=@gpSignature(0)
    gpResultA=cast(ubyte,gpSignatureAddress)
    asm
        PROC
        LOCAL call_ix,back,no_carry,signature,done
        push ix
        ld bc,$243b
        in a,(c)
        push af                         ; NextReg selector
        ld a,(_gpLibrarySlot)
        out (c),a
        inc b
        in a,(c)
        push af                         ; bank that was in the slot
        ld a,(_gpLibraryBank)
        out (c),a
        ld a,(_gpLibrarySlot)           ; slot address = (reg - $50) x $2000
        sub $50
        rrca
        rrca
        rrca
        and $e0
        ld h,a
        ld a,(_gpEntry)
        cp 255
        jr z,signature
        ld l,a
        add a,a
        add a,l                         ; entry x 3
        ld l,a
        push hl
        pop ix                          ; IX = entry address
        ld a,(_gpRegB)
        ld b,a
        ld de,(_gpRegDE)
        ld hl,(_gpRegHL)
        ld a,(_gpRegA)
        call call_ix
        jr back
    call_ix:
        jp (ix)
    signature:
        ld l,27
        ld de,(_gpSignatureAddress)
        ld bc,6
        ldir
        jr done
    back:
        ld (_gpResultHL),hl
        ld (_gpResultDE),de
        ld (_gpResultA),a
        ld a,b
        ld (_gpResultB),a
        ld a,c
        ld (_gpResultC),a
        ld a,0
        jr nc,no_carry
        inc a
    no_carry:
        ld (_gpResultCarry),a
    done:
        ld bc,$243b
        ld a,(_gpLibrarySlot)
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

function GpRun(entry as ubyte) as ubyte
    if gpLibraryBank=0 or gpLibrarySlot<$52 or gpLibrarySlot>$57 then
        gpError=GP_ERR_LIBRARY
        return GP_FAILED
    end if
    gpEntry=entry
    GpCall()
    if gpResultCarry<>0 then
        gpError=gpResultA
        return GP_FAILED
    end if
    gpError=0
    return gpResultA
end function

' Checks the signature ("GPAR", major 1), then gp_init: the library writes and
' reads with GOLEM.DRV, nothing in progress.
function GpInit() as ubyte
    if gpLibraryBank=0 or gpLibrarySlot<$52 or gpLibrarySlot>$57 then
        gpError=GP_ERR_LIBRARY
        return GP_FAILED
    end if
    gpEntry=255
    GpCall()
    if gpSignature(0)<>71 or gpSignature(1)<>80 or gpSignature(2)<>65 or gpSignature(3)<>82 or gpSignature(4)<>1 then
        gpError=GP_ERR_LIBRARY
        return GP_FAILED
    end if
    return GpRun(0)
end function

' Fills gpReq: area, address (21 bits), buffer (the data or the destination),
' length (1-256), flags (GP_FLAG_CONFIRM: a write waits for the Golem's READY).
sub GpRequest(area as ubyte,address as ulong,buffer as uinteger,length as uinteger,flags as ubyte)
    gpReq(0)=area
    gpReq(1)=cast(ubyte,address)
    gpReq(2)=cast(ubyte,address>>8)
    gpReq(3)=cast(ubyte,address>>16)
    gpReq(4)=cast(ubyte,buffer)
    gpReq(5)=cast(ubyte,buffer>>8)
    gpReq(6)=cast(ubyte,length)
    gpReq(7)=cast(ubyte,length>>8)
    gpReq(8)=flags
end sub

' Fills gpFile: type (GP_FILE_WOPL), slot (0: the working one), size (put) or
' room (get), bank table (count, then the banks), offset in the first bank,
' MMU NextReg the banks are paged through ($50-$57, not the library slot).
sub GpFileBlock(kind as ubyte,slot as ubyte,size as ulong,banks as uinteger,offset as uinteger,mmu as ubyte)
    gpFile(0)=kind
    gpFile(1)=slot
    gpFile(2)=cast(ubyte,size)
    gpFile(3)=cast(ubyte,size>>8)
    gpFile(4)=cast(ubyte,size>>16)
    gpFile(5)=cast(ubyte,banks)
    gpFile(6)=cast(ubyte,banks>>8)
    gpFile(7)=cast(ubyte,offset)
    gpFile(8)=cast(ubyte,offset>>8)
    gpFile(9)=mmu
end sub

' GET_INFO: page 0 (numbers) or 1 (name) into size bytes at address
function GpInfo(page as ubyte,address as uinteger,size as ubyte) as ubyte
    gpRegA=page
    gpRegHL=address
    gpRegB=size
    return GpRun(1)
end function

function GpWrite() as ubyte
    gpRegHL=@gpReq(0)
    return GpRun(2)
end function

function GpRead() as ubyte
    gpRegHL=@gpReq(0)
    return GpRun(3)
end function

function GpBlobPut() as ubyte
    gpRegHL=@gpFile(0)
    return GpRun(4)
end function

function GpBlobGet() as ubyte
    gpRegHL=@gpFile(0)
    return GpRun(5)
end function

' Once per frame: sends, receives, counts the time out. budget: WRITEs of up
' to 16 bytes (4 covers the cable). On GP_FAILED, gpError and gpDetail.
function GpUpdate(budget as ubyte) as ubyte
    dim st as ubyte
    gpRegB=budget
    st=GpRun(6)
    if st=GP_FAILED then GpResult()
    return st
end function

' State; gpError, gpDetail (position of a refused byte, $3FFF if none) and
' gpCount (bytes done; a file's size for GpBlobGet).
function GpResult() as ubyte
    dim st as ubyte
    st=GpRun(7)
    gpError=gpResultB
    gpDetail=gpResultDE
    gpCount=(cast(ulong,gpResultC)<<16) bor gpResultHL
    return st
end function
