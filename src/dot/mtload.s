; Hardware probe for the load speed of .MT32 play. Usage: .MTLOAD <file>
;
; Reads the whole file several times with different call sizes, destinations
; and CPU speeds, and times each pass with FRAMES ($5C78, 50 or 60 per
; second). Also times allocating and freeing 8K banks with IDE_BANK, which
; play does once per bank. Nothing is sent to the MIDI port and no driver is
; needed. Results are printed at the end, after memory is restored:
;
;   pass  frames  KB
;
; If FRAMES stops while the SD is read (interrupts disabled), the frames
; under-count: compare the total with a stopwatch.
;
; Memory: a private bank at MMU3 holds the local stack (as in .MT32); four
; banks are mapped at MMU4-7 as read buffers. All are freed, and MMU3-7, the
; CPU speed and the NextReg selector restored, before returning.

        opt zxnext

M_GETSETDRV     equ $89
F_OPEN          equ $9a
F_CLOSE         equ $9b
F_READ          equ $9d
M_P3DOS         equ $94
IDE_BANK        equ $01bd

NEXTREG_SELECT  equ $243b
NXR_TURBO       equ $07
NXR_MMU3        equ $53
FRAMES          equ $5c78
LOCAL_STACK     equ $7ff0
PASSES          equ 8
IDE_TEST_BANKS  equ 80

        org $2000

start:
        ld (saved_sp),sp
        xor a
        ld (failed),a
        ld (data_count),a
        ld (work_mapped),a
        call parse_name             ; the command line may lie in $6000-$7fff
        jp nc,usage

        ld bc,NEXTREG_SELECT
        in a,(c)
        ld (saved_selector),a
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

        call allocate_bank          ; on the caller's stack, as .MT32 does
        jp nc,no_memory
        ld (work_bank),a
        ld hl,data_banks
        ld b,4
.data:
        push bc
        push hl
        call allocate_bank
        pop hl
        pop bc
        jp nc,no_memory
        ld (hl),a
        inc hl
        ld a,(data_count)
        inc a
        ld (data_count),a
        djnz .data

        ld bc,NEXTREG_SELECT        ; private stack bank at MMU3, inline
        ld a,NXR_MMU3
        out (c),a
        inc b
        ld a,(work_bank)
        out (c),a
        ld sp,LOCAL_STACK
        ld a,1
        ld (work_mapped),a

        ld hl,data_banks            ; read buffers at MMU4-7
        ld d,NXR_MMU3+1
        ld e,4
.map:
        ld a,(hl)
        call set_nextreg
        inc hl
        inc d
        dec e
        jr nz,.map

        ld ix,pass_table            ; IY is left alone: the ROM interrupt uses it
        ld hl,results
        ld (result_ptr),hl
        ld a,PASSES
.pass:
        push af
        ld a,(ix+0)
        ld d,NXR_TURBO
        call set_nextreg
        ld l,(ix+1)
        ld h,(ix+2)
        ld (pass_dest),hl
        ld l,(ix+3)
        ld h,(ix+4)
        ld (pass_size),hl
        push ix
        call read_pass
        pop ix
        jr c,.read_failed
        ld hl,(result_ptr)
        ld de,(pass_frames)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld de,(pass_kb)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld (result_ptr),hl
        ld de,5
        add ix,de
        pop af
        dec a
        jr nz,.pass

        ld a,3
        ld d,NXR_TURBO
        call set_nextreg
        call bank_pass
        jr finish

.read_failed:
        pop af
        ld a,1
        ld (failed),a

; Restore MMU4-7 while still on the private stack (the caller's stack may be
; there), then the caller's SP, then MMU3 inline, then free the banks.
finish:
        ld hl,saved_mmu+1
        ld d,NXR_MMU3+1
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
        ld a,(saved_selector)
        out (c),a

        ld a,(failed)
        or a
        jr z,report
        ld hl,msg_read_failed
        dec a
        jr z,.message
        ld hl,msg_no_memory
.message:
        call print_z
        or a
        ret

no_memory:
        ld a,2
        ld (failed),a
        jr finish

usage:
        ld hl,msg_usage
        call print_z
        or a
        ret

report:
        ld hl,msg_header
        call print_z
        ld hl,pass_names
        ld (name_ptr),hl
        ld hl,results
        ld (result_ptr),hl
        ld b,PASSES
        ld hl,0
        ld (total_frames),hl
.line:
        push bc
        ld hl,(name_ptr)
        call print_z
        ld (name_ptr),hl
        ld hl,(result_ptr)
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld c,(hl)
        inc hl
        ld b,(hl)
        inc hl
        ld (result_ptr),hl
        ld (line_kb),bc
        ex de,hl
        push hl
        ld de,(total_frames)
        add hl,de
        ld (total_frames),hl
        pop hl
        call print_u16
        ld a,' '
        rst $10
        ld hl,(line_kb)
        call print_u16
        ld a,13
        rst $10
        pop bc
        djnz .line
        ld hl,msg_banks
        call print_z
        ld hl,(bank_frames)
        push hl
        ld de,(total_frames)
        add hl,de
        ld (total_frames),hl
        pop hl
        call print_u16
        ld a,' '
        rst $10
        ld a,(bank_count)
        ld l,a
        ld h,0
        call print_u16
        ld hl,msg_total
        call print_z
        ld hl,(total_frames)
        call print_u16
        ld a,13
        rst $10
        or a
        ret

