; golem-next .GOLEM module: Golem control client: request, response wait and validation.
; Included by src/dot/golem_cli.s; not assembled on its own. Uses the
; constants and labels defined there and in the other modules.

send_golem_control:
        ld a,$f0
        ld (IO_BUFFER),a
        ld a,GOLEM_SYSEX_MANUFACTURER
        ld (IO_BUFFER+1),a
        ld a,GOLEM_SIGNATURE_0
        ld (IO_BUFFER+2),a
        ld a,GOLEM_SIGNATURE_1
        ld (IO_BUFFER+3),a
        ld a,GOLEM_SIGNATURE_2
        ld (IO_BUFFER+4),a
        ld a,GOLEM_PROTOCOL_VERSION
        ld (IO_BUFFER+5),a
        ld a,(golem_transaction)
        ld (IO_BUFFER+6),a
        ld a,(golem_command)
        ld (IO_BUFFER+7),a
        ld a,(golem_command)
        or a                    ; GOLEM_CMD_GET_STATUS: no payload
        jp z,.no_payload
        ld a,(golem_value)
        ld (IO_BUFFER+8),a
        ld a,(golem_command)
        cp GOLEM_CMD_SET_SOUNDFONT
        jp z,.soundfont
        ld a,$f7
        ld (IO_BUFFER+9),a
        ld hl,IO_BUFFER
        ld de,10
        call write_all
        ret c
        jp wait_golem_response
.no_payload:
        ld a,$f7
        ld (IO_BUFFER+8),a
        ld hl,IO_BUFFER
        ld de,9
        call write_all
        ret c
        jp wait_golem_response
.soundfont:
        xor a                   ; high seven bits; CLI currently accepts 0..127
        ld (IO_BUFFER+9),a
        ld a,$f7
        ld (IO_BUFFER+10),a
        ld hl,IO_BUFFER
        ld de,11
        call write_all
        ret c
        jp wait_golem_response

