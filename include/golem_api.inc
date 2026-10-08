; Experimental bidirectional Golem control protocol for the mt32-pi fork.
;
; Request:  F0 7D 47 4C 4D 01 tt cc [payload] F7
; Response: F0 7D 47 4C 4D 01 tt rr cc [payload] F7
;
; 0x7D is deliberately retained while the protocol is experimental. A
; production manufacturer ID is deferred and does not change this v1 work.

GOLEM_SYSEX_MANUFACTURER equ $7d
GOLEM_SIGNATURE_0        equ $47       ; G
GOLEM_SIGNATURE_1        equ $4c       ; L
GOLEM_SIGNATURE_2        equ $4d       ; M
GOLEM_PROTOCOL_VERSION   equ $01

GOLEM_CMD_GET_STATUS     equ $00
GOLEM_CMD_SET_SYNTH      equ $01
GOLEM_CMD_SET_ROM        equ $02
GOLEM_CMD_SET_SOUNDFONT  equ $03

; Compatibility names used by the current command-line parser.
GOLEM_SYSEX_SWITCH_SYNTH equ GOLEM_CMD_SET_SYNTH
GOLEM_SYSEX_SWITCH_ROM   equ GOLEM_CMD_SET_ROM
GOLEM_SYSEX_SWITCH_SF    equ GOLEM_CMD_SET_SOUNDFONT

GOLEM_RESPONSE_ACCEPTED  equ $40
GOLEM_RESPONSE_READY     equ $41
GOLEM_RESPONSE_ERROR     equ $42
GOLEM_RESPONSE_STATUS    equ $43

GOLEM_ERROR_MALFORMED    equ $01
GOLEM_ERROR_VERSION      equ $02
GOLEM_ERROR_COMMAND      equ $03
GOLEM_ERROR_PARAMETER    equ $04
GOLEM_ERROR_UNAVAILABLE  equ $05
GOLEM_ERROR_OPERATION    equ $06

GOLEM_ROM_MT32_OLD       equ $00
GOLEM_ROM_MT32_NEW       equ $01
GOLEM_ROM_CM32L          equ $02

GOLEM_SYNTH_MT32         equ $00
GOLEM_SYNTH_SOUNDFONT    equ $01

GOLEM_SOUNDFONT_MAX      equ 127       ; CLI v1 limit; wire format is 14-bit
GOLEM_REQUEST_BASE       equ 8         ; through command, before payload/F7
GOLEM_RX_FRAME_MAX       equ 20
