; golem-next .GOLEM module: Bank ownership and file preload.
; Included by src/dot/golem_cli.s; not assembled on its own. Uses the
; constants and labels defined there and in the other modules.
;
; The whole file is read into as many 8K banks as it needs (up to
; MAX_FILE_BANKS), allocated one at a time; reader.s maps them at MMU7.

save_mmus:
        ld bc,NEXTREG_SELECT
        in a,(c)
        ld (saved_nextreg_selector),a
        ld hl,saved_mmu
        ld d,NXR_MMU4
        ld e,4
.loop:
        ld a,d
        out (c),a
        inc b
        in a,(c)
        dec b
        ld (hl),a
        inc hl
        inc d
        dec e
        jp nz,.loop
        ld a,1
        ld (mmus_saved),a
        ret

allocate_bank:
        ld hl,$0001             ; ZX bank, allocate
        exx
        ld de,IDE_BANK
        ld c,7                  ; +3DOS RAM page
        rst $08
        db M_P3DOS
        ld a,e
        ret                     ; IDE_BANK uses carry set for success

; Out: carry clear on success; on failure carry set and A=LOAD_* reason.
; An open file is closed later by the common exit path (file_open); banks
; already allocated are freed there too (allocated_count).
; `play` runs at 28 MHz (turbo_on), so the load does too: reading from the
; SD is CPU-bound (#14: 158 KB took ~5 s at 3.5 MHz).
; Each bank is read at $8000 (MMU4), not at $E000: MTLOAD on the Next read
; KQ5 (631 KB) in 66 frames there and in 100 at $E000-$FFFF (#57). MMU4 gets
; the caller's bank back when the load ends.
load_file:
        call load_file_body
        push af
        ld a,(saved_mmu)
        ld d,NXR_MMU4
        call map_bank
        pop af
        ret

load_file_body:
        xor a
        rst $08
        db M_GETSETDRV
        ld hl,filename
        ld b,1                  ; read-only
        rst $08
        db F_OPEN
        jp c,.open_failed
        ld (file_handle),a
        ld a,1
        ld (file_open),a
        xor a
        ld (file_length),a
        ld (file_length+1),a
        ld (file_length+2),a
        ld (load_index),a

.read_bank:
        ld a,(load_index)
        cp MAX_FILE_BANKS
        jp nc,.too_big
        call allocate_bank
        jp nc,.no_memory
        ld e,a                  ; record the bank before anything can fail
        ld a,(load_index)
        ld c,a
        ld b,0
        ld hl,file_banks
        add hl,bc
        ld (hl),e
        inc a
        ld (allocated_count),a
        ld a,e
        ld d,NXR_MMU4
        call map_bank

        ld a,(file_handle)
        ld hl,LOAD_WINDOW
        ld bc,$2000
        rst $08
        db F_READ
        jp c,.failed
        ld hl,(file_length)
        add hl,bc
        ld (file_length),hl
        ld a,(file_length+2)
        adc a,0
        ld (file_length+2),a
        ld a,b
        cp $20
        jp nz,.eof
        ld a,c
        or a
        jp nz,.eof
        ld a,(load_index)
        inc a
        ld (load_index),a
        and $03                 ; a dot every 32 KB: a big file takes seconds
        jp nz,.read_bank
        ld a,(saved_mmu)        ; print with the caller's MMU4, not a file bank
        ld d,NXR_MMU4
        call map_bank
        ld a,'.'
        rst $10
        jp .read_bank

.eof:
        ld a,$ff                ; the reader has not mapped anything yet
        ld (rd_mapped),a
        ld a,(file_handle)
        rst $08
        db F_CLOSE
        jp c,.failed
        xor a
        ld (file_open),a
        ld hl,(file_length)
        ld a,h
        or l
        ld hl,file_length+2
        or (hl)
        jp z,.failed            ; empty file
        or a
        ret
.open_failed:
        ld a,LOAD_NOT_OPENED
        scf
        ret
.too_big:
        ld a,LOAD_TOO_BIG
        scf
        ret
.no_memory:
        ld a,LOAD_NO_MEMORY
        scf
        ret
.failed:
        ld a,LOAD_READ_FAILED   ; read error, or an empty file
        scf
        ret

; `play` runs at 28 MHz from the load to the end and the common exit restores
; the caller's speed (turbo_restore, from cleanup). At 3.5 MHz the reader and
; the 16-byte driver calls could not keep the UART busy: a long SysEx intro
; went out at ~2500 bytes/s instead of 3125, and catching up with the time
; spent was slower than real time (#57). The scheduler counts raster lines, so
; its timing does not depend on the CPU speed.
turbo_on:
        ld bc,NEXTREG_SELECT
        ld a,NXR_TURBO
        out (c),a
        inc b
        in a,(c)
        and $03
        ld (caller_speed),a
        ld a,1
        ld (speed_saved),a
        ld a,$03
        out (c),a
        ret

turbo_restore:
        ld a,(speed_saved)
        or a
        ret z
        ld bc,NEXTREG_SELECT
        ld a,NXR_TURBO
        out (c),a
        inc b
        ld a,(caller_speed)
        out (c),a
        xor a
        ld (speed_saved),a
        ret

; D=MMU NextReg, A=8K bank.
map_bank:
        push bc
        push af
        ld bc,NEXTREG_SELECT
        ld a,d
        out (c),a
        inc b
        pop af
        out (c),a
        pop bc
        ret
