; GSEQ player library, M6 phase 1 (docs/m6-gseq.md). MIT licence.
;
; Include this file from a client. It needs the constants of
; include/mt32_api.inc. It does not acquire GOLEM.DRV: the client does ACQUIRE
; before gs_start and RELEASE when it has finished (after gs_stop and the
; pumps that send the cleanup).
;
; Calling rules (all routines):
; - Carry set on error, with A = GS_ERR_*. Otherwise A = state (GS_*).
; - IX is preserved. IY is never used: the ROM interrupt routine needs it.
; - AF, BC, DE and HL are not preserved.
; - MMU0/MMU1 must hold the ROM (GOLEM.DRV requirement), and the 16-byte buffer
;   given to gs_init must be visible between $4000 and $FFFF.
; - The MMU slot chosen in gs_init is restored before every routine returns,
;   and also before each driver call, so it may be slot 0 or 1 (which must
;   hold the ROM during the call).
;
; Time: every routine that takes "now" receives in DE a free-running 16-bit
; millisecond counter. Only differences modulo 65536 are used, so pump at
; least every 30 s.

GS_STOPPED      equ 0
GS_PLAYING      equ 1
GS_PAUSED       equ 2
GS_ENDED        equ 3
GS_ERROR        equ 4

GS_ERR_FORMAT   equ 1           ; not GSEQ, or header inconsistent
GS_ERR_VERSION  equ 2           ; major version not 1
GS_ERR_CHECKSUM equ 3
GS_ERR_RECORD   equ 4           ; malformed record found while playing
GS_ERR_DRIVER   equ 5           ; GOLEM.DRV returned an error
GS_ERR_STATE    equ 6           ; call not valid in this state

GS_TASK_NONE    equ 0
GS_TASK_PAUSE   equ 1           ; CC7=0, CC123=0, CC120=0 on the 16 channels
GS_TASK_STOP    equ 2           ; CC64=0, CC123=0, CC120=0, CC7=100 on the 16 channels
GS_TASK_RESUME  equ 3           ; strike again the keys held at pause time
GS_TASK_VOLUME  equ 4           ; restore each channel's CC7 after a pause
GS_DEFAULT_VOLUME equ 100       ; part volume of an MT-32 (and GM) at power-on

GS_MAX_RECORDS  equ 8           ; records read per pump at most
GS_OUT_SIZE     equ 16          ; MT32_MAX_WRITE

GS_NEXTREG_SELECT equ $243b

; ---------------------------------------------------------------------------
; gs_init: HL = 16-byte output buffer (visible to the driver),
;          A = MMU NextReg used to read the sequence ($50-$57),
;          DE = 2048-byte key table for resume, or 0.
gs_init:
        ld (gs_out),hl
        ld (gs_mmu_reg),a
        ld (gs_keys),de
        sub $50
        rrca                    ; slot number x 32 = high byte of its window
        rrca
        rrca
        and $e0
        ld (gs_window),a
        xor a
        ld (gs_state),a
        ld (gs_task),a
        ld (gs_open_flag),a
        ld (gs_out_len),a
        ld (gs_direct_len),a
        ld (gs_errcode),a
        ld hl,0
        ld (gs_sysex_left),hl
        dec hl
        ld (gs_channels),hl     ; all 16 channels until gs_set_channels
        ld a,GS_STOPPED
        or a
        ret

; ---------------------------------------------------------------------------
; gs_set_channels: HL = channels the cleanups may touch (bit n = MIDI channel
; n+1). The start, pause, resume and stop cleanups skip the others, so a client
; can keep channels of its own (sound effects sent with gs_send) untouched.
; gs_init sets all 16. Any state.
gs_set_channels:
        ld (gs_channels),hl
        ld a,(gs_state)
        or a
        ret

; ---------------------------------------------------------------------------
; gs_open: HL = bank table: one byte with the number of 8K banks, then the
; bank numbers. DE = where the sequence starts in the first bank (0-8191), so
; several short sequences, or a sequence and other data, can share banks.
; Checks header, version, length and checksum.
gs_open:
        ld (gs_banks),hl
        ld (gs_offset),de
        call gs_enter
        xor a
        ld (gs_open_flag),a
        ld (gs_state),a
        ld (gs_task),a
        ld hl,(gs_banks)        ; limit = banks x 8192, as 24 bits
        ld a,(hl)
        ld (gs_bank_count),a
        or a
        jp z,.format
        ld l,a
        ld h,0
        add hl,hl               ; HL = count x 32: bits 8-23 of the limit
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,l
        ld (gs_end+1),a
        ld a,h
        ld (gs_end+2),a
        xor a
        ld (gs_end),a
        ld (gs_pos+2),a
        ld hl,(gs_offset)       ; the header starts at the offset
        ld a,h
        cp $20
        jp nc,.format           ; outside the first bank
        ld (gs_pos),hl
        call gs_reset_run
        ld hl,gs_header         ; read the 32-byte header
        ld b,32
