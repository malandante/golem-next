; .GSQ <file>: plays a GSEQ file through the M6 phase 1 library (src/lib/gseq.s).
;
; Second client of the library (#62) and a tool for hardware tests. Loads the
; file into 8K banks, acquires GOLEM.DRV and calls gs_pump in a loop with a
; millisecond clock taken from the raster counter, like .MT32 play. P pauses
; and resumes; SPACE stops. Runs at 28 MHz and restores the caller's speed,
; MMU 3-7, the NextReg selector and the banks on every exit.

        opt zxnext
        include "../../include/mt32_api.inc"

M_GETSETDRV     equ $89
F_OPEN          equ $9a
F_CLOSE         equ $9b
F_READ          equ $9d
M_P3DOS         equ $94
IDE_BANK        equ $01bd

NEXTREG_SELECT  equ $243b
NXR_TURBO       equ $07
NXR_MMU3        equ $53
NXR_MMU4        equ $54
NXR_MMU7        equ $57
NXR_RASTER_MSB  equ $1e
NXR_RASTER_LSB  equ $1f
LOCAL_STACK     equ $7ff0
OUT_BUFFER      equ $6000           ; in the private work bank, visible to the driver
KEY_TABLE       equ $6100           ; 2048 bytes, same bank
LOAD_WINDOW     equ $8000           ; MMU4 while loading
MAX_BANKS       equ 128

        org $2000

start:
        ld (saved_sp),sp
        xor a
        ld (work_bank),a
        ld (bank_count),a
        ld (acquired),a
        ld (failed),a
        ld (file_open),a
        call parse_name             ; before MMU3 changes: args may be there
        jp nc,usage

        ld bc,NEXTREG_SELECT
        in a,(c)
        ld (saved_select),a
        ld a,NXR_TURBO
        out (c),a
        inc b
        in a,(c)
        and 3
        ld (saved_speed),a
        ld hl,saved_mmu             ; MMU3..MMU7
        ld d,NXR_MMU3
        ld e,5
.save:
        dec b
        out (c),d
        inc b
        in a,(c)
        ld (hl),a
        inc hl
        inc d
        dec e
        jr nz,.save

        call allocate_bank          ; caller's stack, as .MT32 does
        jp nc,no_memory
        ld (work_bank),a
        ld bc,NEXTREG_SELECT
        ld a,NXR_MMU3
        out (c),a
        inc b
        ld a,(work_bank)
        out (c),a
        ld sp,LOCAL_STACK
        ld a,1
        ld (work_mapped),a
        ld a,3                      ; 28 MHz
        ld d,NXR_TURBO
        call set_nextreg

        ld hl,msg_loading
        call print_z
        call load_file
        jp c,load_failed

        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_QUERY
        rst $08
        db NEXTZXOS_M_DRVAPI
        jp c,no_driver
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_ACQUIRE
        rst $08
        db NEXTZXOS_M_DRVAPI
        jp c,no_driver
        ld a,1
        ld (acquired),a

        ld hl,OUT_BUFFER
        ld a,NXR_MMU7
        ld de,KEY_TABLE
        call gs_init
        ld hl,bank_count
        ld de,0                     ; the file starts its first bank
        call gs_open
        jp c,library_failed
        call clock_init
        call clock_now
        call gs_start
        jp c,library_failed
        ld hl,msg_playing
        call print_z

; Main loop: pump, read the keys, until the sequence ends or is stopped and
; everything has left.
play_loop:
        call clock_now
        ld b,1                      ; the loop calls again at once
        call gs_pump
        jp c,library_failed
        cp GS_ENDED
        jp z,ended
        cp GS_ERROR
        jp z,library_error
        cp GS_STOPPED
        jp z,stopping
        call read_keys
        jp play_loop

ended:
        call gs_stop                ; clean the channels anyway
stopping:
        call clock_now
        ld b,1                      ; the loop calls again at once
        call gs_pump
        call gs_query
        jp nz,stopping              ; until the cleanup has left
        jp finish

library_error:
        ld hl,msg_record_error
        ld a,1
        ld (failed),a
        jp stopping_with_message

library_failed:
        ld hl,msg_library_error
        ld a,1
        ld (failed),a
stopping_with_message:
        ld (fail_message),hl
        call gs_stop
.drain:
        call clock_now
        ld b,1                      ; the loop calls again at once
        call gs_pump
        jp c,finish                 ; driver error: nothing more to do
        call gs_query
        jp nz,.drain
        jp finish

; P toggles pause on the key press edge; SPACE stops.
read_keys:
        ld bc,$7ffe
        in a,(c)
        bit 0,a
        jp nz,.no_space
        call gs_stop
        ld hl,msg_cancelled
        ld (end_message),hl
        ret
.no_space:
        ld bc,$dffe
        in a,(c)
        cpl
        and 1                       ; 1 = P down
        ld hl,p_down
        ld b,(hl)
        ld (hl),a
        cp b
        ret z                       ; no change
        or a
        ret z                       ; released
        call clock_now
        call gs_query
        cp GS_PAUSED
        jp z,.resume
        call clock_now
        jp gs_pause
.resume:
        call clock_now
        jp gs_resume

; ---------------------------------------------------------------- exits

finish:
        ld a,(acquired)
        or a
        jr z,.released
.drain:
        ld c,MT32_DRIVER_ID         ; let the FIFO empty, up to ~1 s
        ld b,MT32_FN_DRAIN_STATUS
        rst $08
        db NEXTZXOS_M_DRVAPI
        jr c,.release
        ld a,b
        and c
        inc a
        jr z,.release
        ld hl,(drain_count)
        dec hl
        ld (drain_count),hl
        ld a,h
        or l
        jr nz,.drain
.release:
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_RELEASE
        rst $08
        db NEXTZXOS_M_DRVAPI
        xor a
        ld (acquired),a
.released:
        call close_file
        ld hl,saved_mmu+1           ; MMU4-7 on the private stack
        ld d,NXR_MMU4
        ld e,4
.restore:
        ld a,(hl)
        call set_nextreg
        inc hl
        inc d
        dec e
        jr nz,.restore
        ld sp,(saved_sp)
        ld a,(work_mapped)
        or a
        jr z,.unmapped
        ld bc,NEXTREG_SELECT
        ld a,NXR_MMU3
        out (c),a
        inc b
        ld a,(saved_mmu)
        out (c),a
        xor a
        ld (work_mapped),a
.unmapped:
        call free_all
        ld a,(saved_speed)
        ld d,NXR_TURBO
        call set_nextreg
        ld bc,NEXTREG_SELECT
        ld a,(saved_select)
        out (c),a
        ld a,(failed)
        or a
        jr nz,.report
        ld hl,(end_message)
        call print_z
        or a
        ret
.report:
        ld hl,(fail_message)
        xor a                       ; custom error report, last char bit 7
        scf
        ret

usage:
        ld hl,err_usage
        xor a
        scf
        ret

no_memory:
        ld hl,err_memory
        jr fail
load_failed:
        ld hl,err_load
        jr fail
no_driver:
        ld hl,err_driver
fail:
        ld (fail_message),hl
        ld a,1
        ld (failed),a
        jp finish

; ---------------------------------------------------------------- clock

; Lines per frame decide the line length: 311 or 264 lines are 128K/+3 timing
; (228 T per line at 3.5 MHz), anything else 48K timing (224 T). ms per line
; in 16.16 fixed point: 228/3500 -> 4269, 224/3500 -> 4194.
clock_init:
        call measure_lines
        ld de,4194
        ld bc,311
        or a
        sbc hl,bc
        jr z,.long_lines
        add hl,bc
        ld bc,264
        or a
        sbc hl,bc
        jr nz,.ready
.long_lines:
        ld de,4269
.ready:
        ld (line_ms),de
        call read_raster
        ld (raster_prev),hl
        ld hl,0
        ld (clock_q16),hl
        ld (clock_q16+2),hl
        ret

; DE = now in ms (low 16 bits of the 16.16 clock's integer part).
clock_now:
        call read_raster
        ld de,(raster_prev)
        ld (raster_prev),hl
        or a
        sbc hl,de
        jr nc,.delta
        ld de,(frame_lines)
        add hl,de
.delta:                             ; HL = lines since last call (< 1 frame)
        ld de,(line_ms)
        call mul16                  ; DEHL = HL x DE
        ld bc,(clock_q16)
        add hl,bc
        ld (clock_q16),hl
        ld hl,(clock_q16+2)
        adc hl,de
        ld (clock_q16+2),hl
        ex de,hl
        ret

; DEHL = HL x DE (unsigned 16 x 16).
mul16:
        ld b,h
        ld c,l
        ld hl,0
        ld a,16
.bit:
        add hl,hl
        rl e
        rl d
        jr nc,.no_add
        add hl,bc
        jr nc,.no_add
        inc de
.no_add:
        dec a
        jr nz,.bit
        ret

; HL = lines per frame, measured over three frames at 28 MHz with DI.
measure_lines:
        ld a,i
        push af
        di
        call read_raster
        ld (raster_prev),hl
        ld hl,0
        ld (frame_lines),hl
        ld a,3
        ld (wraps),a
.sample:
        call read_raster
        ld de,(frame_lines)
        push hl
        or a
        sbc hl,de
        pop hl
        jr c,.not_max
        ld (frame_lines),hl
.not_max:
        ld de,(raster_prev)
        ld (raster_prev),hl
        or a
        sbc hl,de
        jr nc,.sample
        ld a,(wraps)
        dec a
        ld (wraps),a
        jr nz,.sample
        pop af
        jp po,.done
        ei
.done:
        ld hl,(frame_lines)
        inc hl
        ld (frame_lines),hl
        ret

; HL = current raster line, read consistently across an LSB rollover.
read_raster:
        ld bc,NEXTREG_SELECT
        ld a,NXR_RASTER_MSB
        out (c),a
        inc b
        in a,(c)
        and 1
        ld d,a
        dec b
        ld a,NXR_RASTER_LSB
        out (c),a
        inc b
        in e,(c)
        dec b
        ld a,NXR_RASTER_MSB
        out (c),a
        inc b
        in a,(c)
        and 1
        cp d
        jr nz,read_raster
        ex de,hl
        ret

; ---------------------------------------------------------------- loading

; Reads the whole file into banks allocated one at a time, through MMU4.
; Carry on failure. bank_count and banks hold what was allocated.
load_file:
        xor a
        rst $08
        db M_GETSETDRV
        ld hl,filename
        ld b,1
        rst $08
        db F_OPEN
        ret c
        ld (file_handle),a
        ld a,1
        ld (file_open),a
.bank:
        ld a,(bank_count)
        cp MAX_BANKS
        ccf
        ret c
        call allocate_bank
        ccf
        ret c
        ld e,a
        ld a,(bank_count)
        ld c,a
        ld b,0
        ld hl,banks
        add hl,bc
        ld (hl),e
        inc a
        ld (bank_count),a
        ld a,e
        ld d,NXR_MMU4
        call set_nextreg
        ld a,(file_handle)
        ld hl,LOAD_WINDOW
        ld bc,$2000
        rst $08
        db F_READ
        ret c
        ld a,b
        cp $20
        jr nz,.eof
        ld a,(saved_mmu+1)          ; print with the caller's MMU4, not a file bank:
        ld d,NXR_MMU4               ; the ROM print code may touch $8000-$9FFF
        call set_nextreg
        ld a,'.'
        rst $10
        jr .bank
.eof:
        ld a,b
        or c
        jr nz,.close
        ld a,(bank_count)           ; the last bank stayed empty: free it
        dec a
        ld (bank_count),a
        ld c,a
        ld b,0
        ld hl,banks
        add hl,bc
        ld a,(hl)
        call free_bank
.close:
        ld a,(saved_mmu+1)
        ld d,NXR_MMU4
        call set_nextreg
        call close_file
        ld a,(bank_count)
        or a
        scf
        ret z
        ccf
        ret

close_file:
        ld a,(file_open)
        or a
        ret z
        ld a,(file_handle)
        rst $08
        db F_CLOSE
        xor a
        ld (file_open),a
        ret

free_all:
        ld a,(bank_count)
        or a
        jr z,.work
        ld b,a
        ld hl,banks
.one:
        push bc
        push hl
        ld a,(hl)
        call free_bank
        pop hl
        pop bc
        inc hl
        djnz .one
        xor a
        ld (bank_count),a
.work:
        ld a,(work_bank)
        or a
        ret z
        call free_bank
        xor a
        ld (work_bank),a
        ret

; Out: carry set and A=bank on success.
allocate_bank:
        ld hl,$0001
        exx
        ld de,IDE_BANK
        ld c,7
        rst $08
        db M_P3DOS
        ld a,e
        ret

free_bank:
        ld e,a
        ld hl,$0003
        exx
        ld de,IDE_BANK
        ld c,7
        rst $08
        db M_P3DOS
        ret

; D=NextReg, A=value. Preserves HL, DE.
set_nextreg:
        ld bc,NEXTREG_SELECT
        out (c),d
        inc b
        out (c),a
        ret

; HL=command tail. Copies the first word (optionally quoted) to filename.
parse_name:
        ld a,h
        or l
        ret z
.skip:
        ld a,(hl)
        cp ' '
        jr nz,.start
        inc hl
        jr .skip
.start:
        cp '"'
        jr nz,.copy_start
        inc hl
.copy_start:
        ld de,filename
        ld b,0
.copy:
        ld a,(hl)
        or a
        jr z,.end_name
        cp 13
        jr z,.end_name
        cp ':'
        jr nz,.not_colon
        ld a,b                      ; "c:/..." is part of the name
        cp 1
        ld a,(hl)
        jr nz,.end_name
.not_colon:
        cp ' '
        jr z,.end_name
        cp '"'
        jr z,.end_name
        ld (de),a
        inc hl
        inc de
        inc b
        ld a,b
        cp 250
        jr c,.copy
.end_name:
        xor a
        ld (de),a
        ld a,b
        or a
        ret z
        scf
        ret

print_z:
        ld a,(hl)
        inc hl
        or a
        ret z
        push hl
        rst $10
        pop hl
        jr print_z

        include "../lib/gseq.s"

msg_loading:       db 13,"GSQ: loading",0
msg_playing:       db 13,"GSQ: playing (P pause, SPACE stop)",13,0
msg_done:          db "GSQ: finished",13,0
msg_cancelled:     db "GSQ: stopped",13,0
err_usage:         db "Usage: .GSQ <file",'>'+$80
err_memory:        db "GSQ: out of memory bank",'s'+$80
err_load:          db "GSQ: cannot read fil",'e'+$80
err_driver:        db "GSQ: GOLEM.DRV missing or in us",'e'+$80
msg_library_error: db "GSQ: invalid GSEQ fil",'e'+$80
msg_record_error:  db "GSQ: invalid GSEQ recor",'d'+$80

saved_sp:       dw 0
saved_select:   db 0
saved_speed:    db 0
saved_mmu:      ds 5
work_bank:      db 0
work_mapped:    db 0
acquired:       db 0
failed:         db 0
fail_message:   dw 0
end_message:    dw msg_done
drain_count:    dw 20000
file_open:      db 0
file_handle:    db 0
p_down:         db 0
line_ms:        dw 4194
frame_lines:    dw 312
raster_prev:    dw 0
wraps:          db 0
clock_q16:      ds 4
bank_count:     db 0                ; bank table read by gs_open: count, banks
banks:          ds MAX_BANKS
filename:       ds 256
