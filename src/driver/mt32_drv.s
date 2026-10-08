; NextZXOS .DRV container for the golem-next resident image.

        opt zxnext
        include "../../include/mt32_api.inc"

        org $0000
        db "NDRV"
        db MT32_DRIVER_ID        ; bit 7 clear: no IM1 entry
        db 40                    ; relocation entries in mt32drv.s
        db 0                     ; no extra DivMMC banks
        db 0                     ; no extra Spectrum RAM banks
        incbin "../../build/mt32drv.bin"