.header:
        push bc
        push hl
        call gs_rd
        pop hl
        pop bc
        jp c,.format
        ld (hl),a
        inc hl
        djnz .header
        ld hl,gs_header
        ld a,(hl)
        cp 'G'
        jp nz,.format
        inc hl
        ld a,(hl)
        cp 'S'
        jp nz,.format
        inc hl
        ld a,(hl)
        cp 'E'
        jp nz,.format
        inc hl
        ld a,(hl)
        cp 'Q'
        jp nz,.format
        ld a,(gs_header+4)
        cp 1
        jp nz,.version
        ld hl,(gs_header+6)     ; header size, at least 32 and below 256
        ld a,h
        or a
        jp nz,.format
        ld a,l
        cp 32
        jp c,.format
        ld de,(gs_offset)       ; data start = offset + header size
        add hl,de
        ld (gs_data_start),hl
        ; data end = data start + length; it must fit in the banks
        ld hl,(gs_header+12)
        ld de,(gs_data_start)
        add hl,de
        ld (gs_data_end),hl
        ld a,(gs_header+14)
        adc a,0
        ld (gs_data_end+2),a
        ld hl,(gs_end)          ; limit - data end must not borrow
        ld de,(gs_data_end)
        or a
        sbc hl,de
        ld a,(gs_data_end+2)
        ld d,a
        ld a,(gs_end+2)
        sbc a,d
        jp c,.format
.fits:
        ld hl,(gs_data_end)     ; reads stop at the data end from now on
        ld (gs_end),hl
        ld a,(gs_data_end+2)
        ld (gs_end+2),a
        call gs_reset_run       ; the run was computed against the bank limit
        ld a,(gs_header+8)
        and 1
        ld (gs_loop_flag),a
        jp z,.no_loop
        ld hl,(gs_header+20)    ; loop offset < length
        ld de,(gs_header+12)
        or a
        sbc hl,de
        ld a,(gs_header+14)
        ld d,a
        ld a,(gs_header+22)
        sbc a,d
        jp nc,.format
.no_loop:
        call gs_checksum
        jp c,.checksum
        ld a,1
        ld (gs_open_flag),a
        call gs_leave
        ld a,GS_STOPPED
        or a
        ret
.format:
        ld a,GS_ERR_FORMAT
        jp .fail
.version:
        ld a,GS_ERR_VERSION
        jp .fail
.checksum:
        ld a,GS_ERR_CHECKSUM
.fail:
        push af
        call gs_leave
        pop af
        scf
        ret

; Sum of the data bytes, compared with the header. Carry set if different.
; Reads bank by bank through the window, about 30 T-states per byte.
gs_checksum:
        call gs_reset_run
        ld hl,(gs_data_start)
        ld (gs_pos),hl
        xor a
        ld (gs_pos+2),a
        ld hl,0
        ld (gs_sum),hl
        ; bytes left = length (24-bit)
        ld hl,(gs_header+12)
        ld (gs_left),hl
        ld a,(gs_header+14)
        ld (gs_left+2),a
.bank:
        ld hl,(gs_left)
        ld a,(gs_left+2)
        or h
        or l
        jp z,.compare
        call gs_map_pos         ; HL = window address of gs_pos
        ; run = min(bytes to the end of this bank, bytes left)
        ld a,(gs_pos+1)
        and $1f
        ld b,a
        ld a,(gs_pos)
        ld c,a                  ; BC = offset in the bank
        push hl
        ld hl,$2000
        or a
        sbc hl,bc               ; HL = bytes to the end of the bank
        ld b,h
        ld c,l
        ld a,(gs_left+2)
        or a
        jp nz,.run_ready        ; more than 64K left: the bank limit wins
        ld hl,(gs_left)
        or a
        sbc hl,bc
        jp nc,.run_ready
        ld bc,(gs_left)
.run_ready:
        pop hl
        push bc                 ; run length
        ld de,(gs_sum)
.sum:
        ld a,(hl)
        add a,e
        ld e,a
        jp nc,.no_carry
        inc d
.no_carry:
        inc hl
        dec bc
        ld a,b
        or c
        jp nz,.sum
        ld (gs_sum),de
        pop bc
        ; pos += run, left -= run
        ld hl,(gs_pos)
        add hl,bc
        ld (gs_pos),hl
        ld a,(gs_pos+2)
        adc a,0
        ld (gs_pos+2),a
        ld hl,(gs_left)
        or a
        sbc hl,bc
        ld (gs_left),hl
        ld a,(gs_left+2)
        sbc a,0
        ld (gs_left+2),a
        jp .bank
.compare:
        ld hl,(gs_sum)
        ld de,(gs_header+28)
        or a
        sbc hl,de
        ret z                   ; carry clear
        scf
        ret

