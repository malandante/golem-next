; golem-next .GOLEM module: Command-line parsing and driver query.
; Included by src/dot/golem_cli.s; not assembled on its own. Uses the
; constants and labels defined there and in the other modules.
;
; Commands: play, note, status, engine (mt32, fluidsynth, opl3), soundfont,
; rom, bank, output, usb, set,
; save and reset.

parse_command:
        ld a,h
        or l
        jp z,.bad
        call skip_spaces
        ld a,(hl)
        or $20
        cp 'p'
        jr z,.play
        cp 'n'
        jp z,.note
        cp 's'
        jp z,.status
        cp 'e'
        jp z,.engine
        cp 'r'
        jp z,.romset
        cp 'o'
        jp z,.output
        cp 'u'
        jp z,.usb
        cp 'b'
        jp z,.bank
        jp .bad

.play:
        inc hl
        ld de,kw_lay
        call match_word
        jp nz,.bad
        ld a,(hl)
        cp ' '
        jp nz,.bad
        call skip_spaces
        ld a,(hl)
        cp '"'
        jr z,.quoted

        ld de,filename
        ld b,0
.plain_loop:
        ld a,(hl)
        or a
        jr z,.plain_done
        cp $0d
        jr z,.plain_done
        cp ':'
        jr z,.plain_done
        cp ' '
        jr z,.plain_end
        ld (de),a
        inc de
        inc hl
        inc b
        jp z,.bad
        jr .plain_loop
.plain_done:
        jr .check_tail
.plain_end:
        call skip_spaces
        jr .check_tail

.quoted:
        inc hl
        ld de,filename
        ld b,0
.quote_loop:
        ld a,(hl)
        or a
        jp z,.bad
        cp $0d
        jp z,.bad
        cp '"'
        jr z,.quote_end
        ld (de),a
        inc de
        inc hl
        inc b
        jp z,.bad
        jr .quote_loop
.quote_end:
        inc hl
        call skip_spaces
.check_tail:
        ld a,b
        or a
        jp z,.bad
        xor a
        ld (de),a
        call at_command_end
        jp nc,.bad
        ld a,CMD_PLAY
        ld (command_mode),a
.good:
        scf
        ret

.note:
        inc hl
        ld de,kw_ote
        call match_word
        jp nz,.bad
        ld a,(hl)
        cp ' '
        jp nz,.bad
        call parse_note_args
        ret

.status:
        inc hl
        ld a,(hl)
        or $20
        cp 'o'
        jr z,.soundfont_after_so
        cp 'e'
        jp z,.set
        cp 'a'
        jp z,.save
        cp 't'
        jp nz,.bad
        inc hl
        ld de,kw_atus
        call match_word
        jp nz,.bad
        call skip_spaces
        call at_command_end
        jp nc,.bad
        ld a,CMD_STATUS
        ld (command_mode),a
        scf
        ret

.soundfont_after_so:
        inc hl
        ld de,kw_undfont
        call match_word
        jp nz,.bad
        ld a,(hl)
        cp ' '
        jp nz,.bad
        call parse_u8
        jp nc,.bad
        cp GOLEM_SOUNDFONT_MAX+1
        jp nc,.bad
        ld (golem_value),a
        ld a,GOLEM_SYSEX_SWITCH_SF
        ld b,CMD_SOUNDFONT
        jp .control_end

.engine:
        inc hl
        ld de,kw_ngine
        call match_word
        jp nz,.bad
        ld a,(hl)
        cp ' '
        jp nz,.bad
        call skip_spaces
        ld a,(hl)
        or $20
        ld c,GOLEM_SYNTH_MT32   ; C survives match_word
        cp 'm'
        jr z,.engine_mt32
        inc c                   ; GOLEM_SYNTH_SOUNDFONT
        ld de,text_fluidsynth
        cp 'f'
        jr z,.engine_match
        inc c                   ; GOLEM_SYNTH_OPL3
        ld de,text_opl3
        cp 'o'
        jr z,.engine_match
        jp .bad
.engine_mt32:
        inc hl
        ld de,kw_t32
.engine_match:
        call match_word
        jp nz,.bad
        ld a,c
        ld (golem_value),a
        ld a,GOLEM_SYSEX_SWITCH_SYNTH
        ld b,CMD_ENGINE
        jp .control_end

.romset:
        inc hl
        ld a,(hl)
        or $20
        cp 'e'
        jp z,.reset
        ld de,kw_om
        call match_word
        jp nz,.bad
        ld a,(hl)
        cp ' '
        jp nz,.bad
        call skip_spaces
        ld a,(hl)
        or $20
        cp 'o'
        jr z,.rom_old
        cp 'n'
        jr z,.rom_new
        cp 'c'
        jr z,.rom_cm32l
        jp .bad
.rom_old:
        xor a
        ld (golem_value),a
        ld de,text_old
        jr .rom_word
