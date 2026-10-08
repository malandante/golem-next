; golem-next .GOLEM module: Command-line parsing and driver query.
; Included by src/dot/golem_cli.s; not assembled on its own. Uses the
; constants and labels defined there and in the other modules.
;
; Commands: play, note, status, engine and soundfont.

parse_command:
        ld a,h
        or l
        jp z,.bad
        call skip_spaces
        ld a,(hl)
        or $20
        cp 'p'
        jp z,.play
        cp 'n'
        jp z,.note
        cp 's'
        jp z,.status
        cp 'e'
        jp z,.engine
        cp 'r'
        jp z,.romset
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
        jp z,.quoted

        ld de,filename
        ld b,0
.plain_loop:
        ld a,(hl)
        or a
        jp z,.plain_done
        cp $0d
        jp z,.plain_done
        cp ':'
        jp z,.plain_done
        cp ' '
        jp z,.plain_end
        ld (de),a
        inc de
        inc hl
        inc b
        jp z,.bad
        jp .plain_loop
.plain_done:
        jp .check_tail
.plain_end:
        call skip_spaces
        jp .check_tail

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
        jp z,.quote_end
        ld (de),a
        inc de
        inc hl
        inc b
        jp z,.bad
        jp .quote_loop
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
        jp z,.soundfont_after_so
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
        call skip_spaces
        call at_command_end
        jp nc,.bad
        ld a,GOLEM_SYSEX_SWITCH_SF
        ld (golem_command),a
        ld a,CMD_SOUNDFONT
        ld (command_mode),a
        scf
        ret

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
        cp 'm'
        jp z,.engine_mt32
        cp 'f'
        jp z,.engine_fluidsynth
        jp .bad
.engine_mt32:
        inc hl
        ld de,kw_t32
        call match_word
        jp nz,.bad
        xor a
        ld (golem_value),a
        jp .engine_tail
.engine_fluidsynth:
        ld de,text_fluidsynth
        call match_word
        jp nz,.bad
        ld a,GOLEM_SYNTH_SOUNDFONT
        ld (golem_value),a
.engine_tail:
        call skip_spaces
        call at_command_end
        jp nc,.bad
        ld a,GOLEM_SYSEX_SWITCH_SYNTH
        ld (golem_command),a
        ld a,CMD_ENGINE
        ld (command_mode),a
        scf
        ret

.romset:
        inc hl
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
        jp z,.rom_old
        cp 'n'
        jp z,.rom_new
        cp 'c'
        jp z,.rom_cm32l
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
        call skip_spaces
        call at_command_end
        jp nc,.bad
        ld a,GOLEM_SYSEX_SWITCH_ROM
        ld (golem_command),a
        ld a,CMD_ROMSET
        ld (command_mode),a
        scf
        ret
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
        jp nc,.bad
        cp 128
        jp nc,.bad
        ld (note_value),a
        ld a,(hl)
        cp ' '
        jp nz,.bad

        call parse_u8
        jp nc,.bad
        or a
        jp z,.bad
        cp 128
        jp nc,.bad
        ld (note_velocity),a
        ld a,(hl)
        cp ' '
        jp nz,.bad

        call parse_u8
        jp nc,.bad
        or a
        jp z,.bad
        cp 61
        jp nc,.bad
        ld (note_seconds),a
        call skip_spaces
        call at_command_end
        jp c,.default_channel

        call parse_u8
        jp nc,.bad
        or a
        jp z,.bad
        cp 17
        jp nc,.bad
        dec a
        ld (note_channel),a
        call skip_spaces
        call at_command_end
        jp nc,.bad
        jp .good
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
        jp c,.done
        cp '9'+1
        jp nc,.done
        sub '0'
        ld d,a
        ld a,b
        add a,a
        jp c,.bad
        ld e,a
        add a,a
        jp c,.bad
        add a,a
        jp c,.bad
        add a,e
        jp c,.bad
        add a,d
        jp c,.bad
        ld b,a
        inc hl
        inc c
        jp .digit
.done:
        ld a,c
        or a
        jp z,.bad
        ld a,b
        scf
        ret
.bad:
        or a
        ret

at_command_end:
        ld a,(hl)
        or a
        jp z,.yes
        cp $0d
        jp z,.yes
        cp ':'
        jp z,.yes
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
        jp skip_spaces

query_driver:
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_QUERY
        rst $08
        db NEXTZXOS_M_DRVAPI
        ret c
        ld a,b
        cp $4d
        jp nz,.bad
        ld a,c
        cp $54
        jp nz,.bad
        ld a,d
        or a                    ; ABI major 0 while experimental
        jp nz,.bad
        ld (driver_caps),hl
        or a
        ret
.bad:
        scf
        ret
