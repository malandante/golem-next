; MIDI input library: whole MIDI messages from GOLEM.DRV's READ. MIT licence.
;
; Include this file from a client. It needs the constants of
; include/mt32_api.inc. It does not acquire GOLEM.DRV: the client does ACQUIRE
; before reading and RELEASE when it has finished.
;
; Where the bytes come from depends on the driver output (.golem output):
; - golem: the Pi's UART. With `.golem set keys on` the Golem sends there what a
;   USB keyboard on the Pi plays, between its own replies to Golem requests.
; - left/right: pin 9 of that joystick port, through a MIDI IN adapter (a DIN
;   keyboard or synth, without a Pi).
;
; The parser handles running status, real-time bytes inside other messages and
; SysEx of any length, and drops the Golem replies (SysEx F0 7D 47 4C 4D), so
; only music reaches the client.
;
; Calling rules (all routines):
; - Carry set on error, with A = the driver error (MT32_ERR_*). IX and IY are
;   never used. AF, BC, DE and HL are not preserved.
; - MMU0/MMU1 must hold the ROM (GOLEM.DRV requirement), and the 16-byte buffer
;   given to mi_init must be visible between $4000 and $FFFF.
;
; mi_init  In: HL = 16-byte receive buffer ($4000-$FFFF), DE = SysEx buffer,
;              B = its size (1-255; 0 means no SysEx is kept).
; mi_get   Out: A = 0, nothing new (Z set); A = MI_GET_SHORT, a channel, system
;              common or real-time message in mi_message, B = its length (1-3);
;              A = MI_GET_SYSEX, a SysEx in the SysEx buffer (with F0 and F7),
;              B = bytes kept, C = 1 if it was longer than the buffer (cut).
;          Each call does at most one driver READ (16 bytes), so call it once
;          per frame or more often: at 31250 baud up to about 63 bytes arrive
;          per 50 Hz frame.

MI_GET_NONE         equ 0
MI_GET_SHORT        equ 1
MI_GET_SYSEX        equ 2

mi_init:
        ld (mi_rx_buffer),hl
        ld (mi_sysex_buffer),de
        ld a,b
        ld (mi_sysex_size),a
        xor a
        ld (mi_rx_left),a
        ld (mi_status),a
        ld (mi_in_sysex),a
        ret

mi_get:
        xor a
        ld (mi_did_read),a
mi_at_next_byte:
        ld a,(mi_rx_left)
        or a
        jr nz,mi_at_have_bytes
        ld a,(mi_did_read)
        or a
        jr z,mi_at_read
        xor a                   ; one READ per call: MI_GET_NONE, Z set
        ret
mi_at_read:
        inc a
        ld (mi_did_read),a
        ld hl,(mi_rx_buffer)
        ld (mi_rx_next),hl
        ld de,MT32_MAX_READ
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_READ
        rst $08
        db NEXTZXOS_M_DRVAPI
        ret c                   ; A = driver error
        ld a,c                  ; bytes received (0-16)
        or a
        ret z                   ; A = MI_GET_NONE, Z set
        ld (mi_rx_left),a
mi_at_have_bytes:
        dec a
        ld (mi_rx_left),a
        ld hl,(mi_rx_next)
        ld a,(hl)
        inc hl
        ld (mi_rx_next),hl
        call mi_byte
        or a
        jr z,mi_at_next_byte
        ret                     ; NC from mi_byte

; A = one received byte. Out: A = MI_GET_NONE (keep going), MI_GET_SHORT or MI_GET_SYSEX
; as mi_get, NC.
mi_byte:
        cp $f8
        jr c,mi_at_not_real_time
        ld (mi_message),a       ; real time: alone, whatever is in progress
        ld b,1
        ld a,MI_GET_SHORT
        or a
        ret
mi_at_not_real_time:
        bit 7,a
        jp z,mi_at_data
        cp $f0
        jp z,mi_at_sysex_start
        cp $f7
        jp z,mi_at_sysex_end
        ld c,a                  ; any other status ends an open SysEx (cut)
        xor a
        ld (mi_in_sysex),a
        ld (mi_common),a
        ld (mi_count),a
        ld a,c
        ld (mi_message),a
        ld (mi_status),a
        cp $f0
        jr nc,mi_at_system_common
        and $e0                 ; $c0 and $d0: one data byte, else two
        cp $c0
        ld a,2
        jr nz,mi_at_need
        dec a