; .MT32 and .GM (CLI_ENGINE 1 and 2): before play and note, ask a Golem for
; the engine and wait until it is ready (#76). A synth that does not answer
; ACCEPTED within GOLEM_ACCEPT_FRAMES, or a driver without RX, is taken for an
; external synth and the command plays anyway. Carry: ERROR, cancel or
; transport failure (golem_remote_error and cancelled tell which).
select_engine:
        ld a,CLI_ENGINE
        or a
        ret z
        ld a,(driver_caps)
        and MT32_CAP_RX_NONBLOCKING
        ret z                   ; AND clears carry
        ld a,GOLEM_CMD_SET_SYNTH
        ld (golem_command),a
        ld a,CLI_ENGINE-1       ; 0 MT-32, 1 FluidSynth
        ld (golem_value),a
        ld a,r
        and $7f
        ld (golem_transaction),a
        ld a,GOLEM_ACCEPT_FRAMES
        ld (golem_accept_wait),a
        call send_golem_control
        ret nc
        ld a,(golem_no_answer)
        or a
        ret nz                  ; no Golem: OR clears carry
        scf
        ret

; Waits outside the resident driver. At 50/60 Hz this is a bounded 30/25 s
; window, long enough for an SD-backed SoundFont switch without blocking an
; M_DRVAPI call. READY is valid only after a matching ACCEPTED response.
; golem_accept_wait, when not 0, bounds the wait for ACCEPTED in frames; if
; it runs out, golem_no_answer is set and carry returned.
wait_golem_response:
        xor a
        ld (golem_rx_length),a
        ld (golem_accepted),a
        ld (golem_remote_error),a
        ld (golem_no_answer),a
        ld hl,1500
        ld (golem_timeout),hl
.poll:
        call read_golem_chunk
        ret c
        cp 2
        jp z,.ready
        cp 3
        jp z,.failed
        call check_cancel       ; SPACE ends the wait (#26)
        ret c
        ld a,(golem_last_count) ; a full read: more bytes may be waiting
        cp MT32_MAX_READ
        jp z,.poll
        ei
        halt
        ld a,(golem_accepted)
        or a
        jp nz,.long_wait
        ld a,(golem_accept_wait)
        or a
        jp z,.long_wait
        dec a
        ld (golem_accept_wait),a
        jp nz,.long_wait
        inc a
        ld (golem_no_answer),a
        scf
        ret
.long_wait:
        ld hl,(golem_timeout)
        dec hl
        ld (golem_timeout),hl
        ld a,h
        or l
        jp nz,.poll
        scf
        ret
.ready:
        or a
        ret
.failed:
        scf
        ret

; Returns A=0 pending, A=2 READY, A=3 ERROR. Carry reports driver failure.
read_golem_chunk:
        ld hl,IO_BUFFER
        ld de,MT32_MAX_READ
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_READ
        rst $08
        db NEXTZXOS_M_DRVAPI
        ret c
        ld a,c
        ld (golem_last_count),a
        ld (golem_read_remaining),a
        ld hl,IO_BUFFER
.byte_loop:
        ld a,(golem_read_remaining)
        or a
        jp z,.pending
        dec a
        ld (golem_read_remaining),a
        ld a,(hl)
        inc hl
        push hl
        call feed_golem_byte
        pop hl
        cp 1
        jp nz,.not_accepted
        ld a,1
        ld (golem_accepted),a
        jp .byte_loop
.not_accepted:
        cp 2
        jp nz,.not_ready
        ld a,(golem_accepted)
        or a
        jp z,.byte_loop
        ld a,2
        or a
        ret
.not_ready:
        cp 3
        jp z,.event
        jp .byte_loop
.pending:
        xor a
.event:
        or a
        ret

; Streaming SysEx parser. Any F0 restarts framing, malformed/high-bit data is
; discarded, and unrelated transaction/command replies are ignored.
feed_golem_byte:
        cp $f0
        jp nz,.continuation
        ld (golem_rx_frame),a
        ld a,1
        ld (golem_rx_length),a
        xor a
        ret
.continuation:
        cp $f7
        jp z,.append
        bit 7,a
        jp nz,.reset
.append:
        ld c,a
        ld a,(golem_rx_length)
        or a
        jp z,.none
        cp GOLEM_RX_FRAME_MAX
        jp nc,.reset
        ld e,a
        ld d,0
        ld hl,golem_rx_frame
        add hl,de
        ld (hl),c
        inc a
        ld (golem_rx_length),a
        ld a,c
        cp $f7
        jp nz,.none
        call validate_golem_frame
        push af
        xor a
        ld (golem_rx_length),a
        pop af
        ret
.reset:
        xor a
        ld (golem_rx_length),a
.none:
        xor a
        ret

; Returns 1=ACCEPTED, 2=READY or STATUS (payload copied to golem_status),
; 3=ERROR, 0=irrelevant/malformed.
validate_golem_frame:
        ld a,(golem_rx_length)
        cp 10
        jp c,.invalid
        ld a,(golem_rx_frame+1)
        cp GOLEM_SYSEX_MANUFACTURER
        jp nz,.invalid
        ld a,(golem_rx_frame+2)
        cp GOLEM_SIGNATURE_0
        jp nz,.invalid
        ld a,(golem_rx_frame+3)
        cp GOLEM_SIGNATURE_1
        jp nz,.invalid
        ld a,(golem_rx_frame+4)
        cp GOLEM_SIGNATURE_2
        jp nz,.invalid
        ld a,(golem_rx_frame+5)
        cp GOLEM_PROTOCOL_VERSION
        jp nz,.invalid
        ld a,(golem_transaction)
        ld b,a
        ld a,(golem_rx_frame+6)
        cp b
        jp nz,.invalid
        ld a,(golem_command)
        ld b,a
        ld a,(golem_rx_frame+8)
        cp b
        jp nz,.invalid
        ld a,(golem_rx_frame+7)
        cp GOLEM_RESPONSE_ACCEPTED
        jp z,.accepted
        cp GOLEM_RESPONSE_READY
        jp z,.ready
        cp GOLEM_RESPONSE_ERROR
        jp z,.error
        cp GOLEM_RESPONSE_STATUS
        jp z,.status
.invalid:
        xor a
        ret
.accepted:
        ld a,(golem_rx_length)
        cp 10
        jp nz,.invalid
        ld a,1
        ret
.ready:
        ld a,(golem_command)
        cp GOLEM_CMD_SET_SOUNDFONT
        jp z,.ready_soundfont
        ld a,(golem_rx_length)
        cp 11
        jp nz,.invalid
        ld a,(golem_value)
        ld b,a
        ld a,(golem_rx_frame+9)
        cp b
        jp nz,.invalid
        ld a,2
        ret
.ready_soundfont:
        ld a,(golem_rx_length)
        cp 12
        jp nz,.invalid
        ld a,(golem_value)
        ld b,a
        ld a,(golem_rx_frame+9)
        cp b
        jp nz,.invalid
        ld a,(golem_rx_frame+10)
        or a
        jp nz,.invalid
        ld a,2
        ret
.error:
        ld a,(golem_rx_length)
        cp 11
        jp nz,.invalid
        ld a,(golem_rx_frame+9)
        ld (golem_remote_error),a
        ld a,3
        ret
.status:
        ld a,(golem_rx_length)
        cp 17
        jp nz,.invalid
        ld hl,golem_rx_frame+9
        ld de,golem_status
        ld bc,7
        ldir
        ld a,2
        ret

; .golem status: ask a Golem for its state (GET_STATUS) and print it. Needs a
; free session. Returns HL = closing message for exit_success, or carry and
; HL = error report.
query_golem:
        ld a,(driver_caps)
        and MT32_CAP_RX_NONBLOCKING
        ld hl,msg_golem_no_rx
        ret z                   ; AND clears carry
        ld a,(status_flags)
        bit 0,a
        ld hl,msg_golem_busy
        ret nz
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_ACQUIRE
        rst $08
        db NEXTZXOS_M_DRVAPI
        ld hl,err_driver
        ret c
        ld a,1
        ld (driver_acquired),a
        ld a,GOLEM_CMD_GET_STATUS
        ld (golem_command),a
        ld a,r
        and $7f
        ld (golem_transaction),a
        ld a,GOLEM_ACCEPT_FRAMES
        ld (golem_accept_wait),a
        call send_golem_control
        jp nc,print_golem_status
        ld a,(golem_no_answer)
        or a
        ld hl,msg_golem_silent
        ret nz                  ; OR clears carry
        ld a,(cancelled)
        or a
        ld hl,msg_golem_query_cancelled
        ret nz
        ld a,(golem_remote_error)
        or a
        ld hl,err_golem_rejected
        scf
        ret nz
        ld hl,err_transport
        ret

; golem_status: capabilities (2), availability (bit 0 MT-32, bit 1
; FluidSynth), engine (0 MT-32, 1 FluidSynth, $7F none), ROM set (0 old,
; 1 new, 2 CM-32L, $7F none), SoundFont index (14 bits, $3FFF none).
print_golem_status:
        ld hl,msg_gs_engine
        call print_z
        ld a,(golem_status+3)
        ld hl,text_engine_mt32
        or a
        jp z,.engine
        ld hl,text_engine_fluidsynth
        dec a
        jp z,.engine
        ld hl,text_engine_none
.engine:
        call print_z
        ld a,(golem_status+2)
        bit 0,a
        ld hl,msg_gs_no_mt32
        jp z,.rom_done
        ld hl,msg_gs_rom
        call print_z
        ld a,(golem_status+4)
        ld hl,text_old
        or a
        jp z,.rom_done
        ld hl,text_new
        dec a
        jp z,.rom_done
        ld hl,text_cm32l
        dec a
        jp z,.rom_done
        ld hl,text_unknown
.rom_done:
        call print_z
        ld a,(golem_status+2)
        bit 1,a
        ld hl,msg_gs_no_soundfont
        jp z,.last
        ld hl,msg_gs_soundfont
        call print_z
        ld a,(golem_status+6)   ; HL = high x 128 + low
        ld h,a
        ld a,(golem_status+5)
        ld l,a
        srl h
        jp nc,.even
        set 7,l
.even:
        ld a,h
        cp $3f
        jp nz,.number
        ld a,l
        cp $ff
        jp nz,.number
        ld hl,text_unknown
        jp .last
.number:
        call print_dec
        ld hl,msg_crlf
        or a
        ret
.last:
        call print_z
        ld hl,msg_crlf
        or a
        ret

; Prints HL (0-65535) in decimal without leading zeros.
print_dec:
        ld e,0                  ; set once a digit has been printed
        ld bc,-10000
        call .digit
        ld bc,-1000
        call .digit
        ld bc,-100
        call .digit
        ld bc,-10
        call .digit
        ld a,l
        add a,'0'
        jp .print
.digit:
        ld a,'0'-1
.count:
        inc a
        add hl,bc
        jp c,.count
        sbc hl,bc               ; carry is clear: undo the last step
        cp '0'
        jp nz,.print_digit
        bit 0,e
        ret z
.print_digit:
        ld e,1
.print:
        push hl
        push de
        rst $10
        pop de
        pop hl
        ret
