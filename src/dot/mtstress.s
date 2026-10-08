; M2 pressure client. Requires the CSpect bridge pressure mode documented in
; tests/integration/cspect/README.md and proves partial plus zero-progress writes.

        opt zxnext
        include "../../include/mt32_api.inc"

        org $2000

start:
        xor a
        ld (acquired),a
        ld (saw_partial),a
        ld (saw_zero),a

        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_QUERY
        rst $08
        db NEXTZXOS_M_DRVAPI
        jp c,failed
        ld a,b
        cp $4d
        jp nz,failed
        ld a,c
        cp $54
        jp nz,failed

        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_ACQUIRE
        rst $08
        db NEXTZXOS_M_DRVAPI
        jp c,failed
        ld a,1
        ld (acquired),a

        ld hl,payload
        ld de,$4000
        ld bc,payload_end-payload
        ldir
        ld hl,$4000
        ld de,payload_end-payload
        ld ix,250
.write:
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_WRITE
        rst $08
        db NEXTZXOS_M_DRVAPI
        jp c,failed_release
        ld a,b
        or a
        jp nz,failed_release    ; accepted count must fit in low byte
        ld a,c
        cp MT32_MAX_WRITE+1
        jp nc,failed_release
        ld a,b
        or c
        jp nz,.progress
        ld a,1
        ld (saw_zero),a
        ei
        halt
        dec ix
        ld a,ixh
        or ixl
        jp z,failed_release
        jp .write
.progress:
        ld a,d
        or e
        jp z,.written
        ld a,1
        ld (saw_partial),a
        jp .write

.written:
        ld a,(saw_partial)
        or a
        jp z,failed_release
        ld a,(saw_zero)
        or a
        jp z,failed_release

        ld ix,250
.drain:
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_DRAIN_STATUS
        rst $08
        db NEXTZXOS_M_DRVAPI
        jp c,failed_release
        ld a,b
        and c
        inc a
        jp z,.release
        ei
        halt
        dec ix
        ld a,ixh
        or ixl
        jp nz,.drain
        jp failed_release

.release:
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_RELEASE
        rst $08
        db NEXTZXOS_M_DRVAPI
        jp c,failed
        xor a
        ld (acquired),a
        ld a,4
        out ($fe),a
        or a
        ret

failed_release:
        ld a,(acquired)
        or a
        jp z,failed
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_RELEASE
        rst $08
        db NEXTZXOS_M_DRVAPI
failed:
        ld a,2
        out ($fe),a
        scf
        ret

acquired:      db 0
saw_partial:   db 0
saw_zero:      db 0
payload:
        ds 20,$f8
payload_end:
