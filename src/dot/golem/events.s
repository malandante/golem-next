; golem-next .GOLEM module: Event decoding and MIDI output.
; Included by src/dot/golem_cli.s; not assembled on its own. Uses the
; constants and labels defined there and in the other modules.
;
; Every merged channel event emits an explicit status byte.

process_event:
        ld ix,(selected_track)
        call rd_load
        call rd_peek
        jp nc,.bad
        ld b,a
        ld a,(sysex_open)
        or a
        jp z,.read_status
        ld a,b
        cp $f7                 ; only a continuation may follow open SysEx
        jp nz,.bad
.read_status:
        ld a,b
        bit 7,a
        jp z,.running
        cp $f0
        jp nc,.system
        ld (ix+ST_STATUS),a
        call rd_byte           ; consume the status byte
        jp .channel
.running:
        ld a,(ix+ST_STATUS)
        or a
        jp z,.bad
.channel:
        ld (event_status),a
        and $f0
        cp $c0
        jp z,.one_data
        cp $d0
        jp z,.one_data
        ld c,2
        jp .have_data_len
.one_data:
        ld c,1
.have_data_len:
        call rd_byte
        jp nc,.bad
        bit 7,a
        jp nz,.bad
        ld (IO_BUFFER+1),a
        dec c
        jp z,.channel_ready
        call rd_byte
        jp nc,.bad
        bit 7,a
        jp nz,.bad
        ld (IO_BUFFER+2),a
.channel_ready:
        call rd_store
        ld a,(event_status)
        ld (IO_BUFFER),a
        and $f0
        cp $c0
        jp z,.send_two
        cp $d0
        jp z,.send_two
        ld de,3
        jp .send_channel
.send_two:
        ld de,2
.send_channel:
        ld hl,IO_BUFFER
        call write_all
        jp c,.bad
        jp .next_delta

.system:
        cp $ff
        jp z,.meta
        cp $f0
        jp z,.sysex
        cp $f7
        jp z,.sysex
        jp .bad

.meta:
        xor a
        ld (ix+ST_STATUS),a
        call rd_byte           ; FF
        call rd_byte
        jp nc,.bad
        ld (event_type),a
        call rd_vlq
        jp nc,.bad
        call payload_length    ; HL=length (16-bit), checked against the track
        jp nc,.bad
        ld a,(event_type)
        cp $2f
        jp z,.end_track
        cp $51
        jp nz,.skip_meta
        ld a,h
        or a
        jp nz,.bad
        ld a,l
        cp 3
        jp nz,.bad
        call rd_byte
        ld (tempo+2),a
        call rd_byte
        ld (tempo+1),a
        call rd_byte
        ld (tempo),a
        xor a
        ld (tempo+3),a
        ld a,(tempo)
        ld b,a
        ld a,(tempo+1)
        or b
        ld b,a
        ld a,(tempo+2)
        or b
        jp z,.bad
        jp .meta_done
.skip_meta:
        call rd_skip
        jp nc,.bad
.meta_done:
        call rd_store
        jp .next_delta
.end_track:
        ld a,h
        or l
        jp nz,.bad
        ld a,1
        ld (ix+ST_DONE),a
        or a
        ret

.sysex:
        ld (event_type),a
        xor a
        ld (ix+ST_STATUS),a
        call rd_byte           ; F0 or F7
        call rd_vlq
        jp nc,.bad
        call payload_length    ; HL=length, checked against the track
        jp nc,.bad
        ld (sysex_left),hl
        ld a,(event_type)       ; validate before the first byte leaves (#27):
        cp $f0                  ; SysEx data must be 7-bit, F7 only at the end
        jp z,.validate_sysex
        ld a,(sysex_open)
        or a
        jp z,.sysex_valid       ; standalone F7 escape: raw bytes, unchecked
.validate_sysex:
        ld hl,(rd_pos)
        ld (rd_saved),hl
        ld a,(rd_pos+2)
        ld (rd_saved+2),a
        ld de,(sysex_left)
.validate_loop:
        ld a,d
        or e
        jp z,.validate_done
        ld a,e                  ; every 16 bytes, keep the raster count: a
        and $0f                 ; long scan can outlast a frame (#57)
        jp nz,.validate_byte
        push de
        call account_raster_lines
        pop de
.validate_byte:
        call rd_byte
        jp nc,.bad
        dec de
        or a
        jp p,.validate_loop     ; 7-bit data
        cp $f7
        jp nz,.bad
        ld a,d                  ; F7 is only allowed as the last byte
        or e
        jp nz,.bad
.validate_done:
        ld hl,(rd_saved)
        ld (rd_pos),hl
        ld a,(rd_saved+2)
        ld (rd_pos+2),a
.sysex_valid:
        ld a,(event_type)
        cp $f0
        jp nz,.send_sysex_payload
        ld a,$f0
        ld (IO_BUFFER),a
        ld hl,IO_BUFFER
        ld de,1
        call write_all
        jp c,.bad
        ld a,1
        ld (sysex_open),a
        ld hl,(selected_track)  ; its continuation packets come first (#23)
        ld (sysex_owner),hl
.send_sysex_payload:
        ld a,(sysex_left)
        ld b,a
        ld a,(sysex_left+1)
        or b
        ld (sysex_had_data),a  ; non-zero when the payload is not empty
.send_chunk:
        ld hl,(sysex_left)
        ld a,h
        or l
        jp z,.sysex_sent
        ld a,h                 ; C=min(16, left)
        or a
        ld c,16
        jp nz,.chunk_size
        ld a,l
        cp 16
        jp nc,.chunk_size
        ld c,a
.chunk_size:
        ld b,0
        or a
        sbc hl,bc
        ld (sysex_left),hl
        ld hl,IO_BUFFER
        ld b,c
.copy:
        call rd_byte
        jp nc,.bad
        ld (hl),a
        ld (sysex_last),a
        inc hl
        djnz .copy
        ld e,c
        ld d,0
        ld hl,IO_BUFFER
        call write_all
        jp c,.bad
        jp .send_chunk
.sysex_sent:
        ld a,(sysex_open)
        or a
        jp z,.sysex_done       ; standalone F7 escape, not a continuation
        ld a,(sysex_had_data)
        or a
        jp z,.sysex_done       ; empty continuation leaves SysEx open
        ld a,(sysex_last)
        cp $f7
        jp nz,.sysex_done
        xor a
        ld (sysex_open),a
.sysex_done:
        call rd_store

.next_delta:
        call rd_vlq
        jp nc,.bad
        call rd_store
        ld a,(ix+ST_TICK)
        ld b,a
        ld a,(vlq_value)
        add a,b
        ld (ix+ST_TICK),a
        ld a,(ix+ST_TICK+1)
        ld b,a
        ld a,(vlq_value+1)
        adc a,b
        ld (ix+ST_TICK+1),a
        ld a,(ix+ST_TICK+2)
        ld b,a
        ld a,(vlq_value+2)
        adc a,b
        ld (ix+ST_TICK+2),a
        ld a,(ix+ST_TICK+3)
        ld b,a
        ld a,(vlq_value+3)
        adc a,b
        ld (ix+ST_TICK+3),a
        jp c,.bad
        or a
        ret
.bad:
        scf
        ret

; After a length VLQ: HL=length if it fits in 16 bits and the payload lies
; within the track (rd_end). Carry set if valid; rd_pos is not moved.
payload_length:
        ld a,(vlq_value+2)
        ld b,a
        ld a,(vlq_value+3)
        or b
        jp nz,.bad
        ld hl,(vlq_value)
        push hl
        call rd_check_len
        pop hl
        ret
.bad:
        or a
        ret
