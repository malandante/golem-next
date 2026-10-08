; M2 preservation probe. Emits F3 01 only when CPU and readable hardware state
; survive ACQUIRE/STATUS/RELEASE exactly as documented.

        opt zxnext
        include "../../include/mt32_api.inc"

UART_TX        equ $133b
UART_SELECT    equ $153b
UART_FRAME     equ $163b
NEXTREG_SELECT equ $243b
NEXTREG_DATA   equ $253b

        org $2000

start:
        ld a,$01
        ld (failure_code),a
        call save_hardware_state
        call acquire
        jp c,failed
        ld a,$02
        ld (failure_code),a
        call check_cpu_preservation
        jp c,failed_release
        ld a,$06
        ld (failure_code),a
        call check_i2s_enabled
        jp c,failed_release
        ld a,$03
        ld (failure_code),a
        call release
        jp c,failed
        ld a,$04
        ld (failure_code),a
        call check_hardware_state
        jp c,failed

        ; Emit a valid two-byte Song Select marker through the public API.
        ld a,$05
        ld (failure_code),a
        call acquire
        jp c,failed
        ld hl,success_marker
        ld de,$4000
        ld bc,2
        ldir
        ld hl,$4000
        ld de,2
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_WRITE
        rst $08
        db NEXTZXOS_M_DRVAPI
        jp c,failed_release
        ld a,b
        or a
        jp nz,failed_release
        ld a,c
        cp 2
        jp nz,failed_release
        ld a,d
        or e
        jp nz,failed_release
        call release
        jp c,failed
        ld a,4
        out ($fe),a
        or a
        ret

save_hardware_state:
        ld bc,UART_SELECT
        in a,(c)
        ld (saved_uart_select),a
        ld bc,UART_FRAME
        in a,(c)
        ld (saved_uart_frame),a

        ld bc,NEXTREG_SELECT
        ld a,$a0
        out (c),a
        inc b
        in a,(c)
        ld (saved_a0),a
        dec b
        ld a,$a2
        out (c),a
        inc b
        in a,(c)
        ld (saved_a2),a
        dec b
        ld hl,saved_mmus
        ld d,$54
        ld e,4
.mmu_loop:
        ld a,d
        out (c),a
        inc b
        in a,(c)
        dec b
        ld (hl),a
        inc hl
        inc d
        dec e
        jp nz,.mmu_loop
        ld a,$42                ; observable selector restored by RELEASE
        out (c),a
        ret

check_cpu_preservation:
        push ix
        push iy
        exx
        push bc
        push de
        push hl
        exx
        ex af,af'
        push af
        ex af,af'

        ld ix,$1234
        ld iy,$5678
        exx
        ld bc,$9abc
        ld de,$def0
        ld hl,$1357
        exx
        ld a,$a5
        ex af,af'

        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_STATUS
        rst $08
        db NEXTZXOS_M_DRVAPI
        jp c,.bad

        push ix
        pop hl
        ld de,$1234
        or a
        sbc hl,de
        jp nz,.bad
        push iy
        pop hl
        ld de,$5678
        or a
        sbc hl,de
        jp nz,.bad

        exx
        ld a,b
        cp $9a
        jp nz,.bad_exx
        ld a,c
        cp $bc
        jp nz,.bad_exx
        ld a,d
        cp $de
        jp nz,.bad_exx
        ld a,e
        cp $f0
        jp nz,.bad_exx
        ld a,h
        cp $13
        jp nz,.bad_exx
        ld a,l
        cp $57
        jp nz,.bad_exx
        exx

        ex af,af'
        cp $a5
        jp nz,.bad_af
        ex af,af'
        ex af,af'
        pop af
        ex af,af'
        exx
        pop hl
        pop de
        pop bc
        exx
        pop iy
        pop ix
        or a
        ret
.bad_af:
        ex af,af'
        jp .restore_bad
.bad_exx:
        exx
        jp .restore_bad
.bad:
.restore_bad:
        ex af,af'
        pop af
        ex af,af'
        exx
        pop hl
        pop de
        pop bc
        exx
        pop iy
        pop ix
        scf
        ret

; While acquired, NextReg $A2 must receive I2S from the Pi (#6).
check_i2s_enabled:
        ld bc,NEXTREG_SELECT
        in a,(c)
        ld e,a
        ld a,$a2
        out (c),a
        inc b
        in a,(c)
        dec b
        ld d,a
        ld a,e
        out (c),a
        ld a,d
        cp $d2
        jr nz,.bad
        or a
        ret
.bad:
        scf
        ret

check_hardware_state:
        ld bc,NEXTREG_SELECT
        in a,(c)
        cp $42
        jp nz,.bad

        ld a,$a0
        out (c),a
        inc b
        in a,(c)
        ld d,a
        ld a,(saved_a0)
        cp d
        jp nz,.bad
        dec b
        ld a,$a2
        out (c),a
        inc b
        in a,(c)
        ld d,a
        ld a,(saved_a2)
        cp d
        jp nz,.bad
        dec b

        ld hl,saved_mmus
        ld d,$54
        ld e,4
.mmu_loop:
        ld a,d
        out (c),a
        inc b
        in a,(c)
        dec b
        cp (hl)
        jp nz,.bad
        inc hl
        inc d
        dec e
        jp nz,.mmu_loop

        ld bc,UART_SELECT
        in a,(c)
        ld d,a
        ld a,(saved_uart_select)
        cp d
        jp nz,.bad
        ld bc,UART_FRAME
        in a,(c)
        ld d,a
        ld a,(saved_uart_frame)
        cp d
        jp nz,.bad
        or a
        ret
.bad:
        scf
        ret

acquire:
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_ACQUIRE
        rst $08
        db NEXTZXOS_M_DRVAPI
        ret

release:
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_RELEASE
        rst $08
        db NEXTZXOS_M_DRVAPI
        ret

failed_release:
        call release
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
        ld a,$7f
        out (c),a
        ld a,(failure_code)
        out (c),a
        ld bc,UART_SELECT
        ld a,d
        or $10
        out (c),a
        ret

saved_uart_select: db 0
saved_uart_frame:  db 0
saved_a0:          db 0
saved_a2:          db 0
saved_mmus:        ds 4
failure_code:      db 0
success_marker:    db $f3,$01