; One pass over the file: F_READ of pass_size bytes into pass_dest until a
; short read. Out: carry set on error; pass_frames, pass_kb.
read_pass:
        xor a
        rst $08
        db M_GETSETDRV
        ld hl,filename
        ld b,1
        rst $08
        db F_OPEN
        ret c
        ld (handle),a
        xor a
        ld (pass_bytes),a
        ld (pass_bytes+1),a
        ld (pass_bytes+2),a
        ld hl,(FRAMES)
        ld (pass_start),hl
.read:
        ld a,(handle)
        ld hl,(pass_dest)
        ld bc,(pass_size)
        rst $08
        db F_READ
        jr c,.error
        ld hl,(pass_bytes)
        add hl,bc
        ld (pass_bytes),hl
        ld a,(pass_bytes+2)
        adc a,0
        ld (pass_bytes+2),a
        ld hl,(pass_size)
        or a
        sbc hl,bc
        jr z,.read                  ; full read: more to come
        ld hl,(FRAMES)
        ld de,(pass_start)
        or a
        sbc hl,de
        ld (pass_frames),hl
        ld a,(handle)
        rst $08
        db F_CLOSE
        ld hl,(pass_bytes+1)        ; KB = bytes / 1024
        srl h
        rr l
        srl h
        rr l
        ld (pass_kb),hl
        or a
        ret
.error:
        ld a,(handle)
        rst $08
        db F_CLOSE
        scf
        ret

; Allocate up to IDE_TEST_BANKS banks one at a time, then free them.
bank_pass:
        ld hl,(FRAMES)
        ld (pass_start),hl
        xor a
        ld (bank_count),a
.allocate:
        call allocate_bank
        jr nc,.free
        ld e,a
        ld a,(bank_count)
        ld c,a
        ld b,0
        ld hl,test_banks
        add hl,bc
        ld (hl),e
        inc a
        ld (bank_count),a
        cp IDE_TEST_BANKS
        jr c,.allocate
.free:
        ld a,(bank_count)
        or a
        jr z,.timed
        ld b,a
        ld hl,test_banks
.free_one:
        push bc
        push hl
        ld a,(hl)
        call free_bank
        pop hl
        pop bc
        inc hl
        djnz .free_one
.timed:
        ld hl,(FRAMES)
        ld de,(pass_start)
        or a
        sbc hl,de
        ld (bank_frames),hl
        ret

free_all:
        ld a,(data_count)
        or a
        jr z,.work
        ld b,a
        ld hl,data_banks
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
        ld (data_count),a
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

; A=bank to free.
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
; Carry set if a name was found.
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

; Print HL as an unsigned decimal number.
print_u16:
        ld b,0
        ld de,10000
        call .digit
        ld de,1000
        call .digit
        ld de,100
        call .digit
        ld de,10
        call .digit
        ld a,l
        add a,'0'
        rst $10
        ret
.digit:
        ld a,'0'-1
.sub:
        inc a
        or a
        sbc hl,de
        jr nc,.sub
        add hl,de
        cp '0'
        jr nz,.print
        bit 0,b
        ret z
.print:
        ld b,1
        push hl
        push bc
        rst $10
        pop bc
        pop hl
        ret

; Out: HL just past the terminating zero.
print_z:
        ld a,(hl)
        inc hl
        or a
        ret z
        push hl
        rst $10
        pop hl
        jr print_z

; Per pass: speed (NextReg $07), destination, bytes per F_READ.
pass_table:
        db 3
        dw $e000,$2000
        db 3
        dw $8000,$2000
        db 3
        dw $8000,$4000
        db 3
        dw $8000,$8000
        db 3
        dw $8000,$0200
        db 0
        dw $e000,$2000
        db 1
        dw $e000,$2000
        db 3
        dw $e000,$2000
pass_names:
        db "8K  E000 28  ",0
        db "8K  8000 28  ",0
        db "16K 8000 28  ",0
        db "32K 8000 28  ",0
        db "512 8000 28  ",0
        db "8K  E000 3,5 ",0
        db "8K  E000 7   ",0
        db "8K  E000 28  ",0

msg_usage:       db "Usage: .MTLOAD <file>",13,0
msg_header:      db 13,"MTLOAD: pass frames KB",13,0
msg_banks:       db "IDE_BANK x80 ",0
msg_total:       db " banks",13,"Total frames: ",0
msg_no_memory:   db "MTLOAD: out of banks",13,0
msg_read_failed: db "MTLOAD: open or read error",13,0

saved_sp:        dw 0
saved_selector:  db 0
saved_speed:     db 0
saved_mmu:       ds 5
work_bank:       db 0
work_mapped:     db 0
data_banks:      ds 4
data_count:      db 0
failed:          db 0
handle:          db 0
pass_dest:       dw 0
pass_size:       dw 0
pass_start:      dw 0
pass_frames:     dw 0
pass_kb:         dw 0
pass_bytes:      ds 3
bank_frames:     dw 0
bank_count:      db 0
total_frames:    dw 0
result_ptr:      dw 0
name_ptr:        dw 0
line_kb:         dw 0
results:         ds PASSES*4
test_banks:      ds IDE_TEST_BANKS
filename:        ds 256
