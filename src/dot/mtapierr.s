; M2 API error-path client. Emits F6 only after every expected result passes.

        opt zxnext
        include "../../include/mt32_api.inc"

        org $2000

start:
        xor a
        ld (acquired),a

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

        call acquire
        jp c,failed

        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_ACQUIRE
        rst $08
        db NEXTZXOS_M_DRVAPI
        jp nc,failed_release
        cp MT32_ERR_BUSY
        jp nz,failed_release

        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_STATUS
        rst $08
        db NEXTZXOS_M_DRVAPI
        jp c,failed_release
        bit 0,c
        jp z,failed_release

        call release
        jp c,failed

        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_STATUS
        rst $08
        db NEXTZXOS_M_DRVAPI
        jp c,failed
        bit 0,c
        jp nz,failed

        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_RELEASE
        rst $08
        db NEXTZXOS_M_DRVAPI
        call expect_not_acquired
        jp c,failed

        ld hl,$4000
        ld de,1
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_WRITE
        rst $08
        db NEXTZXOS_M_DRVAPI
        call expect_not_acquired
        jp c,failed

        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_DRAIN_STATUS
        rst $08
        db NEXTZXOS_M_DRVAPI
        call expect_not_acquired
        jp c,failed

        ld hl,$4000
        ld de,1
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_READ
        rst $08
        db NEXTZXOS_M_DRVAPI
        call expect_not_acquired
        jp c,failed

        call acquire
        jp c,failed

        ld hl,$3fff
        ld de,1
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_WRITE
        rst $08
        db NEXTZXOS_M_DRVAPI
        jp nc,failed_release
        cp MT32_ERR_INVALID
        jp nz,failed_release

        ld hl,$3fff
        ld de,1
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_READ
        rst $08
        db NEXTZXOS_M_DRVAPI
        jp nc,failed_release
        cp MT32_ERR_INVALID
        jp nz,failed_release

        ld a,$f6
        ld ($4000),a
        ld hl,$4000
        ld de,1
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_WRITE
        rst $08
        db NEXTZXOS_M_DRVAPI
        jp c,failed_release
        ld a,d
        or e
        jp nz,failed_release

        call release
        jp c,failed
        ld a,4
        out ($fe),a
        or a
        ret

acquire:
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_ACQUIRE
        rst $08
        db NEXTZXOS_M_DRVAPI
        ret c
        ld a,1
        ld (acquired),a
        or a
        ret

release:
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_RELEASE
        rst $08
        db NEXTZXOS_M_DRVAPI
        ret c
        xor a
        ld (acquired),a
        ret

; Carry is set on entry from the driver. Return carry clear only for error 2.
expect_not_acquired:
        jp nc,.bad
        cp MT32_ERR_NOT_ACQUIRED
        jp nz,.bad
        or a
        ret
.bad:
        scf
        ret

failed_release:
        ld a,(acquired)
        or a
        jp z,failed
        call release
failed:
        ld a,2
        out ($fe),a
        scf
        ret

acquired: db 0