; ---------------------------------------------------------------------------
; gs_start: DE = now. Plays from the beginning.
gs_start:
        ld a,(gs_open_flag)
        or a
        jp z,gs_bad_state
        ld (gs_last_now),de
        push ix
        call gs_enter
        ld hl,(gs_data_start)
        ld (gs_pos),hl
        xor a
        ld (gs_pos+2),a
        call gs_reset_run
        ld hl,0
        ld (gs_now),hl
        ld (gs_now+2),hl
        ld (gs_deadline),hl
        ld (gs_deadline+2),hl
        ld (gs_loops),hl
        ld (gs_sysex_left),hl
        xor a
        ld (gs_out_len),a
        ld (gs_task_index),a
        ld (gs_task_index+1),a
        ld (gs_notice),a
        ld (gs_errcode),a
        ld a,GS_TASK_STOP       ; clean the synth before the first record
        ld (gs_task),a
        call gs_clear_keys
        ld hl,gs_volume
        ld b,16
.volume:
        ld (hl),GS_DEFAULT_VOLUME
        inc hl
        djnz .volume
        call gs_read_delta
        jp c,.bad
        ld a,GS_PLAYING
        ld (gs_state),a
        call gs_leave
        pop ix
        ld a,GS_PLAYING
        or a
        ret
.bad:
        call gs_leave
        pop ix
        ld a,GS_ERR_RECORD
        scf
        ret

gs_bad_state:
        ld a,GS_ERR_STATE
        scf
        ret

; ---------------------------------------------------------------------------
; gs_pause: DE = now. Time stops now; the cleanup (CC120) goes out in the
; next pumps, after any message that is half sent.
gs_pause:
        ld a,(gs_state)
        cp GS_PLAYING
        jp nz,gs_bad_state
        call gs_advance_time    ; account time up to the pause
        ld a,GS_PAUSED
        ld (gs_state),a
        ld a,GS_TASK_PAUSE
        ld (gs_task),a
        xor a
        ld (gs_task_index),a
        ld (gs_task_index+1),a
        ld a,GS_PAUSED
        or a
        ret

; gs_resume: DE = now. The pause does not count as music time.
gs_resume:
        ld a,(gs_state)
        cp GS_PAUSED
        jp nz,gs_bad_state
        ld (gs_last_now),de
        ld a,GS_PLAYING
        ld (gs_state),a
        xor a
        ld (gs_task_index),a
        ld (gs_task_index+1),a
        ld a,GS_TASK_VOLUME     ; volumes back, then keys struck again
        ld (gs_task),a
        ld a,GS_PLAYING
        or a
        ret

; gs_stop: finish the message being sent, then CC64/CC123/CC120/CC7=100 on every
; channel over the next pumps. The state is GS_STOPPED at once; gs_busy says
; when the cleanup has left.
gs_stop:
        ld a,GS_STOPPED
        ld (gs_state),a
gs_stop_task:
        ld a,GS_TASK_STOP
        ld (gs_task),a
        xor a
        ld (gs_task_index),a
        ld (gs_task_index+1),a
        call gs_clear_keys
        ld a,(gs_state)
        or a
        ret

; ---------------------------------------------------------------------------
; gs_send: HL = complete MIDI message, B = length (1-16). It leaves in the
; next pump, before pending music, but never inside a SysEx of the music.
; Carry with A=GS_ERR_STATE if a previous direct message is still waiting.
gs_send:
        ld a,(gs_direct_len)
        or a
        jp nz,gs_bad_state
        ld a,b
        or a
        jp z,gs_bad_state
        cp GS_OUT_SIZE+1
        jp nc,gs_bad_state
        ld (gs_direct_len),a
        ld de,gs_direct
        ld c,b
        ld b,0
        ldir
        ld a,(gs_state)
        or a
        ret

; gs_query: A = state, HL = gs_info (state, error, notice, loops, time ms,
; target synth from header byte 15: 0 any, 1 MT-32/CM-32L, 2 General MIDI).
; Z clear (NZ) while bytes or a cleanup are still pending.
gs_query:
        ld hl,gs_info
        ld a,(gs_state)
        ld (hl),a
        inc hl
        ld a,(gs_errcode)
        ld (hl),a
        inc hl
        ld a,(gs_notice)
        ld (hl),a
        inc hl
        ld de,(gs_loops)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld de,(gs_now)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld de,(gs_now+2)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld a,(gs_header+15)
        ld (hl),a
        ld hl,gs_info
        ld a,(gs_out_len)
        ld b,a
        ld a,(gs_task)
        or b
        ld b,a
        ld a,(gs_direct_len)
        or b
        ld b,a
        ld a,(gs_sysex_left)
        or b
        ld b,a
        ld a,(gs_sysex_left+1)
        or b                    ; Z if idle
        ld a,(gs_state)
        ret

; ---------------------------------------------------------------------------
; gs_pump: DE = now, B = budget: how many WRITEs of up to 16 bytes this call
; may make (0 counts as 1). Each WRITE carries what is due, as before (at most
; GS_MAX_RECORDS records read); another follows only while the driver takes
; every byte and something is left to send, so a quiet song costs one WRITE
; whatever the budget. Once per frame at 50 Hz, a budget of 1 gives 800 bytes/s
; and 4 covers the 3125 bytes/s of the cable. Never waits. Returns A = state.
gs_pump:
        push ix
        ld a,b
        or a
        jp nz,.budget
        inc a
