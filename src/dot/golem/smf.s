; golem-next .GOLEM module: SMF validation and per-track cursor setup.
; Included by src/dot/golem_cli.s; not assembled on its own. Uses the
; constants and labels defined there and in the other modules.

parse_smf:
        ld hl,0                 ; read the whole file: rd_pos=0, rd_end=length
        ld (rd_pos),hl
        xor a
        ld (rd_pos+2),a
        ld hl,(file_length)
        ld (rd_end),hl
        ld a,(file_length+2)
        ld (rd_end+2),a
        ld hl,text_mthd
        call rd_match4
        jp nc,.bad
        jp nz,.bad
        call rd_chunk_length    ; header length: 6..255
        jp nc,.bad
        ld a,(chunk_length+2)
        ld b,a
        ld a,(chunk_length+1)
        or b
        jp nz,.bad
        ld a,(chunk_length)
        cp 6
        jp c,.bad
        call rd_check_chunk
        jp nc,.bad
        call rd_byte            ; format high byte
        or a
        jp nz,.bad
        call rd_byte
        cp 2
        jp nc,.bad              ; formats 0 and 1 only
        ld (smf_format),a
        call rd_byte            ; track count high byte
        or a
        jp nz,.bad
        call rd_byte
        or a
        jp z,.bad
        cp MAX_TRACKS+1
        jp nc,.bad
        ld (track_count),a
        ld b,a
        ld a,(smf_format)
        or a
        jp nz,.format_ok
        ld a,b
        cp 1
        jp nz,.bad
.format_ok:
        call rd_byte
        ld b,a
        call rd_byte
        ld c,a
        bit 7,b
        jp nz,.bad              ; SMPTE division not supported
        ld a,b
        or c
        jp z,.bad
        ld (division),bc
        ld a,(chunk_length)     ; skip any extra header bytes
        sub 6
        ld l,a
        ld h,0
        call rd_skip
        jp nc,.bad
        call build_frame_quantum

        ld ix,track_states
        ld a,(track_count)
        ld (tracks_left),a
.track_loop:
        ld hl,text_mtrk
        call rd_match4
        jp nc,.bad
        push af                 ; Z = MTrk
        call rd_chunk_length
        jp nc,.bad_pop
        call rd_check_chunk     ; rd_limit = end of this chunk
        jp nc,.bad_pop
        pop af
        jp nz,.foreign          ; SMF: chunks of unknown type are skipped (#23)
        ld hl,(rd_pos)          ; track: cursor = data start, end = chunk end
        ld (ix+ST_CURSOR),l
        ld (ix+ST_CURSOR+1),h
        ld a,(rd_pos+2)
        ld (ix+ST_CURSOR+2),a
        ld hl,(rd_limit)
        ld (ix+ST_END),l
        ld (ix+ST_END+1),h
        ld a,(rd_limit+2)
        ld (ix+ST_END+2),a
        xor a
        ld (ix+ST_STATUS),a
        ld (ix+ST_DONE),a
        ld (ix+ST_TICK),a
        ld (ix+ST_TICK+1),a
        ld (ix+ST_TICK+2),a
        ld (ix+ST_TICK+3),a
        ld hl,(rd_end)          ; keep the file end while reading the delta
        ld (rd_saved),hl
        ld a,(rd_end+2)
        ld (rd_saved+2),a
        call rd_load            ; rd_pos/rd_end = this track
        call rd_vlq
        jp nc,.bad
        call rd_store
        ld a,(vlq_value)
        ld (ix+ST_TICK),a
        ld a,(vlq_value+1)
        ld (ix+ST_TICK+1),a
        ld a,(vlq_value+2)
        ld (ix+ST_TICK+2),a
        ld a,(vlq_value+3)
        ld (ix+ST_TICK+3),a
        ld l,(ix+ST_END)        ; continue after the chunk, up to the file end
        ld h,(ix+ST_END+1)
        ld (rd_pos),hl
        ld a,(ix+ST_END+2)
        ld (rd_pos+2),a
        ld hl,(rd_saved)
        ld (rd_end),hl
        ld a,(rd_saved+2)
        ld (rd_end+2),a
        ld de,ST_SIZE
        add ix,de
        ld a,(tracks_left)
        dec a
        ld (tracks_left),a
        jp nz,.track_loop
        or a
        ret
.foreign:
        ld hl,(rd_limit)
        ld (rd_pos),hl
        ld a,(rd_limit+2)
        ld (rd_pos+2),a
        jp .track_loop
.bad_pop:
        pop af
.bad:
        scf
        ret

text_mthd:
        db "MThd"
text_mtrk:
        db "MTrk"

; Build a 1 ms musical quantum and its exact raster cadence: 1 ms is 3500 T,
; that is 15 + 5/8 lines of 224 T or 15 + 20/57 lines of 228 T, distributed as
; 15- and 16-line slices (#7). This keeps the long-term tempo exact while
; leaving enough CPU time for parsing and transport at 3.5 MHz.
build_frame_quantum:
        ld bc,NEXTREG_SELECT
        ld a,NXR_PERIPHERAL1
        out (c),a
        inc b
        in a,(c)
        and $04
        ld a,0
        jp z,.rate_ready
        inc a
.rate_ready:
        ld (refresh_60),a
        ; Real time per raster line (#7). Video runs from a 3.5 MHz T-state
        ; clock: 48K/Pentagon lines are 224 T, 128K/+3 lines are 228 T, and the
        ; line count tells them apart (311 or 264 lines means 128K/+3). One
        ; millisecond is 3500 T, so 125 lines per 8 ms or 875 lines per 57 ms.
        ; Measured on a Next by HDMI: 311 lines, 49.37 Hz; 264 lines, 58.16 Hz.
        call measure_frame_lines   ; HL=lines per frame
        ld de,-250
        add hl,de
        jp nc,.default_lines       ; fewer than 250 lines: not plausible
        ld de,-81
        add hl,de
        jp c,.default_lines        ; more than 330 lines: not plausible
        ld de,331
        add hl,de                  ; HL=lines per frame again
        ld b,h
        ld c,l
        ld de,311
        or a
        sbc hl,de
        jp z,.timing_228
        ld h,b
        ld l,c
        ld de,264
        or a
        sbc hl,de
        jp z,.timing_228
        ld hl,8                    ; 224 T per line: 15 + 5/8 lines per ms
        ld de,5
        jp .lines_ready
.timing_228:
        ld hl,57                   ; 228 T per line: 15 + 20/57 lines per ms
        ld de,20
        jp .lines_ready
.default_lines:
        ld bc,312
        ld a,(refresh_60)
        or a
        jp z,.default_224
        ld bc,262
.default_224:
        ld hl,8
        ld de,5
.lines_ready:
        ld (raster_lines),bc
        ld (slice_period),hl
        ld (slice_remainder),de
        or a
        sbc hl,de
        ld (slice_phase),hl
        ld a,15
        ld (slice_lines),a

        xor a
        ld (frame_quantum),a
        ld (frame_quantum+1),a
        ld (frame_quantum+2),a
        ld (frame_quantum+3),a
        ld bc,(division)
        ld de,1000
.multiply:
        ld a,b
        or c
        jp z,.multiply_done
        ld hl,(frame_quantum)
        add hl,de
        ld (frame_quantum),hl
        ld hl,(frame_quantum+2)
        ld de,0
        adc hl,de
        ld (frame_quantum+2),hl
        ld de,1000
        dec bc
        jp .multiply
.multiply_done:
        ret
