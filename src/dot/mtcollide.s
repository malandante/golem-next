; M2 collision probe. Emits direct UART marker F4 only if the dummy owner kept ID.

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
        jp c,failed
        ld a,b
        cp $58                 ; dummy signature "XX"
        jp nz,failed
        ld a,c
        cp $58
        jp nz,failed

        ld a,$f4
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
