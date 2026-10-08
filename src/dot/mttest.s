; Separate M2 conformance client for GOLEM.DRV.
; Install build/GOLEM.DRV first, then copy build/MTTEST to /dot and run .mttest.

        opt zxnext
        include "../../include/mt32_api.inc"

        org $2000

start:
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_QUERY
        rst $08
        db NEXTZXOS_M_DRVAPI
        jr c,failed
        ld a,b
        cp $4d
        jr nz,failed
        ld a,c
        cp $54
        jr nz,failed

        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_ACQUIRE
        rst $08
        db NEXTZXOS_M_DRVAPI
        jr c,failed

        ld hl,note_on
        ld de,$4000            ; driver buffers must be in visible main RAM
        ld bc,3
        ldir
        ld hl,$4000
        ld de,3
        call write_all
        jr c,failed_release

        ld ix,250               ; five-second audible hold at 50 Hz
note_delay:
        ei
        halt
        dec ix
        ld a,ixh
        or ixl
        jr nz,note_delay

        ld hl,note_off
        ld de,$4000
        ld bc,3
        ldir
        ld hl,$4000
        ld de,3
        call write_all
        jr c,failed_release

        ld ix,250               ; bounded wait outside the driver
drain_loop:
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_DRAIN_STATUS
        rst $08
        db NEXTZXOS_M_DRVAPI
        jr c,failed_release
        ld a,b
        and c
        inc a                   ; $ffff -> A becomes 0
        jr z,release_ok
        ei
        halt
        dec ix
        ld a,ixh
        or ixl
        jr nz,drain_loop
        jr failed_release

release_ok:
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_RELEASE
        rst $08
        db NEXTZXOS_M_DRVAPI
        jr c,failed
        ld a,4                  ; green border: capture is the main oracle
        out ($fe),a
        or a
        ret

failed_release:
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_RELEASE
        rst $08
        db NEXTZXOS_M_DRVAPI
failed:
        ld a,2                  ; red border
        out ($fe),a
        scf
        ret

; HL=next byte, DE=remaining. Retries zero progress for at most 250 frames.
write_all:
        ld ix,250
write_retry:
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_WRITE
        rst $08
        db NEXTZXOS_M_DRVAPI
        ret c
        ld a,d
        or e
        ret z
        ld a,b
        or c
        jr nz,write_retry
        ei
        halt
        dec ix
        ld a,ixh
        or ixl
        jr nz,write_retry
        scf
        ret

note_on:
        db $91,$3c,$64
note_off:
        db $81,$3c,$00
