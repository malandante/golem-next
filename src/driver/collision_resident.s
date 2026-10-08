; Test-only resident claiming MT32_DRIVER_ID with signature "XX".

        opt zxnext
        include "../../include/mt32_api.inc"

        org $0000

api_entry:
        ld a,b
        or a
        jr nz,unsupported
        ld bc,$5858
        ld de,$0001
        ld hl,0
        or a
        ret
unsupported:
        xor a
        scf
        ret

code_end:
        ds 512-code_end
