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
GOLEM_CMD_SET_USB_OUT    equ $04       ; firmware golem-1.1.0 and later
GOLEM_CMD_SET_PARAM      equ $05       ; idem; payload parameter, value
GOLEM_CMD_SAVE           equ $06       ; idem; payload GOLEM_SAVE_*

; SAVE payload: the Pi keeps its settings in golem.cfg on its SD card, read
; after mt32-pi.cfg at start-up.
GOLEM_SAVE_WRITE         equ $00       ; write the current settings
GOLEM_SAVE_CLEAR         equ $01       ; delete golem.cfg

; SET_USB_OUT payload: where MIDI from the Next also goes (#85)
GOLEM_USB_OUT_OFF        equ $00       ; only the Golem synth
GOLEM_USB_OUT_ON         equ $01       ; Golem synth and USB MIDI devices
GOLEM_USB_OUT_BRIDGE     equ $02       ; USB MIDI devices only; synth silent
GOLEM_USB_OUT_QUERY      equ $7f       ; change nothing, report the mode

; SET_PARAM parameters; READY carries the parameter and its value. They last
; until the Pi is switched off and survive an MT-32 reset (.golem play).
GOLEM_PARAM_VOLUME       equ $00       ; 0-100, both engines (HAT encoder)
GOLEM_PARAM_FX           equ $01       ; 0/1, FluidSynth reverb and chorus
GOLEM_PARAM_CHANNELS     equ $02       ; 0 standard 2-10, 1 alternate 1-8,10
GOLEM_PARAM_THRU         equ $03       ; 0/1, USB keyboard also to USB out
GOLEM_PARAM_KEYS         equ $04       ; 0/1, USB keyboard also to the Next
GOLEM_PARAM_BANK         equ $05       ; 0-127, OPL3 instrument bank
GOLEM_PARAM_LOUD         equ $06       ; 0/1, synth louder through a limiter
GOLEM_PARAM_QUERY        equ $7f       ; value: change nothing, report

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
GOLEM_SYNTH_OPL3         equ $02

GOLEM_SOUNDFONT_MAX      equ 127       ; CLI v1 limit; wire format is 14-bit
GOLEM_REQUEST_BASE       equ 8         ; through command, before payload/F7
GOLEM_RX_FRAME_MAX       equ 20