.rom_new:
        ld a,GOLEM_ROM_MT32_NEW
        ld (golem_value),a
        ld de,text_new
        jr .rom_word
.rom_cm32l:
        ld a,GOLEM_ROM_CM32L
        ld (golem_value),a
        ld de,text_cm32l
.rom_word:
        call match_word
        jp nz,.bad
        ld a,GOLEM_SYSEX_SWITCH_ROM
        ld b,CMD_ROMSET
        jp .control_end
.output:
        inc hl
        ld de,kw_utput
        call match_word
        jp nz,.bad
        ld a,$ff                ; no word: report only
        ld (output_choice),a
        call at_command_end
        jr c,.output_done
        ld a,(hl)
        cp ' '
        jp nz,.bad
        call skip_spaces
        call at_command_end
        jr c,.output_done
        ld a,(hl)
        or $20
        ld de,text_golem
        ld c,MT32_OUTPUT_GOLEM
        cp 'g'
        jr z,.output_word
        ld de,text_left
        ld c,MT32_OUTPUT_LEFT
        cp 'l'
        jr z,.output_word
        ld de,text_right
        ld c,MT32_OUTPUT_RIGHT
        cp 'r'
        jp nz,.bad
.output_word:
        call match_word
        jp nz,.bad
        ld a,c
        ld (output_choice),a
        call skip_spaces
        call at_command_end
        jp nc,.bad
.output_done:
        ld a,CMD_OUTPUT
        ld (command_mode),a
        scf
        ret
.reset:
        ld de,kw_eset
        call match_word
        jp nz,.bad
        call skip_spaces
        call at_command_end
        jp nc,.bad
        ld a,CMD_RESET
        ld (command_mode),a
        scf
        ret
