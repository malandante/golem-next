; golem-next .GOLEM module: Deterministic track merge and raster scheduler.
; Included by src/dot/golem_cli.s; not assembled on its own. Uses the
; constants and labels defined there and in the other modules.

play_smf:
        ld hl,500000 & $ffff
        ld (tempo),hl
        ld hl,500000 >> 16
        ld (tempo+2),hl
        xor a
        ld (time_accum),a
        ld (time_accum+1),a
        ld (time_accum+2),a
        ld (time_accum+3),a
        ld (last_tick),a
        ld (last_tick+1),a
        ld (last_tick+2),a
        ld (last_tick+3),a
        ld (elapsed_lines),a
        ld (elapsed_lines+1),a
        ld (elapsed_lines+2),a
        call read_raster_line
        ld (raster_previous),hl
        ld a,1
        ld (scheduler_active),a
.event_loop:
        call check_cancel
        jp c,.failed
        call find_next_track
        jp nc,.finished
        call wait_to_selected
        jp c,.failed
        call process_event
        jp c,.failed
        jp .event_loop
.finished:
        xor a
        ld (scheduler_active),a
        or a
        ret
.failed:
        xor a
        ld (scheduler_active),a
        scf
        ret

; While a SysEx is open (F0 packet without F7, continued by F7 packets), the
; track that opened it plays next, even if another track has an earlier event:
; nothing may reach the cable between the packets of one SysEx (#23).
find_next_track:
        ld a,(sysex_open)
        or a
        jp z,.merge
        ld ix,(sysex_owner)
        ld a,(ix+ST_DONE)
        or a
        jp nz,.merge            ; owner ended: the next event is reported bad
        ld (selected_track),ix
        scf
        ret
.merge:
        xor a
        ld (best_valid),a
        ld ix,track_states
        ld a,(track_count)
        ld (scan_left),a
.scan:
        ld a,(ix+ST_DONE)
        or a
        jp nz,.next
        ld a,(best_valid)
        or a
        jp z,.choose
        ld hl,(selected_track)
        ld de,ST_TICK+3
        add hl,de               ; HL=most significant tick byte of best track
        ld a,(ix+ST_TICK+3)
        cp (hl)
        jp c,.choose
        jp nz,.next
        dec hl
        ld a,(ix+ST_TICK+2)
        cp (hl)
        jp c,.choose
        jp nz,.next
        dec hl
        ld a,(ix+ST_TICK+1)
        cp (hl)
        jp c,.choose
        jp nz,.next
        dec hl
        ld a,(ix+ST_TICK)
        cp (hl)
        jp nc,.next             ; ties retain lower track index
.choose:
        ld (selected_track),ix
        ld a,1
        ld (best_valid),a
.next:
        ld de,ST_SIZE
        add ix,de
        ld a,(scan_left)
        dec a
        ld (scan_left),a
        jp nz,.scan
        ld a,(best_valid)
        or a
        ret z
        scf
        ret

; IY is never used here: BASIC and the IM1 handler expect IY=ERR_NR while the
; command runs and when it returns. The selected track lives in memory and is
; addressed through IX instead.
wait_to_selected:
        ld ix,(selected_track)
        call account_raster_lines
        ld a,(ix+ST_TICK)
        ld b,a
        ld a,(last_tick)
        ld c,a
        ld a,b
        sub c
        ld (delta_ticks),a
        ld a,(ix+ST_TICK+1)
        ld b,a
        ld a,(last_tick+1)
        ld c,a
        ld a,b
        sbc a,c
        ld (delta_ticks+1),a
        ld a,(ix+ST_TICK+2)
        ld b,a
        ld a,(last_tick+2)
        ld c,a
        ld a,b
        sbc a,c
        ld (delta_ticks+2),a
        ld a,(ix+ST_TICK+3)
        ld b,a
        ld a,(last_tick+3)
        ld c,a
        ld a,b
        sbc a,c
        ld (delta_ticks+3),a
        jp nc,.forward
        xor a                   ; an event held behind an open SysEx is late:
        ld (delta_ticks),a      ; play it now and keep the later last_tick
        ld (delta_ticks+1),a
        ld (delta_ticks+2),a
        ld (delta_ticks+3),a
        jp .tick_loop
.forward:
        ld a,(ix+ST_TICK)
        ld (last_tick),a
        ld a,(ix+ST_TICK+1)
        ld (last_tick+1),a
        ld a,(ix+ST_TICK+2)
        ld (last_tick+2),a
        ld a,(ix+ST_TICK+3)
        ld (last_tick+3),a

.tick_loop:
        ld a,(delta_ticks)
        ld b,a
        ld a,(delta_ticks+1)
        or b
        ld b,a
        ld a,(delta_ticks+2)
        or b
        ld b,a
        ld a,(delta_ticks+3)
        or b
        jp z,.done
        call add_tempo
        call decrement_delta
.frame_loop:
        call accum_ge_quantum
        jp nc,.tick_loop
        call subtract_quantum
        call consume_raster_line
        jp c,.cancel
        jp .frame_loop
.done:
        or a
        ret
.cancel:
        scf
        ret

add_tempo:
        ld a,(time_accum)
        ld b,a
        ld a,(tempo)
        add a,b
        ld (time_accum),a
        ld a,(time_accum+1)
        ld b,a
        ld a,(tempo+1)
        adc a,b
        ld (time_accum+1),a
        ld a,(time_accum+2)
        ld b,a
        ld a,(tempo+2)
        adc a,b
        ld (time_accum+2),a
        ld a,(time_accum+3)
        ld b,a
        ld a,(tempo+3)
        adc a,b
        ld (time_accum+3),a
        ret

decrement_delta:
        ld hl,delta_ticks
        ld a,(hl)
        sub 1
        ld (hl),a
        inc hl
        ld a,(hl)
        sbc a,0
        ld (hl),a
        inc hl
        ld a,(hl)
        sbc a,0
        ld (hl),a
        inc hl
        ld a,(hl)
        sbc a,0
        ld (hl),a
        ret

accum_ge_quantum:
        ld a,(time_accum+3)
        ld b,a
        ld a,(frame_quantum+3)
        cp b
        jp c,.yes
        jp nz,.no
        ld a,(time_accum+2)
        ld b,a
        ld a,(frame_quantum+2)
        cp b
        jp c,.yes
        jp nz,.no
        ld a,(time_accum+1)
        ld b,a
        ld a,(frame_quantum+1)
        cp b
        jp c,.yes
        jp nz,.no
        ld a,(time_accum)
        ld b,a
        ld a,(frame_quantum)
        cp b
        jp c,.yes
        jp z,.yes
.no:
        or a
        ret
.yes:
        scf
        ret

subtract_quantum:
        ld a,(time_accum)
        ld b,a
        ld a,(frame_quantum)
        ld c,a
        ld a,b
        sub c
        ld (time_accum),a
        ld a,(time_accum+1)
        ld b,a
        ld a,(frame_quantum+1)
        ld c,a
        ld a,b
        sbc a,c
        ld (time_accum+1),a
        ld a,(time_accum+2)
        ld b,a
        ld a,(frame_quantum+2)
        ld c,a
        ld a,b
        sbc a,c
        ld (time_accum+2),a
        ld a,(time_accum+3)
        ld b,a
        ld a,(frame_quantum+3)
        ld c,a
        ld a,b
        sbc a,c
        ld (time_accum+3),a
        ret

; Account for scanlines already spent parsing or writing the previous event.
; Calls are frequent enough that no complete frame can pass unnoticed.
account_raster_lines:
        ld a,(scheduler_active)
        or a
        ret z
        call read_raster_line
        ld de,(raster_previous)
        ld (raster_previous),hl
        or a
        sbc hl,de
        jp nc,.have_delta
        ld bc,(raster_lines)
        add hl,bc
.have_delta:
        ld a,h
        or l
        ret z
        jp add_elapsed

; HL=raster lines to add to elapsed_lines. The count is 24-bit: a 16-bit one
; saturated after 65535 lines (4,2 s) of transport back-pressure, and that
; time was lost, e.g. the 18 KB SysEx intro of KQ5 (#57). Preserves BC, DE.
add_elapsed:
        push de
        ld de,(elapsed_lines)
        add hl,de
        ld (elapsed_lines),hl
        ld a,(elapsed_lines+2)
        adc a,0
        jp nc,.store
        ld hl,$ffff
        ld (elapsed_lines),hl
        ld a,$ff
.store:
        ld (elapsed_lines+2),a
        pop de
        ret

consume_raster_line:
.wait:
        call check_cancel
        ret c
        call account_raster_lines
        ld hl,(elapsed_lines)
        ld a,(slice_lines)
        ld e,a
        ld d,0
        or a
        sbc hl,de
        ld a,(elapsed_lines+2)
        sbc a,0
        jp c,.wait
        ld (elapsed_lines),hl
        ld (elapsed_lines+2),a
        call advance_frame_quantum
        or a
        ret

; Wait for one raster transition when transport back-pressure requires a retry.
wait_line:
.loop:
        call check_cancel
        ret c
        call read_raster_line
        ld de,(raster_previous)
        push hl
        or a
        sbc hl,de
        jp nc,.delta_ready
        ld bc,(raster_lines)
        add hl,bc
.delta_ready:
        ld a,h
        or l
        jp z,.same_line
        ex de,hl               ; DE=number of raster lines crossed
        pop hl                 ; HL=current raster position
        ld (raster_previous),hl
        ex de,hl               ; HL=number of raster lines crossed
        ld a,h
        or a
        jp nz,.record_extra
        ld a,l
        cp 1
        jp z,.done
.record_extra:
        dec hl                 ; the caller consumes the first crossed line
        call add_elapsed
.done:
        or a
        ret
.same_line:
        pop hl
        jp .loop

; Wait for a complete video frame. Used only by note duration, transport
; back-pressure and cleanup; it does not advance the SMF scheduler phase.
wait_frame:
        call read_raster_line
        ld (raster_previous),hl
.loop:
        call check_cancel
        ret c
        call read_raster_line
        ld de,(raster_previous)
        ld (raster_previous),hl
        or a
        sbc hl,de
        jp nc,.loop             ; a lower line means the counter wrapped
        or a
        ret

; Out: HL=lines per frame (highest raster line + 1). Measured at 28 MHz with
; interrupts disabled, because the IM1 routine hides its own lines from
; polling; takes two to three frames. Speed and interrupt state are restored.
measure_frame_lines:
        ld bc,NEXTREG_SELECT
        ld a,NXR_TURBO
        out (c),a
        inc b
        in a,(c)
        and $03
        ld (measure_speed),a
        ld a,$03
        out (c),a
        ld a,i                     ; P/V = IFF2
        push af
        di
        call read_raster_line
        ld (raster_previous),hl
        ld hl,0
        ld (measure_max),hl
        ld a,3
        ld (measure_wraps),a
.sample:
        call read_raster_line
        ld de,(measure_max)
        push hl
        or a
        sbc hl,de
        pop hl
        jp c,.not_max
        ld (measure_max),hl
.not_max:
        ld de,(raster_previous)
        ld (raster_previous),hl
        or a
        sbc hl,de
        jp nc,.sample              ; a lower line means the counter wrapped
        ld a,(measure_wraps)
        dec a
        ld (measure_wraps),a
        jp nz,.sample
        pop af
        jp po,.interrupts_done
        ei
.interrupts_done:
        ld bc,NEXTREG_SELECT
        ld a,NXR_TURBO
        out (c),a
        inc b
        ld a,(measure_speed)
        out (c),a
        ld hl,(measure_max)
        inc hl
        ret

; Read the 9-bit active video line consistently across an LSB rollover.
read_raster_line:
.retry:
        ld bc,NEXTREG_SELECT
        ld a,NXR_RASTER_MSB
        out (c),a
        inc b
        in a,(c)
        and $01
        ld d,a
        dec b
        ld a,NXR_RASTER_LSB
        out (c),a
        inc b
        in e,(c)
        dec b
        ld a,NXR_RASTER_MSB
        out (c),a
        inc b
        in a,(c)
        and $01
        cp d
        jp nz,.retry
        ld h,d
        ld l,e
        ret

; Select 15 or 16 physical lines for the next exact 1 ms slice.
advance_frame_quantum:
        ld hl,(slice_phase)
        ld de,(slice_remainder)
        add hl,de
        ld de,(slice_period)
        or a
        sbc hl,de
        jp c,.short_slice
        ld (slice_phase),hl
        ld a,16
        ld (slice_lines),a
        ret
.short_slice:
        add hl,de
        ld (slice_phase),hl
        ld a,15
        ld (slice_lines),a
        ret

check_cancel:
        ld bc,$7ffe
        in a,(c)
        bit 0,a                 ; SPACE
        jp nz,.no
        ld a,1
        ld (cancelled),a
        scf
        ret
.no:
        or a
        ret
