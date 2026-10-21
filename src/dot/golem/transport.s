; golem-next .GOLEM module: Driver transport, cleanup and status UI.
; Included by src/dot/golem_cli.s; not assembled on its own. Uses the
; constants and labels defined there and in the other modules.

show_status:
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_STATUS
        rst $08
        db NEXTZXOS_M_DRVAPI
        ret c
        ld a,b
        ld (status_uart),a
        ld a,c                  ; C bit 0: session acquired (B bit 0 is RX data)
        ld (status_flags),a
        bit 0,a
        ld hl,msg_status_free
        jp z,.owner_ready
        ld hl,msg_status_busy
.owner_ready:
        call print_z
        ld a,(status_flags)
        bit 1,a
        ld hl,msg_status_full
        jp nz,.tx_ready
        bit 2,a
        ld hl,msg_status_empty
        jp nz,.tx_ready
        ld hl,msg_status_active
.tx_ready:
        call print_z
        ld a,(status_uart)      ; framing, byte after an error, overflow (#17)
        and $64
        ld hl,msg_status_rx_errors
        call nz,print_z
        or a
        ret

; Duration in real milliseconds (#92): the same raster clock as play (1 ms
; slices of 15/16 lines, 224 or 228 T per line), not 50 or 60 frames per
; second, since a frame lasts 20.26 ms with +3 timing at 50 Hz.
play_note:
        call build_frame_quantum ; measures the frame before the note starts
        ld a,(note_channel)
        or $90
        ld (IO_BUFFER),a
        ld a,(note_value)
        ld (IO_BUFFER+1),a
        ld a,(note_velocity)
        ld (IO_BUFFER+2),a
        ld hl,IO_BUFFER
        ld de,3
        call write_all
        ret c

        xor a
        ld (elapsed_lines),a
        ld (elapsed_lines+1),a
        ld (elapsed_lines+2),a
        call read_raster_line
        ld (raster_previous),hl
        ld a,1
        ld (scheduler_active),a
        ld a,(note_seconds)
        ld (note_seconds_left),a
.second:
        ld bc,1000
.millisecond:
        push bc
        call consume_raster_line
        pop bc
        jp c,.cancel
        dec bc
        ld a,b
        or c
        jp nz,.millisecond
        ld a,(note_seconds_left)
        dec a
        ld (note_seconds_left),a
        jp nz,.second
        xor a
        ld (scheduler_active),a
        jp send_note_off
.cancel:
        xor a
        ld (scheduler_active),a
        call send_note_off
        scf
        ret

send_note_off:
        ld a,(note_channel)
        or $80
        ld (IO_BUFFER),a
        ld a,(note_value)
        ld (IO_BUFFER+1),a
        xor a
        ld (IO_BUFFER+2),a
        ld hl,IO_BUFFER
        ld de,3
        jp write_all

write_all:
        ld a,250
        ld (write_idle),a
.loop:
        push hl
        push de
        call account_raster_lines
        pop de
        pop hl
        ld a,d
        or e
        ret z
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_WRITE
        push ix                 ; the event decoder keeps its track pointer here
        rst $08
        db NEXTZXOS_M_DRVAPI
        pop ix
        ld a,$ff                ; do not trust MMU7 after an OS call: the
        ld (rd_mapped),a        ; reader maps its bank again (#14)
        jp c,.transport_failed
        ld a,b
        or c
        jp nz,.progress
        ld a,(scheduler_active)
        or a
        jp z,.wait_frame
        push hl
        push de
        call wait_line
        pop de
        pop hl
        ret c
        push hl
        ld hl,1                 ; the line wait_line left for the caller
        call add_elapsed        ; preserves DE (bytes still to write)
        pop hl
        jp .idle_tick
.wait_frame:
        push hl
        push de
        call wait_frame
        pop de
        pop hl
        ret c
.idle_tick:
        ld a,(write_idle)
        dec a
        ld (write_idle),a
        jp nz,.loop
.transport_failed:              ; driver error or no progress (#51)
        ld a,1
        ld (transport_failed),a
        scf
        ret
.progress:
        ld a,250
        ld (write_idle),a
        jp .loop

cleanup:
        ld a,(file_open)
        or a
        jp z,.no_file
        ld a,(file_handle)
        rst $08
        db F_CLOSE
        xor a
        ld (file_open),a
.no_file:
        ld a,(driver_acquired)
        or a
        jp z,.no_driver
        ld a,(cleanup_midi)
        or a
        jp z,.skip_midi_cleanup
        call close_open_sysex
        call all_notes_off
.skip_midi_cleanup:
        call drain_driver
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_RELEASE
        rst $08
        db NEXTZXOS_M_DRVAPI
        xor a
        ld (driver_acquired),a
.no_driver:
        call restore_mmus
        call free_banks
        call turbo_restore
        ret

; A malformed or interrupted SMF may leave the wire inside a SysEx message.
; Close it on a best-effort basis before channel cleanup bytes are emitted.
close_open_sysex:
        ld a,(sysex_open)
        or a
        ret z
        ld a,$f7
        ld (IO_BUFFER),a
        ld hl,IO_BUFFER
        ld de,1
        call write_all
        xor a
        ld (sysex_open),a
        ret

; Per channel: Sustain off (CC64=0), All Notes Off (CC123=0) and All Sound
; Off (CC120=0). All Notes Off alone respects a held sustain pedal and could
; leave notes sounding after a cancellation (#3). One WRITE per channel.
all_notes_off:
        xor a
        ld (cleanup_channel),a
.loop:
        ld a,(cleanup_channel)
        or $b0
        ld (IO_BUFFER),a
        ld (IO_BUFFER+3),a
        ld (IO_BUFFER+6),a
        ld a,$40
        ld (IO_BUFFER+1),a
        ld a,$7b
        ld (IO_BUFFER+4),a
        ld a,$78
        ld (IO_BUFFER+7),a
        xor a
        ld (IO_BUFFER+2),a
        ld (IO_BUFFER+5),a
        ld (IO_BUFFER+8),a
        ld hl,IO_BUFFER
        ld de,9
        call write_all
        ret c
        ld a,(cleanup_channel)
        inc a
        ld (cleanup_channel),a
        cp 16
        jp c,.loop
        ret

; Before a song: the synth may keep notes from a session cut short (the Next
; switched off mid-note; the mt32-pi has its own supply) or parts left at
; volume 0. Per channel: CC64=0, CC123=0, CC120=0 and CC7=100 (power-on part
; volume), one WRITE of 12 bytes per channel, as the GSEQ library does.
clean_synth:
        xor a
        ld (cleanup_channel),a
.loop:
        ld a,(cleanup_channel)
        or $b0
        ld (IO_BUFFER),a
        ld (IO_BUFFER+3),a
        ld (IO_BUFFER+6),a
        ld (IO_BUFFER+9),a
        ld a,$40
        ld (IO_BUFFER+1),a
        ld a,$7b
        ld (IO_BUFFER+4),a
        ld a,$78
        ld (IO_BUFFER+7),a
        ld a,$07
        ld (IO_BUFFER+10),a
        ld a,100
        ld (IO_BUFFER+11),a
        xor a
        ld (IO_BUFFER+2),a
        ld (IO_BUFFER+5),a
        ld (IO_BUFFER+8),a
        ld hl,IO_BUFFER
        ld de,12
        call write_all
        ret c
        ld a,(cleanup_channel)
        inc a
        ld (cleanup_channel),a
        cp 16
        jp c,.loop
        or a
        ret

RESET_MESSAGES_LENGTH equ 17   ; reset_messages in data.s (SNasm has no $-label)

; Sends the MT-32 "all parameters reset" SysEx (address $7F0000) and GM System
; On, then waits 25 frames: Munt resets at once, a real MT-32 on a joystick
; output needs time. WRITE takes buffers at $4000 or above, hence the copy.
reset_synth:
        ld hl,reset_messages
        ld de,IO_BUFFER
        ld bc,RESET_MESSAGES_LENGTH
        ldir
        ld hl,IO_BUFFER
        ld de,RESET_MESSAGES_LENGTH
        call write_all
        ret c
        ld b,25
.wait:
        ei
        halt
        djnz .wait
        or a
        ret

drain_driver:
        ld de,250
.loop:
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_DRAIN_STATUS
        rst $08
        db NEXTZXOS_M_DRVAPI
        ret c
        ld a,b
        and c
        inc a
        ret z
        ei
        halt
        dec de
        ld a,d
        or e
        jp nz,.loop
        ret

restore_mmus:
        ld a,(mmus_saved)
        or a
        ret z
        ld hl,saved_mmu
        ld d,NXR_MMU4
        ld e,4
.loop:
        ld a,(hl)
        push hl
        push de
        call map_bank
        pop de
        pop hl
        inc hl
        inc d
        dec e
        jp nz,.loop
        ld bc,NEXTREG_SELECT
        ld a,(saved_nextreg_selector)
        out (c),a
        xor a
        ld (mmus_saved),a
        ret

free_banks:
        ld a,(allocated_count)
        or a
        ret z
        ld b,a
        ld hl,file_banks
.loop:
        push bc
        push hl
        ld a,(hl)
        call free_bank
        pop hl
        pop bc
        inc hl
        djnz .loop
        xor a
        ld (allocated_count),a
        ret

; A=8K bank to return to NextZXOS.
free_bank:
        ld e,a
        ld hl,$0003             ; ZX bank, release
        exx
        ld de,IDE_BANK
        ld c,7
        rst $08
        db M_P3DOS
        ret

; HL=zero-terminated text; a PFX byte prints msg_prefix in its place.
print_z:
        ld a,(hl)
        or a
        ret z
        cp PFX
        jr z,.prefix
        rst $10
.next:
        inc hl
        jr print_z
.prefix:
        push hl
        ld hl,msg_prefix
        call print_z
        pop hl
        jr .next