; .golem usb [off|on|bridge] (#85): without a word it only reports.
.usb:
        inc hl
        ld de,kw_sb
        call match_word
        jp nz,.bad
        ld a,GOLEM_USB_OUT_QUERY
        ld (golem_value),a
        call at_command_end
        jr c,.usb_done
        ld a,(hl)
        cp ' '
        jp nz,.bad
        call skip_spaces
        call at_command_end
        jr c,.usb_done
        ld c,GOLEM_USB_OUT_BRIDGE
        ld de,text_bridge
        ld a,(hl)
        or $20
        cp 'b'
        jr z,.usb_word
        dec c                   ; GOLEM_USB_OUT_ON
        ld de,text_on
        inc hl
        ld a,(hl)
        dec hl                  ; DEC HL keeps the flags
        or $20
        cp 'n'
        jr z,.usb_word
        dec c                   ; GOLEM_USB_OUT_OFF
        ld de,text_off
.usb_word:
        call match_word
        jp nz,.bad
        ld a,c
        ld (golem_value),a
.usb_done:
        ld a,GOLEM_CMD_SET_USB_OUT
        ld b,CMD_USB
        jp .control_end
; .golem save [clear]: the Pi writes its settings to golem.cfg, or deletes it.
.save:
        inc hl
        ld de,kw_ve
        call match_word
        jp nz,.bad
        ld c,GOLEM_SAVE_WRITE
        call skip_spaces
        call at_command_end
        jr c,.save_done
        ld de,text_clear
        call match_word
        jp nz,.bad
        inc c                   ; GOLEM_SAVE_CLEAR
.save_done:
        ld a,c
        ld (golem_value),a
        ld a,GOLEM_CMD_SAVE
        ld b,CMD_SAVE
        jp .control_end

; .golem bank [0-127]: the OPL3 engine's instrument bank, next to rom and
; soundfont. Sent as SET_PARAM 5, as the settings below.
.bank:
        ld c,GOLEM_PARAM_BANK
        ld de,text_bank
        jr .set_param

; .golem set volume|fx|channels|thru|keys|loud [value]: a firmware setting that survives
; the MT-32 reset of play. Without a value it only reports.
.set:
        inc hl
        ld a,(hl)
        or $20
        cp 't'
        jp nz,.bad
        inc hl
        ld a,(hl)
        cp ' '
        jp nz,.bad
        call skip_spaces
        ld a,(hl)
        or $20
        ld c,GOLEM_PARAM_VOLUME
        ld de,text_volume
        cp 'v'
        jr z,.set_param
        inc c                   ; GOLEM_PARAM_FX
        ld de,text_fx
        cp 'f'
        jr z,.set_param
        inc c                   ; GOLEM_PARAM_CHANNELS
        ld de,text_channels
        cp 'c'
        jr z,.set_param
        inc c                   ; GOLEM_PARAM_THRU
        ld de,text_thru
        cp 't'
        jr z,.set_param
        inc c                   ; GOLEM_PARAM_KEYS
        ld de,text_keys
        cp 'k'
        jr z,.set_param
        inc c                   ; GOLEM_PARAM_BANK: .golem bank
        inc c                   ; GOLEM_PARAM_LOUD
        ld de,text_loud
        cp 'l'
        jr nz,.bad
.set_param:
        call match_word
        jr nz,.bad
        ld a,c
        ld (golem_value),a
        ld a,GOLEM_PARAM_QUERY
        ld (golem_value2),a
        call skip_spaces
        call at_command_end
        jr c,.set_done
        ld a,c
        cp GOLEM_PARAM_BANK
        jr z,.set_number
        or a
        jr nz,.set_word
.set_number:
        call parse_u8
        jr nc,.bad
        cp 128                  ; bank: 0-127, the Golem checks what it has
        jr nc,.bad
        ld b,a
        ld a,(golem_value)
        or a
        ld a,b
        jr nz,.set_value
        cp 101                  ; volume: 0-100
        jr nc,.bad
        jr .set_value
.set_word:
        cp GOLEM_PARAM_CHANNELS
        ld a,(hl)
        jr z,.set_channels
        inc hl                  ; on or off: the second letter
        ld a,(hl)
        dec hl                  ; DEC HL keeps the flags
        or $20
        ld de,text_on
        cp 'n'
        ld a,1
        jr z,.set_match
        ld de,text_off
        xor a
        jr .set_match
.set_channels:
        or $20
        ld de,text_std
        cp 's'
        ld a,0
        jr z,.set_match
        ld de,text_alt
        inc a
.set_match:
        push af                 ; A = value
        call match_word
        pop bc                  ; B = value; flags from match_word
        jr nz,.bad
        ld a,b
.set_value:
        ld (golem_value2),a
.set_done:
        ld a,GOLEM_CMD_SET_PARAM
        ld b,CMD_SET
; Golem control commands end here. A = golem_command, B = command_mode.
.control_end:
        ld (golem_command),a
        ld a,b
        ld (command_mode),a
        call skip_spaces
        call at_command_end     ; carry: the command ends here
        ret c
.bad:
        or a
        ret

; Case-insensitive keyword match.
; In: HL=input, DE=lower-case keyword ending in 0.
; Out: Z and HL past the word if it matched; NZ otherwise. Uses A, B, DE.
match_word:
        ld a,(de)
        or a
        ret z
        ld b,a
        ld a,(hl)
        or $20
        cp b
        ret nz
        inc de
        inc hl
        jr match_word

parse_note_args:
        call parse_u8
        jr nc,.bad
        cp 128
        jr nc,.bad
        ld (note_value),a
        ld a,(hl)
        cp ' '
        jr nz,.bad

        call parse_u8
        jr nc,.bad
        or a
        jr z,.bad
        cp 128
        jr nc,.bad
        ld (note_velocity),a
        ld a,(hl)
        cp ' '
        jr nz,.bad

        call parse_u8
        jr nc,.bad
        or a
        jr z,.bad
        cp 61
        jr nc,.bad
        ld (note_seconds),a
        call skip_spaces
        call at_command_end
        jr c,.default_channel

        call parse_u8
        jr nc,.bad
        or a
        jr z,.bad
        cp 17
        jr nc,.bad
        dec a
        ld (note_channel),a
        call skip_spaces
        call at_command_end
        jr nc,.bad
        jr .good
.default_channel:
        xor a
        ld (note_channel),a
.good:
        ld a,CMD_NOTE
        ld (command_mode),a
        scf
        ret
.bad:
        or a
        ret

; Parse one unsigned decimal byte. HL advances to the first non-digit.
parse_u8:
        call skip_spaces
        ld b,0
        ld c,0
.digit:
        ld a,(hl)
        cp '0'
        jr c,.done
        cp '9'+1
        jr nc,.done
        sub '0'
        ld d,a
        ld a,b
        add a,a
        jr c,.bad
        ld e,a
        add a,a
        jr c,.bad
        add a,a
        jr c,.bad
        add a,e
        jr c,.bad
        add a,d
        jr c,.bad
        ld b,a
        inc hl
        inc c
        jr .digit
.done:
        ld a,c
        or a
        jr z,.bad
        ld a,b
        scf
        ret
.bad:
        or a
        ret

at_command_end:
        ld a,(hl)
        or a
        jr z,.yes
        cp $0d
        jr z,.yes
        cp ':'
        jr z,.yes
        or a
        ret
.yes:
        scf
        ret

skip_spaces:
        ld a,(hl)
        cp ' '
        ret nz
        inc hl
        jr skip_spaces

query_driver:
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_QUERY
        rst $08
        db NEXTZXOS_M_DRVAPI
        ret c
        ld a,b
        cp $4d
        jr nz,.bad
        ld a,c
        cp $54
        jr nz,.bad
        ld a,d
        or a                    ; ABI major 0 while experimental
        jr nz,.bad
        ld (driver_caps),hl
        or a
        ret
.bad:
        scf
        ret
