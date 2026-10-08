; Hardware probe for #7 and #10. Usage: .MTFRAME (GOLEM.DRV installed).
;
; 1. Lines per frame, sampled at 28 MHz over eight frames, and 50/60 Hz.
;    The scheduler assumed 312 (50 Hz) and 262 (60 Hz).
; 2. Where a driver call loses the frame interrupt. For every raster line L
;    and every CPU speed, wait for L, read FRAMES ($5C78, incremented by the
;    ROM IM1 routine), make one call (STATUS, then WRITE of 16 x $F8, a MIDI
;    clock the MT-32 ignores), wait for L in the next frame and read FRAMES
;    again. FRAMES must have advanced by one. Lines where it did not show where
;    the interrupt arrived while the call had interrupts disabled; the width
;    of that range, times 64 us per line, is how long the call blocks them.
; The CPU speed, the screen bytes used as buffer and the driver are restored.

        opt zxnext
        include "../../include/mt32_api.inc"

NEXTREG_SELECT equ $243b
NEXTREG_DATA   equ $253b
NXR_TURBO      equ $07
NXR_PERIPH1    equ $05
NXR_RASTER_MSB equ $1e
NXR_RASTER_LSB equ $1f
FRAMES         equ $5c78
BUFFER         equ $4000          ; visible to the driver; restored afterwards

        org $2000

start:
        ld bc,NEXTREG_SELECT
        ld a,NXR_TURBO
        out (c),a
        inc b
        in a,(c)
        and 3
        ld (saved_speed),a

        ld hl,BUFFER                ; save the screen bytes, fill with $F8
        ld de,saved_screen
        ld bc,16
        ldir
        ld hl,BUFFER
        ld b,16
.fill:
        ld (hl),$f8
        inc hl
        djnz .fill

        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_ACQUIRE
        rst $08
        db NEXTZXOS_M_DRVAPI
        jp c,no_driver

        ; --- lines per frame -------------------------------------------
        ld a,3                      ; 28 MHz: sample every line
        call set_speed
        call max_raster_line
        inc hl                      ; lines = highest line + 1
        ld (frame_lines),hl
        push hl
        ld hl,msg_lines
        call print_z
        pop hl
        call print_u16
        ld bc,NEXTREG_SELECT
        ld a,NXR_PERIPH1
        out (c),a
        inc b
        in a,(c)
        ld hl,msg_50
        and 4
        jr z,.hz
        ld hl,msg_60
.hz:
        call print_z

        ; --- frame period against the UART bit clock -----------------------
        call frame_rate
        ld hl,msg_rate
        call print_z
        ld hl,(rate_bytes)
        call print_u16
        ld hl,msg_rate_mid
        call print_z
        ld hl,(rate_wraps)
        call print_u16
        ld hl,msg_rate_plus
        call print_z
        ld hl,(rate_lines)
        call print_u16
        ld hl,msg_rate_end
        call print_z

        ; --- lines where a call loses the interrupt ---------------------
        ld hl,msg_header
        call print_z
        xor a
.speed_loop:
        ld (speed),a
        call set_speed
        ld a,MT32_FN_STATUS
        call sweep
        ld a,MT32_FN_WRITE
        call sweep
        ld a,(speed)
        inc a
        cp 4
        jr c,.speed_loop

        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_RELEASE
        rst $08
        db NEXTZXOS_M_DRVAPI
        jr finish

no_driver:
        ld hl,msg_no_driver
        call print_z
finish:
        ld bc,NEXTREG_SELECT
        ld a,NXR_TURBO
        out (c),a
        inc b
        ld a,(saved_speed)
        out (c),a
        ld hl,saved_screen
        ld de,BUFFER
        ld bc,16
        ldir
        or a
        ret

; In: A=new NextReg $07 value.
set_speed:
        ld bc,NEXTREG_SELECT
        push af
        ld a,NXR_TURBO
        out (c),a
        inc b
        pop af
        out (c),a
        ret

