; M2 call-duration probe. Measures 32 WRITE calls aligned to raster lines.
; Emits F2 <mode> <max line crossings>: mode 0=16 accepted, 1=FIFO full.

        opt zxnext
        include "../../include/mt32_api.inc"

UART_TX        equ $133b
UART_SELECT    equ $153b
NEXTREG_SELECT equ $243b
NEXTREG_DATA   equ $253b
NXR_RASTER_MSB equ $1e
NXR_RASTER_LSB equ $1f
ITERATIONS     equ 32

        org $2000

start:
        ld hl,test_buffer
        ld de,$4000
        ld bc,16
        ldir
        call detect_environment
        ld a,$ff
        ld (write_mode),a
        xor a
        ld (max_lines),a
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_ACQUIRE
        rst $08
        db NEXTZXOS_M_DRVAPI
        jp c,failed

        call wait_line_64
        ld a,ITERATIONS
        ld (iterations_left),a
.measure:
        call wait_next_line
        ld (line_before),hl
        ld a,1
        ld (failure_code),a
        ld hl,$4000
        ld de,16
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_WRITE
        rst $08
        db NEXTZXOS_M_DRVAPI
        jp c,failed_release
        ld a,2
        ld (failure_code),a
        call classify_result
        jp c,failed_release
        ld a,3
        ld (failure_code),a
        call read_raster_line
        ld (line_after),hl
        ld de,(line_before)
        or a
        sbc hl,de
        jp nc,.delta_ready
        ld de,(total_lines)
        add hl,de
.delta_ready:
        ld a,h
        or a
        jp nz,failed_release    ; more than 255 lines is never a bounded call
        ld a,(max_lines)
        cp l
        jp nc,.next
        ld a,l
        ld (max_lines),a
.next:
        ld a,(iterations_left)
        dec a
        ld (iterations_left),a
        jp nz,.measure

        ld a,4
        ld (failure_code),a
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_RELEASE
        rst $08
        db NEXTZXOS_M_DRVAPI
        jp c,failed
        call emit_result
        ld a,4
        out ($fe),a
        or a
        ret

detect_environment:
        ld bc,NEXTREG_SELECT
        ld a,$05
        out (c),a
        inc b
        in a,(c)
        and $04
        ld hl,312
        jp z,.store
        ld hl,262
.store:
        ld (total_lines),hl
        dec b
        ld a,$07
        out (c),a
        inc b
        in a,(c)
        and $30
        rrca
        rrca
        rrca
        rrca
        ld (cpu_speed),a
        ret

; Normal bridge accepts all 16 bytes; pressure mode accepts zero. Enforce one
; stable path for all iterations and validate the returned suffix pointers.
classify_result:
        ld a,b
        or a
        jp nz,.bad
        ld a,c
        cp 16
        jp z,.accepted
        or a
        jp nz,.bad
        ld a,d
        or a
        jp nz,.bad
        ld a,e
        cp 16
        jp nz,.bad
        ld a,1
        jp .mode
.accepted:
        ld a,d
        or e
        jp nz,.bad
        xor a
.mode:
        ld d,a
        ld a,(write_mode)
        cp $ff
        jp nz,.compare
        ld a,d
        ld (write_mode),a
        or a
        ret
.compare:
        cp d
        jp nz,.bad
        or a
        ret
.bad:
        scf
        ret

wait_line_64:
.loop:
        call read_raster_line
        ld a,h
        or a
        jp nz,.loop
        ld a,l
        cp 64
        jp nz,.loop
        ret

wait_next_line:
        call read_raster_line
        ld (line_wait),hl
.loop:
        call read_raster_line
        ld de,(line_wait)
        or a
        sbc hl,de
        add hl,de
        jp z,.loop
        ret

read_raster_line:
.retry:
        ld bc,NEXTREG_SELECT
        ld a,NXR_RASTER_MSB
        out (c),a
        inc b
        in a,(c)
        and $01
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
        and $01
        cp d
        jp nz,.retry
        ld h,d
        ld l,e
        ret

; Test-only result marker sent after RELEASE while restoring UART selection.
emit_result:
        ld bc,UART_SELECT
        in a,(c)
        ld (saved_uart_select),a
        ld a,$40
        out (c),a
        ld bc,UART_TX
        ld a,$f2
        out (c),a
        ld a,(write_mode)
        out (c),a
        ld a,(max_lines)
        and $7f
        out (c),a
        ld a,$f3
        out (c),a
        ld a,(cpu_speed)
        out (c),a
        ld bc,UART_SELECT
        ld a,(saved_uart_select)
        or $10
        out (c),a
        ret

failed_release:
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_RELEASE
        rst $08
        db NEXTZXOS_M_DRVAPI
failed:
        call emit_failure
        ld a,2
        out ($fe),a
        scf
        ret

emit_failure:
        ld bc,UART_SELECT
        in a,(c)
        ld d,a
        ld a,$40
        out (c),a
        ld bc,UART_TX
        ld a,$f2
        out (c),a
        ld a,(failure_code)
        and $7f
        out (c),a
        ld a,(iterations_left)
        and $7f
        out (c),a
        ld a,$f0
        out (c),a
        ld a,$7d
        out (c),a
        ld hl,(line_before)
        ld a,l
        and $7f
        out (c),a
        ld a,l
        add a,a
        ld a,h
        rla
        and $03
        out (c),a
        ld hl,(line_after)
        ld a,l
        and $7f
        out (c),a
        ld a,l
        add a,a
        ld a,h
        rla
        and $03
        out (c),a
        ld a,$f7
        out (c),a
        ld bc,UART_SELECT
        ld a,d
        or $10
        out (c),a
        ret

iterations_left:  db 0
write_mode:       db 0
max_lines:        db 0
failure_code:     db 0
saved_uart_select: db 0
line_before:      dw 0
line_after:       dw 0
line_wait:        dw 0
total_lines:      dw 0
cpu_speed:        db 0
test_buffer:      ds 16,$fe
