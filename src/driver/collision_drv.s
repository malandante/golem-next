; Test-only NextZXOS driver container that deliberately claims ID $2D.

        opt zxnext
        include "../../include/mt32_api.inc"

        org $0000
        db "NDRV"
        db MT32_DRIVER_ID
        db 0
        db 0
        db 0
        incbin "../../build/collision_resident.bin"