.budget:
        ld (gs_budget),a
        ld a,(gs_state)
        cp GS_PLAYING
        jp nz,.no_time
        ld a,(gs_task)          ; the cleanup before a song: time starts after it
        cp GS_TASK_STOP
        jp z,.no_time
        call gs_advance_time
        jp .timed
.no_time:
        ld (gs_last_now),de
.timed:
        call gs_enter
.again:
        ld a,(gs_out_len)       ; 1. bytes refused last time go first
        or a
        jp nz,.write
        ld hl,(gs_sysex_left)   ; 2. the rest of a SysEx being sent
        ld a,h
        or l
        jp z,.direct
        xor a
        ld (gs_used),a
        ld (gs_msg_start),a
        call gs_copy_sysex
        jp c,.record_error
        ld hl,(gs_sysex_left)   ; finished: the next record's delta follows
        ld a,h
        or l
        jp nz,.commit
        call gs_read_delta
        jp c,.record_error
        jp .commit
.direct:
        ld a,(gs_direct_len)    ; 3. a direct (client) message
        or a
        jp z,.task
        ld c,a
        ld b,0
        ld hl,gs_direct
        ld de,(gs_out)
        ldir
        ld (gs_out_len),a
        xor a
        ld (gs_direct_len),a
        jp .write
.task:
        xor a
        ld (gs_used),a
        ld a,(gs_task)          ; 4. pause, stop or resume work
        or a
        jp z,.music
        call gs_task_step
        jp .commit
.music:
        ld a,(gs_state)         ; 5. music that is due
        cp GS_PLAYING
        jp nz,.done
        call gs_fill
        jp c,.record_error
.commit:
        ld a,(gs_used)
        ld (gs_out_len),a
.write:
        ld a,(gs_out_len)
        or a
        jp z,.done
        call gs_unmap           ; the window slot may be 0 or 1: ROM for the driver
        ld a,(gs_out_len)
        ld e,a
        ld d,0
        ld hl,(gs_out)
        ld ix,(gs_out)          ; NextZXOS takes the buffer from HL in a dot
        push de                 ; command and from IX in a program (IX is
        ld c,MT32_DRIVER_ID     ; restored on return)
        ld b,MT32_FN_WRITE
        rst $08
        db NEXTZXOS_M_DRVAPI
        pop de
        jp c,.driver_error
        ld a,(gs_out_len)       ; keep the bytes that were not accepted
        sub c
        ld (gs_out_len),a
        jp z,.sent
        ld b,0                  ; move them to the start of the buffer
        ld hl,(gs_out)
        add hl,bc               ; HL = first refused byte
        ld de,(gs_out)
        ld c,a
        ldir
.done:
        call gs_leave
        pop ix
        ld a,(gs_state)
        or a
        ret
.sent:
        ld hl,gs_budget         ; all taken: another WRITE if the budget allows
        dec (hl)
        jp nz,.again
        jp .done
.record_error:
        ld a,(gs_msg_start)     ; drop a partial message, keep whole ones
        ld (gs_used),a
        ld (gs_out_len),a
        ld a,GS_ERR_RECORD
        ld (gs_errcode),a
        ld a,GS_ERROR
        ld (gs_state),a
        ld hl,0
        ld (gs_sysex_left),hl
        call gs_stop_task
        jp .write
.driver_error:
        ld a,GS_ERR_DRIVER
        ld (gs_errcode),a
        ld a,GS_ERROR
        ld (gs_state),a
        xor a
        ld (gs_out_len),a
        ld (gs_task),a
        ld hl,0
        ld (gs_sysex_left),hl
        call gs_leave
        pop ix
        ld a,GS_ERR_DRIVER
        scf
        ret

; now += (DE - last now) modulo 65536
gs_advance_time:
        ld hl,(gs_last_now)
        ex de,hl
        ld (gs_last_now),hl
        or a
        sbc hl,de               ; HL = elapsed ms
        ld de,(gs_now)
        add hl,de
        ld (gs_now),hl
        ret nc
        ld hl,(gs_now+2)
        inc hl
        ld (gs_now+2),hl
        ret

; ---------------------------------------------------------------------------
; Music: copy due records into the output buffer.
gs_fill:
        ld a,GS_MAX_RECORDS
        ld (gs_records),a
.record:
        ld a,(gs_used)
        ld (gs_msg_start),a
        call gs_due             ; deadline <= now?
        ret nc                  ; not yet (carry clear = no error)
        call gs_peek
        ret c
        cp $f0
        jp z,.sysex
        cp $ff
        jp z,.control
        cp $80
        jp c,.bad
        cp $f0
        jp nc,.bad
        ; channel message: 2 or 3 bytes
        ld b,a
        and $e0
        cp $c0
        ld c,3
        jp nz,.size
        ld c,2