mi_at_need:
        ld (mi_need),a
        xor a
        ret
mi_at_system_common:                 ; A = $f1-$f6
        cp $f6
        jr z,mi_at_tune_request
        ld b,2
        cp $f2                  ; song position: two data bytes
        jr z,mi_at_common_need
        dec b
        cp $f1                  ; MTC quarter frame, song select: one
        jr z,mi_at_common_need
        cp $f3
        jr z,mi_at_common_need
        xor a                   ; $f4, $f5: undefined, ignored
        ld (mi_status),a
        ret
mi_at_common_need:
        ld a,b
        ld (mi_need),a
        ld a,1
        ld (mi_common),a        ; mi_status keeps it until its data arrive
        xor a
        ret
mi_at_tune_request:
        xor a
        ld (mi_status),a
        ld b,1
        ld a,MI_GET_SHORT
        or a
        ret

mi_at_data:
        ld c,a
        ld a,(mi_in_sysex)
        or a
        jr nz,mi_at_sysex_data
        ld a,(mi_status)
        or a
        ret z                   ; stray data byte: A = MI_GET_NONE
        ld (mi_message),a       ; running status
        ld hl,mi_count
        ld e,(hl)
        inc (hl)
        ld d,0
        ld hl,mi_message+1
        add hl,de
        ld (hl),c
        ld a,(mi_need)
        dec a
        cp e
        jr z,mi_at_complete
        xor a
        ret
mi_at_complete:
        add a,2                 ; length = data bytes + 1
        ld b,a
        xor a
        ld (mi_count),a
        ld a,(mi_common)
        or a
        jr z,mi_at_short
        xor a
        ld (mi_common),a
        ld (mi_status),a        ; system common: no running status
mi_at_short:
        ld a,MI_GET_SHORT
        or a
        ret

mi_at_sysex_start:
        ld a,1
        ld (mi_in_sysex),a
        xor a
        ld (mi_status),a
        ld (mi_common),a
        ld (mi_sysex_length),a
        ld (mi_sysex_cut),a
        ld c,$f0
mi_at_sysex_data:
        ld a,(mi_sysex_length)
        ld hl,mi_sysex_size
        cp (hl)
        jr nc,mi_at_sysex_full
        ld e,a
        inc a
        ld (mi_sysex_length),a
        ld d,0
        ld hl,(mi_sysex_buffer)
        add hl,de
        ld (hl),c
        xor a
        ret
mi_at_sysex_full:
        ld a,1
        ld (mi_sysex_cut),a
        xor a
        ret

mi_at_sysex_end:
        ld a,(mi_in_sysex)
        or a
        ret z                   ; F7 without F0: ignored
        ld c,$f7
        call mi_at_sysex_data
        xor a
        ld (mi_in_sysex),a
        ; Golem reply (F0 7D 47 4C 4D ...): not music, dropped
        ld a,(mi_sysex_length)
        cp 6
        jr c,mi_at_sysex_ready
        ld hl,(mi_sysex_buffer)
        inc hl
        ld de,mi_golem_signature
        ld b,4
mi_at_compare:
        ld a,(de)
        cp (hl)
        jr nz,mi_at_sysex_ready
        inc de
        inc hl
        djnz mi_at_compare
        xor a                   ; MI_GET_NONE
        ret
mi_at_sysex_ready:
        ld a,(mi_sysex_cut)
        ld c,a
        ld a,(mi_sysex_length)
        ld b,a
        ld a,MI_GET_SYSEX
        or a
        ret

mi_golem_signature:
        db $7d,$47,$4c,$4d

mi_rx_buffer:    dw 0
mi_rx_next:      dw 0
mi_rx_left:      db 0
mi_did_read:     db 0
mi_sysex_buffer: dw 0
mi_sysex_size:   db 0
mi_sysex_length: db 0
mi_sysex_cut:    db 0
mi_in_sysex:     db 0
mi_status:       db 0           ; running status; 0 = none
mi_common:       db 0           ; 1 while a system common message is open
mi_need:         db 0           ; data bytes of the current message
mi_count:        db 0           ; data bytes received so far
mi_message:      ds 3           ; status and up to two data bytes