; In: A=driver function. Prints "<MHz> <name> <lost> <first>-<last>".
sweep:
        ld (function),a
        ld hl,0
        ld (line),hl
        ld (lost),hl
        ld hl,$ffff
        ld (first_lost),hl
        ld hl,0
        ld (last_lost),hl
.position:
        call wait_line              ; frame n, line L
        ld a,(FRAMES)
        ld (frames_start),a
        ld a,(function)
        ld b,a
        ld c,MT32_DRIVER_ID
        ld hl,BUFFER
        ld de,16
        rst $08
        db NEXTZXOS_M_DRVAPI
.leave:
        call read_raster            ; leave line L before waiting for it again
        ld de,(line)
        or a
        sbc hl,de
        jr z,.leave
        call wait_line              ; frame n+1, line L
        ld a,(frames_start)
        ld b,a
        ld a,(FRAMES)
        sub b
        cp 1
        jr z,.next
        ld hl,(lost)
        inc hl
        ld (lost),hl
        ld hl,(line)
        ld (last_lost),hl
        ld de,(first_lost)
        push hl
        or a
        sbc hl,de
        pop hl
        jr nc,.next
        ld (first_lost),hl
.next:
        ld hl,(line)
        inc hl
        ld (line),hl
        ld de,(frame_lines)
        or a
        sbc hl,de
        jr c,.position

        ld a,(speed)
        add a,a
        add a,a
        ld e,a
        ld d,0
        ld hl,speed_names
        add hl,de
        call print_z
        ld hl,name_status
        ld a,(function)
        cp MT32_FN_STATUS
        jr z,.name
        ld hl,name_write
.name:
        call print_z
        ld hl,(lost)
        call print_u16
        ld a,(lost)
        or a
        jr z,.done
        ld a,' '
        rst $10
        ld hl,(first_lost)
        call print_u16
        ld a,'-'
        rst $10
        ld hl,(last_lost)
        call print_u16
.done:
        ld a,13
        rst $10
        ret

; Wait until the raster is exactly on (line).
; Wait for the next frame's first observed line >= (line). The IM1 routine
; hides some lines from polling every frame, so never wait for an exact line:
; first see the frame wrap (or a line below the target), then reach it.
wait_line:
        call read_raster
        ld (previous_line),hl
.before:
        ld de,(line)
        push hl
        or a
        sbc hl,de
        pop hl
        jr c,.reach                 ; already below the target in a new frame
        call read_raster
        ld de,(previous_line)
        ld (previous_line),hl
        push hl
        ex de,hl
        or a
        sbc hl,de                   ; previous - current
        jr c,.no_wrap
        ld de,100
        sbc hl,de
.no_wrap:
        pop hl
        jr c,.before                ; no wrap yet
.reach:
        call read_raster
        ld de,(line)
        or a
        sbc hl,de
        jr c,.reach
        ret

; Send UART_TEST_BYTES of $F8 at 31250 baud (10 bits, 320 us each) and count the
; raster frames and lines that pass until the FIFO is empty again. With the
; baud divisor right, bytes x 320 us is absolute time: frames per second =
; (wraps + lines/frame_lines) / (bytes x 0.00032).
UART_TEST_BYTES equ 15625                ; 5 s
frame_rate:
.drain_first:
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_DRAIN_STATUS
        rst $08
        db NEXTZXOS_M_DRVAPI
        ld a,b
        and c
        inc a
        jr nz,.drain_first          ; until BC=$FFFF
        call read_raster
        ld (rate_start),hl
        ld (previous_line),hl
        ld hl,0
        ld (rate_bytes),hl
        ld (rate_wraps),hl
.send:
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_WRITE
        ld hl,BUFFER
        ld de,16
        rst $08
        db NEXTZXOS_M_DRVAPI
        ld hl,(rate_bytes)
        add hl,bc
        ld (rate_bytes),hl
        call .count_wrap
        ld hl,(rate_bytes)
        ld de,UART_TEST_BYTES
        or a
        sbc hl,de
        jr c,.send
