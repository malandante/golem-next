; M2 missing-driver probe. Emits direct UART marker F5 only when ID is absent.

        opt zxnext
        include "../../include/mt32_api.inc"

UART_TX     equ $133b
UART_SELECT equ $153b

        org $2000

start:
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_QUERY
        rst $08
        db NEXTZXOS_M_DRVAPI
        jp nc,failed

        ld a,$f5
        call send_marker
        ld a,4
        out ($fe),a
        or a
        ret

failed:
        ld a,2
        out ($fe),a
        scf
        ret

; Test-only direct marker; preserves UART selection and readable top divisor.
send_marker:
        push af
        ld bc,UART_SELECT
        in a,(c)
        ld (saved_select),a
        ld a,$40
        out (c),a
        ld bc,UART_TX
        pop af
        out (c),a
        ld bc,UART_SELECT
        ld a,(saved_select)
        or $10
        out (c),a
        ret

saved_select: db 0