.size:
        ld a,(gs_used)
        add a,c
        cp GS_OUT_SIZE+1
        ret nc                  ; does not fit: next pump
        call gs_rd              ; status
        ret c
        call gs_put
        ld (gs_status),a
        dec c
.data:
        call gs_rd
        ret c
        bit 7,a
        jp nz,.bad
        call gs_put
        dec c
        jp nz,.data
        call gs_track_volume
        call gs_track_key
        jp .next
.sysex:
        ld a,(gs_used)          ; needs room for F0 and at least one byte
        cp GS_OUT_SIZE-1
        ret nc
        call gs_rd              ; F0
        ret c
        call gs_rd_vlq
        ret c
        ld a,(gs_vlq+2)
        ld b,a
        ld a,(gs_vlq+3)
        or b
        jp nz,.bad              ; longer than 65535
        ld hl,(gs_vlq)
        ld a,h
        or l
        jp z,.bad
        ld (gs_sysex_left),hl
        call gs_check_room      ; the whole SysEx must be inside the data
        jp c,.bad
        ld a,$f0
        call gs_put
        call gs_copy_sysex
        ret c
        ld hl,(gs_sysex_left)
        ld a,h
        or l
        ret nz                  ; the rest goes in the next pumps
        jp .next
.control:
        call gs_rd              ; FF
        ret c
        call gs_rd              ; order
        ret c
        ld (gs_order),a
        call gs_rd_vlq          ; parameter length
        ret c
        ld a,(gs_vlq+2)
        ld b,a
        ld a,(gs_vlq+3)
        or b
        jp nz,.bad
        ld hl,(gs_vlq)
        ld (gs_sysex_left),hl   ; temporary use for the bounds check
        call gs_check_room
        ld hl,0
        ld (gs_sysex_left),hl
        jp c,.bad
        ld a,(gs_order)
        or a
        jp z,.end_record
        cp 1
        jp nz,.skip
        ld hl,(gs_vlq)          ; notice: first parameter byte
        ld a,h
        or l
        jp z,.skip
        call gs_rd
        ret c
        ld (gs_notice),a
        ld hl,(gs_vlq)
        dec hl
        ld (gs_vlq),hl
.skip:
        ld hl,(gs_vlq)
        call gs_skip
        jp .next
.end_record:
        ld a,(gs_loop_flag)
        or a
        jp z,.finished
        ; back to the loop: now -= deadline - loop time; deadline = loop time
        ld hl,(gs_deadline)
        ld de,(gs_header+24)
        or a
        sbc hl,de
        ld (gs_tmp),hl
        ld hl,(gs_deadline+2)
        ld de,(gs_header+26)
        sbc hl,de
        ld (gs_tmp+2),hl
        ld hl,(gs_now)
        ld de,(gs_tmp)
        or a
        sbc hl,de
        ld (gs_now),hl
        ld hl,(gs_now+2)
        ld de,(gs_tmp+2)
        sbc hl,de
        ld (gs_now+2),hl
        ld hl,(gs_header+24)
        ld (gs_deadline),hl
        ld hl,(gs_header+26)
        ld (gs_deadline+2),hl
        ld de,(gs_data_start)   ; position = data start + loop offset
        ld hl,(gs_header+20)
        add hl,de
        ld (gs_pos),hl
        ld a,(gs_header+22)
        adc a,0
        ld (gs_pos+2),a
        call gs_reset_run
        ld hl,(gs_loops)
        inc hl
        ld (gs_loops),hl
        jp .next
.finished:
        ld a,GS_ENDED
        ld (gs_state),a
        or a
        ret
.next:
        call gs_read_delta
        ret c
        ld a,(gs_records)
        dec a
        ld (gs_records),a
        jp nz,.record
        or a
        ret
.bad:
        scf
        ret

; Copy as much of the pending SysEx as fits. Data bytes must be 7-bit and the
; last one F7. Carry on a malformed byte.
gs_copy_sysex:
.byte:
        ld hl,(gs_sysex_left)
        ld a,h
        or l
        ret z
        ld a,(gs_used)
        cp GS_OUT_SIZE
        ret nc
        call gs_rd
        ret c
        ld hl,(gs_sysex_left)
        dec hl
        ld (gs_sysex_left),hl
        bit 7,a
        jp z,.put
        cp $f7
        jp nz,.bad
        ld b,a
        ld a,h
        or l
        ld a,b
        jp nz,.bad              ; F7 before the end
.put:
        call gs_put
        jp .byte
.bad:
        scf
        ret

; Append A to the output buffer. Preserves BC, DE.
gs_put:
        push de
        push af
        ld hl,(gs_out)
        ld a,(gs_used)
        ld e,a
        ld d,0
        add hl,de
        inc a
        ld (gs_used),a
        pop af
        ld (hl),a
        pop de
        ret