.drain:
        call .count_wrap
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_DRAIN_STATUS
        rst $08
        db NEXTZXOS_M_DRVAPI
        ld a,b
        and c
        inc a
        jr nz,.drain
        call read_raster            ; lines = end - start (+ frame if negative)
        push hl
        call .count_wrap_with_hl
        pop hl
        ld de,(rate_start)
        or a
        sbc hl,de
        jr nc,.lines_ok
        ld de,(frame_lines)
        add hl,de
        ld de,(rate_wraps)
        dec de
        ld (rate_wraps),de
.lines_ok:
        ld (rate_lines),hl
        ret
.count_wrap:
        call read_raster
.count_wrap_with_hl:
        ld de,(previous_line)
        ld (previous_line),hl
        or a
        sbc hl,de
        ret nc                      ; no wrap
        ld hl,(rate_wraps)
        inc hl
        ld (rate_wraps),hl
        ret

; Wait until the raster line goes back to the top of the frame.
wait_wrap:
        call read_raster
        ld (previous_line),hl
.wait:
        call read_raster
        ld de,(previous_line)
        ld (previous_line),hl
        ex de,hl
        or a
        sbc hl,de
        jr c,.wait
        ld de,100
        sbc hl,de
        jr c,.wait
        ret

; Out: HL=highest raster line seen during four frames.
max_raster_line:
        di                          ; the IM1 routine would hide its lines
        call wait_wrap
        ld hl,0
        ld (max_line),hl
        ld a,4
.frame:
        push af
        call read_raster
        ld (previous_line),hl
.sample:
        call read_raster
        ld de,(max_line)
        push hl
        or a
        sbc hl,de
        pop hl
        jr c,.not_max
        ld (max_line),hl
.not_max:
        ld de,(previous_line)
        ld (previous_line),hl
        ex de,hl
        or a
        sbc hl,de
        jr c,.sample
        ld de,100
        sbc hl,de
        jr c,.sample
        pop af
        dec a
        jr nz,.frame
        ld hl,(max_line)
        ei
        ret

; Out: HL=current raster line. Uses A, BC. MSB is read twice so that the
; 255->256 transition between the two reads cannot produce a false 0.
read_raster:
        ld bc,NEXTREG_SELECT
        ld a,NXR_RASTER_MSB
        out (c),a
        inc b
        in a,(c)
        and 1
        ld h,a
        dec b
        ld a,NXR_RASTER_LSB
        out (c),a
        inc b
        in a,(c)
        ld l,a
        dec b
        ld a,NXR_RASTER_MSB
        out (c),a
        inc b
        in a,(c)
        and 1
        cp h
        jr nz,read_raster
        ret

; Print HL as an unsigned decimal number.
print_u16:
        ld b,0                      ; B=1 once a non-zero digit was printed
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

print_z:
        ld a,(hl)
        or a
        ret z
        push hl
        rst $10
        pop hl
        inc hl
        jr print_z

msg_lines:      db "MTFRAME lines/frame ",0
msg_50:         db " (50 Hz)",13,0
msg_60:         db " (60 Hz)",13,0
msg_rate:       db "5 s UART: ",0
msg_rate_mid:   db " bytes = ",0
msg_rate_plus:  db " frames + ",0
msg_rate_end:   db " lines",13,0
msg_header:     db "MHz order lost lines",13,0
msg_no_driver:  db "MTFRAME: GOLEM.DRV missing",13,0
speed_names:    db "3,5",0
                db "7  ",0
                db "14 ",0
                db "28 ",0
name_status:    db " STATUS ",0
name_write:     db " WRITE  ",0

saved_speed:    db 0
speed:          db 0
function:       db 0
frames_start:   db 0
frame_lines:    dw 0
line:           dw 0
lost:           dw 0
first_lost:     dw 0
last_lost:      dw 0
rate_bytes:     dw 0
rate_wraps:     dw 0
rate_lines:     dw 0
rate_start:     dw 0
previous_line:  dw 0
max_line:       dw 0
saved_screen:   ds 16
