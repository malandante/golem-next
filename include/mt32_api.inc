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
MT32_FN_SET_OUTPUT   equ $07

MT32_ERR_BUSY        equ $01
MT32_ERR_NOT_ACQUIRED equ $02
MT32_ERR_INVALID     equ $03

MT32_SIGNATURE       equ $4d54     ; BC = "MT"
MT32_ABI_VERSION     equ $0003     ; DE = major.minor (0.3)

MT32_CAP_PARTIAL_WRITE equ $0001
MT32_CAP_RX_NONBLOCKING equ $0002
MT32_CAP_OUTPUT_SELECT equ $0004   ; SET_OUTPUT; QUERY H = NextReg $0B used

; SET_OUTPUT (E) and the QUERY H value it produces (NextReg $0B while acquired).
MT32_OUTPUT_GOLEM    equ 0         ; Accelerator header: Golem, UART + I2S
MT32_OUTPUT_LEFT     equ 1         ; left joystick port, pin 7 (external synth)
MT32_OUTPUT_RIGHT    equ 2         ; right joystick port, pin 7
MT32_NR0B_LEFT       equ $a1       ; I/O mode, UART on the left port, Pi UART
MT32_NR0B_RIGHT      equ $b1       ; idem, right port
; STATUS: B is the raw UART status byte (port $133B), ABI 0.3 (#17).
MT32_UART_RX_BREAK   equ $80       ; receive line held low >= 20 bit times
MT32_UART_RX_FRAMING equ $40       ; framing/parity error; clears on read
MT32_UART_RX_AFTER_ERROR equ $20   ; the next RX byte came after an error
MT32_UART_RX_OVERFLOW equ $04      ; RX FIFO overflowed; clears on read
MT32_MAX_WRITE       equ 16
MT32_MAX_READ        equ 16

NEXTZXOS_M_DRVAPI    equ $92