; Control Change 7 just copied: remember the channel volume for resume.
gs_track_volume:
        ld a,(gs_status)
        and $f0
        cp $b0
        ret nz
        call gs_last_two        ; D = controller, E = value
        ld a,d
        cp 7
        ret nz
        ld a,(gs_status)
        and $0f
        ld c,a
        ld b,0
        ld hl,gs_volume
        add hl,bc
        ld (hl),e
        ret

; Note On / Note Off just copied: update the key table for resume.
gs_track_key:
        ld hl,(gs_keys)
        ld a,h
        or l
        ret z
        ld a,(gs_status)
        and $f0
        cp $80
        jp z,.off
        cp $90
        ret nz
        ld a,(gs_used)          ; velocity is the last byte put
        call gs_last_two        ; D = note, E = velocity
        jp .store
.off:
        call gs_last_two
        ld e,0
.store:
        ld a,(gs_status)        ; index = channel x 128 + note
        and $0f
        ld h,a
        ld l,d
        srl h
        jp nc,.even
        set 7,l
.even:
        ld bc,(gs_keys)
        add hl,bc
        ld (hl),e
        ret

; D = second last byte put, E = last byte put.
gs_last_two:
        ld hl,(gs_out)
        ld a,(gs_used)
        ld c,a
        ld b,0
        add hl,bc
        dec hl
        ld e,(hl)
        dec hl
        ld d,(hl)
        ret

gs_clear_keys:
        ld hl,(gs_keys)
        ld a,h
        or l
        ret z
        ld (hl),0
        ld d,h
        ld e,l
        inc de
        ld bc,2047
        ldir
        ret

; ---------------------------------------------------------------------------
; Pause, stop and resume work, a few channels or keys per pump.
gs_task_step:
        ld a,(gs_task)
        cp GS_TASK_PAUSE
        jp z,.pause
        cp GS_TASK_STOP
        jp z,.stop
        cp GS_TASK_VOLUME
        jp z,.volume
        ; resume: scan up to 64 table entries, strike at most 5 keys
        ld b,64
.resume_scan:
        ld a,(gs_used)
        cp GS_OUT_SIZE-2
        ret nc
        ld hl,(gs_task_index)
        ld a,h
        cp 8                    ; 2048 entries done
        jp nc,.finished
        ld de,(gs_keys)
        add hl,de
        ld a,(hl)
        or a
        jp z,.resume_next
        ld e,a                  ; velocity
        ld hl,(gs_task_index)   ; channel = index >> 7, note = index & 127
        ld a,l
        and $7f
        ld d,a
        add hl,hl
        ld a,h
        and $0f
        or $90
        call gs_put
        ld a,d
        call gs_put
        ld a,e
        call gs_put
.resume_next:
        ld hl,(gs_task_index)
        inc hl
        ld (gs_task_index),hl
        djnz .resume_scan
        ret
