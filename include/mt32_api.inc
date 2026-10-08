; golem-next experimental driver ABI v0.2 (see ABI_CHANGELOG.md)
; Numeric values may change until M6. The driver ID must be assigned upstream.

MT32_DRIVER_ID       equ $2d       ; provisional, deliberately non-alphabetic

MT32_FN_QUERY        equ $00
MT32_FN_ACQUIRE      equ $01
MT32_FN_WRITE        equ $02
MT32_FN_STATUS       equ $03
MT32_FN_DRAIN_STATUS equ $04
MT32_FN_RELEASE      equ $05
MT32_FN_READ         equ $06

MT32_ERR_BUSY        equ $01
MT32_ERR_NOT_ACQUIRED equ $02
MT32_ERR_INVALID     equ $03

MT32_SIGNATURE       equ $4d54     ; BC = "MT"
MT32_ABI_VERSION     equ $0002     ; DE = major.minor (0.2)

MT32_CAP_PARTIAL_WRITE equ $0001
MT32_CAP_RX_NONBLOCKING equ $0002
MT32_MAX_WRITE       equ 16
MT32_MAX_READ        equ 16

NEXTZXOS_M_DRVAPI    equ $92