.pause:
        ; The MT-32 (1987) does not recognise All Sound Off (CC120), so a
        ; pause mutes each part with CC7=0 at once and then releases its
        ; notes with CC123; CC120 is kept for synths that do know it (#62).
        call gs_next_channel    ; one channel (9 bytes) per pump
        cp 16
        jp nc,.finished
        ld c,a
        or $b0
        ld b,a
        call gs_put
        ld a,7
        call gs_put
        xor a
        call gs_put
        ld a,b
        call gs_put
        ld a,123
        call gs_put
        xor a
        call gs_put
        ld a,b
        call gs_put
        ld a,120
        call gs_put
        xor a
        call gs_put
        ld a,c
        inc a
        ld (gs_task_index),a
        ret
.volume:
        call gs_next_channel    ; CC7 = remembered volume, five channels per pump
        cp 16
        jp nc,.volume_done
        ld c,a
        or $b0
        call gs_put
        ld a,7
        call gs_put
        ld b,0
        ld hl,gs_volume
        add hl,bc
        ld a,(hl)
        call gs_put
        ld a,c
        inc a
        ld (gs_task_index),a
        ld a,(gs_used)
        cp GS_OUT_SIZE-2
        jp c,.volume
        ret
.volume_done:
        xor a
        ld (gs_task_index),a
        ld hl,(gs_keys)
        ld a,h
        or l
        jp z,.finished
        ld a,GS_TASK_RESUME
        ld (gs_task),a
        ret
.stop:
        ; Also the cleanup before a song (gs_start): the synth may keep notes
        ; from a session cut short (the Next switched off mid-note) or parts
        ; muted by a pause. CC7 goes back to its power-on value last, once
        ; the notes are released.
        call gs_next_channel    ; one channel (12 bytes) per pump
        cp 16
        jp nc,.finished
        ld c,a
        or $b0
        ld b,a
        call gs_put
        ld a,64
        call gs_put
        xor a
        call gs_put
        ld a,b
        call gs_put
        ld a,123
        call gs_put
        xor a
        call gs_put
        ld a,b
        call gs_put
        ld a,120
        call gs_put
        xor a
        call gs_put
        ld a,b
        call gs_put
        ld a,7
        call gs_put
        ld a,GS_DEFAULT_VOLUME
        call gs_put
        ld a,c
        inc a
        ld (gs_task_index),a
        ret
.finished:
        xor a
        ld (gs_task),a
        ret

; A = first channel from gs_task_index on that the cleanups may touch (bit
; set in gs_channels), also stored in gs_task_index; 16 when none is left.
gs_next_channel:
        ld a,(gs_task_index)
.channel:
        cp 16
        jp nc,.store
        ld hl,(gs_channels)
        ld b,a
        inc b
.shift:
        dec b
        jp z,.test
        srl h
        rr l
        jp .shift
.test:
        bit 0,l
        jp nz,.store
        inc a
        jp .channel
.store:
        ld (gs_task_index),a
        ret

; ---------------------------------------------------------------------------
; Records and time.

; Carry if deadline <= now (the next record is due).
gs_due:
        ld hl,(gs_now)
        ld de,(gs_deadline)
        or a
        sbc hl,de
        ld hl,(gs_now+2)
        ld de,(gs_deadline+2)
        sbc hl,de               ; now - deadline, borrow if negative
        ccf
        ret

; Read the delta of the next record and add it to the deadline.
gs_read_delta:
        call gs_rd_vlq
        ret c
        ld hl,(gs_deadline)
        ld de,(gs_vlq)
        add hl,de
        ld (gs_deadline),hl
        ld hl,(gs_deadline+2)
        ld de,(gs_vlq+2)
        adc hl,de
        ld (gs_deadline+2),hl
        or a
        ret

; Read a 1-4 byte VLQ into gs_vlq (32-bit). Carry on error.
; One byte (most deltas) is stored as it is; each further byte shifts by 7
; as a byte move (x256) and one shift right.
gs_rd_vlq:
        call gs_rd
        ret c
        bit 7,a
        jp nz,.multi
        ld (gs_vlq),a
        xor a                   ; carry clear
        ld (gs_vlq+1),a
        ld (gs_vlq+2),a
        ld (gs_vlq+3),a
        ret
.multi:
        and $7f
        ld hl,0
        ld (gs_vlq+2),hl
        ld l,a
        ld (gs_vlq),hl
        ld b,3
.more:
        call gs_rd              ; preserves BC
        ret c
        ld c,a
        ld hl,(gs_vlq+1)        ; vlq <<= 8 (vlq < 2^21 here: nothing lost)
        ld (gs_vlq+2),hl
        ld a,(gs_vlq)
        ld (gs_vlq+1),a
        xor a
        ld (gs_vlq),a
        ld hl,gs_vlq+3          ; vlq >>= 1
        srl (hl)
        dec hl
        rr (hl)
        dec hl
        rr (hl)
        dec hl
        rr (hl)
        ld a,c
        and $7f
        or (hl)                 ; carry clear
        ld (hl),a
        bit 7,c
        ret z
        djnz .more
        scf                     ; more than 4 bytes
        ret

; Carry unless gs_pos + gs_sysex_left <= gs_end.
gs_check_room:
        ld hl,(gs_pos)
        ld de,(gs_sysex_left)
        add hl,de
        ld b,h
        ld c,l
        ld a,(gs_pos+2)
        adc a,0
        ld d,a                  ; D:BC = end of the payload
        ld hl,(gs_end)
        or a
        sbc hl,bc
        ld a,(gs_end+2)
        sbc a,d
        ret                     ; carry if end < payload end

; Advance gs_pos by HL (already checked against the end).
gs_skip:
        ld de,(gs_pos)
        add hl,de
        ld (gs_pos),hl
        ld a,(gs_pos+2)
        adc a,0
        ld (gs_pos+2),a
        jp gs_reset_run

; ---------------------------------------------------------------------------
; Reading the sequence through the MMU window.

gs_enter:
        ld bc,GS_NEXTREG_SELECT
        in a,(c)
        ld (gs_saved_select),a
        ld a,(gs_mmu_reg)
        out (c),a
        inc b
        in a,(c)
        ld (gs_saved_bank),a
        ld a,$ff
        ld (gs_mapped),a
        ; the caller's bank is back in the window between calls: map again
gs_reset_run:
        push hl
        ld hl,0
        ld (gs_run),hl
        pop hl
        ret

; Put the caller's bank back in the window before a driver call: GOLEM.DRV
; needs the ROM in MMU0/1, which a client may use as the window. The next read
; maps the sequence again.
gs_unmap:
        ld bc,GS_NEXTREG_SELECT
        ld a,(gs_mmu_reg)
        out (c),a
        inc b
        ld a,(gs_saved_bank)
        out (c),a
        ld a,$ff
        ld (gs_mapped),a
        jp gs_reset_run

gs_leave:
        ld bc,GS_NEXTREG_SELECT
        ld a,(gs_mmu_reg)
        out (c),a
        inc b
        ld a,(gs_saved_bank)
        out (c),a
        dec b
        ld a,(gs_saved_select)
        out (c),a
        ret

; Map the bank holding gs_pos. Out: HL = its address in the window.
; Assumes gs_pos lies inside the bank table (checked by the callers).
gs_map_pos:
        ld a,(gs_pos+1)         ; bank index = pos >> 13
        rlca
        rlca
        rlca
        and $07
        ld e,a
        ld a,(gs_pos+2)
        add a,a
        add a,a
        add a,a
        or e
        ld e,a
        ld a,(gs_mapped)
        cp e
        jp z,.mapped
        ld a,e
        ld (gs_mapped),a
        ld d,0
        ld hl,(gs_banks)
        inc hl
        add hl,de
        ld e,(hl)
        ld bc,GS_NEXTREG_SELECT
        ld a,(gs_mmu_reg)
        out (c),a
        inc b
        out (c),e
.mapped:
        ld a,(gs_pos+1)
        and $1f
        ld h,a
        ld a,(gs_window)
        or h
        ld h,a
        ld a,(gs_pos)
        ld l,a
        ret

; A = byte at gs_pos without moving. Carry at or past the end.
gs_peek:
        ld hl,(gs_run)          ; bytes left in the mapped run: no checks needed
        ld a,h
        or l
        jp z,.slow
        ld hl,(gs_ptr)
        ld a,(hl)
        or a
        ret
.slow:
        call gs_at_end
        ret c
        call gs_map_pos
        ld a,(hl)
        or a
        ret

; A = byte at gs_pos, then advance. Carry at or past the end.
; Preserves BC, DE. Reads come from a run: the bytes of the mapped bank before
; its end or the data end, whichever is first (gs_run, gs_ptr). Only an empty
; run pays for the end check and the mapping.
gs_rd:
        ld hl,(gs_run)
        ld a,h
        or l
        jp z,.refill
.fast:
        dec hl
        ld (gs_run),hl
        ld hl,(gs_pos)
        inc hl
        ld (gs_pos),hl
        ld a,h
        or l
        jp nz,.read
        ld hl,gs_pos+2
        inc (hl)
.read:
        ld hl,(gs_ptr)
        ld a,(hl)
        inc hl
        ld (gs_ptr),hl
        or a
        ret
.refill:
        push de
        push bc
        call gs_at_end
        jp c,.end_of_data
        call gs_map_pos
        ld (gs_ptr),hl
        ld a,(gs_pos+1)         ; DE = bytes to the end of the bank
        and $1f
        ld d,a
        ld a,(gs_pos)
        ld e,a
        ld hl,$2000
        or a
        sbc hl,de
        ex de,hl
        ld hl,(gs_end)          ; HL = data end - pos (above zero here)
        ld bc,(gs_pos)
        or a
        sbc hl,bc
        ld a,(gs_pos+2)
        ld b,a
        ld a,(gs_end+2)
        sbc a,b
        jp nz,.bank_run         ; 64K or more to the end: the bank wins
        or a
        sbc hl,de
        jp nc,.bank_run
        add hl,de               ; the data end comes first
        jp .set_run
.bank_run:
        ex de,hl
.set_run:
        ld (gs_run),hl
        pop bc
        pop de
        jp .fast
.end_of_data:
        pop bc
        pop de
        scf
        ret

; Carry if gs_pos >= gs_end.
gs_at_end:
        ld hl,(gs_pos)
        ld de,(gs_end)
        or a
        sbc hl,de
        ld a,(gs_pos+2)
        ld d,a
        ld a,(gs_end+2)
        ld e,a
        ld a,d
        sbc a,e
        ccf
        ret

; ---------------------------------------------------------------------------
; State.
gs_out:          dw 0
gs_mmu_reg:      db $57
gs_window:       db $e0
gs_keys:         dw 0
gs_banks:        dw 0
gs_bank_count:   db 0
gs_state:        db 0
gs_errcode:        db 0
gs_task:         db 0
gs_task_index:   dw 0
gs_open_flag:    db 0
gs_loop_flag:    db 0
gs_out_len:      db 0
gs_used:         db 0
gs_msg_start:    db 0
gs_direct_len:   db 0
gs_direct:       ds GS_OUT_SIZE
gs_records:      db 0
gs_status:       db 0
gs_order:        db 0
gs_notice:       db 0
gs_loops:        dw 0
gs_sysex_left:   dw 0
gs_last_now:     dw 0
gs_now:          ds 4
gs_deadline:     ds 4
gs_vlq:          ds 4
gs_tmp:          ds 4
gs_pos:          ds 3
gs_end:          ds 3
gs_left:         ds 3
gs_sum:          dw 0
gs_data_start:   dw 0
gs_offset:       dw 0
gs_channels:     dw $ffff
gs_data_end:     ds 3
gs_mapped:       db $ff
gs_run:          dw 0
gs_budget:       db 1
gs_ptr:          dw 0
gs_saved_bank:   db 0
gs_saved_select: db 0
gs_header:       ds 32
gs_info:         ds 10
gs_volume:       ds 16
