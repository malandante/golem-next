; Golem foreground command: .GOLEM and its aliases .MT32, .GM and .OPL3.
; Included by src/dot/golem.s, mt32.s, gm.s and opl3.s, which set CLI_ENGINE:
;   0  .GOLEM  leaves the synth engine as it is
;   1  .MT32   play/note first ask a Golem for the MT-32 engine
;   2  .GM     play/note first ask a Golem for FluidSynth (General MIDI)
;   3  .OPL3   play/note first ask a Golem for OPL3 FM (General MIDI)
; Without a Golem answer the aliases play anyway (an external synth, #76).
;
; The resident driver remains transport-only.  This command owns the SMF
; parser, track merge, raster scheduler, cancellation and resource cleanup.

        opt zxnext
        include "../../include/mt32_api.inc"
        include "../../include/golem_api.inc"

M_GETSETDRV     equ $89
F_OPEN          equ $9a
F_CLOSE         equ $9b
F_READ          equ $9d
M_P3DOS         equ $94
IDE_BANK        equ $01bd

NEXTREG_SELECT  equ $243b
NEXTREG_DATA    equ $253b
NXR_MMU3        equ $53
NXR_MMU4        equ $54
NXR_MMU7        equ $57
NXR_PERIPHERAL1 equ $05
NXR_TURBO       equ $07
NXR_VIDEO_TIMING equ $11
NXR_RASTER_MSB  equ $1e
NXR_RASTER_LSB  equ $1f

FILE_WINDOW     equ $e000       ; MMU7: the reader's view of the file
LOAD_WINDOW     equ $8000       ; MMU4: where load_file reads each bank (#57)
MAX_FILE_BANKS  equ 128         ; 1 MB
IO_BUFFER       equ $6000       ; inside the private work bank at MMU3
IO_BUFFER_SIZE  equ $100        ; its uses: up to 17 bytes (the reset)
file_banks      equ IO_BUFFER+IO_BUFFER_SIZE    ; MAX_FILE_BANKS bytes
track_states    equ file_banks+MAX_FILE_BANKS   ; MAX_TRACKS x ST_SIZE bytes
LOCAL_STACK     equ $7ff0       ; idem; bank 5 is never written here
MAX_TRACKS      equ 24

LOAD_NOT_OPENED  equ 1
LOAD_TOO_BIG     equ 2
LOAD_READ_FAILED equ 3
LOAD_NO_MEMORY   equ 4

CMD_PLAY        equ 0
CMD_NOTE        equ 1
CMD_STATUS      equ 2
CMD_ENGINE      equ 3
CMD_SOUNDFONT   equ 4
CMD_ROMSET      equ 5
CMD_OUTPUT      equ 6
CMD_USB         equ 7
CMD_RESET       equ 8
CMD_SET         equ 9
CMD_SAVE        equ 10
PFX             equ 1       ; print_z: new line and "Golem: " (msg_prefix)

ST_CURSOR       equ 0           ; 24-bit file offsets (#14)
ST_END          equ 3
ST_TICK         equ 6
ST_STATUS       equ 10
ST_DONE         equ 11
ST_SIZE         equ 12

GOLEM_ACCEPT_FRAMES equ 10      ; .MT32/.GM: wait for ACCEPTED before playing anyway

        org $2000

start:
        ld (saved_sp),sp
        xor a
        ld (work_mapped),a
        ld (file_open),a
        ld (driver_acquired),a
        ld (allocated_count),a
        ld (cancelled),a
        ld (mmus_saved),a
        ld (sysex_open),a
        ld (scheduler_active),a
        ld (cleanup_midi),a
        ld (speed_saved),a

        ; Parse first, on the caller's stack: the command line is part of the
        ; BASIC program and may itself lie in $6000-$7fff.
        call parse_command
        jp nc,error_usage

        ; The I/O buffer and the local stack live in a private 8K bank mapped
        ; at MMU3 ($6000-$7fff) while the command runs. Bank 5 there holds the
        ; BASIC program and variables, which must not be overwritten (#2).
        ; IDE_BANK runs on the caller's stack, which is normal RAM.
        ld bc,NEXTREG_SELECT
        in a,(c)
        ld (saved_nextreg_selector),a
        call allocate_bank
        jp nc,no_work_bank
        ld (work_bank),a
        ld bc,NEXTREG_SELECT
        ld a,NXR_MMU3
        out (c),a
        inc b
        in a,(c)
        ld (saved_mmu3),a
        ld a,(work_bank)
        out (c),a               ; inline: no stack use while MMU3 changes
        dec b
        ld a,(saved_nextreg_selector)
        out (c),a
        ld sp,LOCAL_STACK
        ld a,1
        ld (work_mapped),a

        call query_driver
        jp c,error_driver
        ld a,(command_mode)
        cp CMD_STATUS
        jp z,command_status
        cp CMD_NOTE
        jp z,command_note
        cp CMD_ENGINE
        jp z,command_golem_control
        cp CMD_SOUNDFONT
        jp z,command_golem_control
        cp CMD_ROMSET
        jp z,command_golem_control
        cp CMD_OUTPUT
        jp z,command_output
        cp CMD_USB
        jp z,command_golem_control
        cp CMD_SET
        jp z,command_golem_control
        cp CMD_SAVE
        jp z,command_golem_control
        cp CMD_RESET
        jp z,command_reset

        call turbo_on
        call save_mmus
        ld hl,msg_loading
        call print_z
        call load_file
        jp c,error_load
        call parse_smf
        jp c,error_midi

        call acquire_driver
        ld (cleanup_midi),a
        call select_engine
        jp c,engine_failed
        call clean_synth
        jp c,play_failed
        call reset_synth        ; factory setup first, not the previous
                                ; file's SysEx (#104)
        jp c,play_failed
        ld hl,msg_playing
        call print_z

        call play_smf
        jp c,play_failed
        ld hl,msg_done
        jp exit_success

command_status:
        call show_status
        jp c,error_driver
        call print_output
        call query_golem
        jp c,exit_error
        jp exit_success

; .golem output [golem|left|right] (#64): where the driver sends MIDI from the
; next ACQUIRE on. golem: the Accelerator header (UART and I2S); left/right: pin
; 7 of a joystick port, for an external synth. Without a word it only reports.
command_output:
        ld a,(output_choice)
        cp $ff
        jp z,.show
        ld e,a
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_SET_OUTPUT
        rst $08
        db NEXTZXOS_M_DRVAPI
        jp c,error_driver       ; A=0: driver older than ABI 0.3
        call query_driver
        jp c,error_driver
        call apply_output
.show:
        call print_output
        ld hl,msg_crlf
        jp exit_success

; Applies the output now instead of at the next play. Outside UART mode
; pin 7 of a joystick port carries Mega Drive pad scans (4 x 9 us low every
; ~2.3 ms, measured 2026-10-15) that an external synth could take for MIDI.
; left/right: ACQUIRE writes NextReg $0B and, with a joystick output, RELEASE
; keeps it, so the port stays in UART mode with pin 7 idle high. golem: undo
; that UART mode ($A1/$B1) so the joystick works again; then ACQUIRE/RELEASE
; leave the Pi's audio enabled ($A2), so a keyboard on the Pi sounds (#107).
apply_output:
        ld a,(driver_caps+1)
        or a
        call z,joystick_off
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_ACQUIRE
        rst $08
        db NEXTZXOS_M_DRVAPI
        ret c                   ; session in use: applies at its next ACQUIRE
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_RELEASE
        rst $08
        db NEXTZXOS_M_DRVAPI
        ret
joystick_off:
        ld bc,NEXTREG_SELECT
        in a,(c)
        ld e,a
        ld a,$0b
        out (c),a
        inc b
        in a,(c)
        and $ef                 ; $A1 left or $B1 right
        cp $a1
        jr nz,.keep
        xor a
        out (c),a
.keep:
        dec b
        ld a,e
        out (c),a
        ret

; Prints "; output golem|left|right" from QUERY H (driver_caps+1).
print_output:
        ld hl,msg_output
        call print_z
        ld a,(driver_caps+1)
        ld hl,text_output_golem
        or a
        jp z,.print
        ld hl,text_output_left
        cp MT32_NR0B_LEFT
        jp z,.print
        ld hl,text_output_right
.print:
        jp print_z

; ACQUIRE, or the driver error report. Returns A=1.
acquire_driver:
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_ACQUIRE
        rst $08
        db NEXTZXOS_M_DRVAPI
        jp c,error_driver       ; exit_common restores SP
        ld a,1
        ld (driver_acquired),a
        ret

; .golem reset (#104): MT-32 "all parameters reset" and GM System On.
command_reset:
        call acquire_driver
        call reset_synth
        jp c,error_transport
        ld hl,msg_golem_done
        jp exit_success

command_note:
        call acquire_driver
        ld (cleanup_midi),a
        call select_engine
        jp c,engine_failed
        call play_note
        jp c,play_failed
        ld hl,msg_note_done
        jp exit_success

command_golem_control:
        ld a,(driver_caps)      ; Golem replies need READ (ABI 0.2, #5)
        and MT32_CAP_RX_NONBLOCKING
        jp z,error_no_rx
        call acquire_driver
        ld a,r                   ; vary transaction across separate CLI loads
        and $7f
        ld (golem_transaction),a
        call send_golem_control
        jp nc,.confirmed
        ld a,(cancelled)
        or a
        jp z,.not_cancelled
        ld hl,msg_golem_cancelled
        jp exit_success
.not_cancelled:
        ld a,(golem_remote_error)
        or a
        jp z,error_transport
        ld hl,err_golem_old
        cp GOLEM_ERROR_COMMAND  ; firmware without this command
        jp z,exit_error
        ld hl,err_golem_rejected
        jp exit_error
.confirmed:
        ld a,(command_mode)
        cp CMD_SET
        jr z,.show_set
        cp CMD_USB
        ld hl,msg_golem_done
        jp nz,exit_success

; .golem usb (#85): READY carries the mode and the USB MIDI device count,
; kept in golem_status by validate_golem_frame.
        ld hl,msg_usb
        call print_z
        ld a,(golem_status)
        ld hl,text_off
        or a
        jr z,.usb_mode
        ld hl,text_on
        dec a
        jr z,.usb_mode
        ld hl,text_bridge
.usb_mode:
        call print_z
        ld hl,msg_usb_devices
        call print_z
        ld a,(golem_status+1)
        ld l,a
        ld h,0
        call print_dec
        ld hl,msg_crlf
        jp exit_success

; .golem set: "Golem: <parameter> <value>" from READY (golem_status+1).
.show_set:
        ld hl,msg_prefix
        call print_z
        ld a,(golem_value)      ; parameter
        push af
        ld hl,text_volume
        call skip_z
        call print_z
        ld a,' '
        rst $10
        pop af
        ld hl,text_off          ; off, on
        cp GOLEM_PARAM_CHANNELS
        jr nz,.set_value
        ld hl,text_std          ; std, alt
.set_value:
        cp GOLEM_PARAM_BANK
        jr z,.set_bank
        or a                    ; volume: a number
.set_bank:                      ; Z: volume or bank, a number
        ld a,(golem_status+1)
        jr z,.set_number
        call skip_z
        call print_z
        jr .set_end
.set_number:
        ld l,a
        ld h,0
        call print_dec
.set_end:
        ld hl,msg_crlf
        jp exit_success

; HL past A zero-terminated strings. Uses A, C.
skip_z:
        or a
        ret z
        ld c,a
.next:
        ld a,(hl)
        inc hl
        or a
        jr nz,.next
        dec c
        jr nz,.next
        ret

; .MT32/.GM engine request: rejected, cancelled, or no READY in time.
engine_failed:
        ld a,(golem_remote_error)
        or a
        ld hl,err_golem_rejected
        jp nz,exit_error
        ld a,(cancelled)
        or a
        ld hl,msg_cancelled
        jp nz,exit_success
        jp error_transport

play_failed:
        ld a,(cancelled)
        or a
        jp nz,.cancelled
        ld a,(transport_failed)
        or a
        jp nz,error_transport
        ld hl,err_bad_event      ; anything else is the file's content (#51)
        jp exit_error
.cancelled:
        ld hl,msg_cancelled
        jp exit_success

; Failures are returned to NextZXOS as custom error reports (carry set, A=0,
; HL=text with bit 7 set on its last character), so BASIC stops or an ON ERROR
; handler runs instead of continuing as if the command had worked (#4).
error_usage:
        ld hl,msg_usage
        call print_z            ; syntax help on screen, then the report
        ld hl,err_usage
        jp exit_error
error_driver:
        ld hl,err_driver
        jp exit_error
error_no_rx:
        ld hl,err_no_rx
        jp exit_error
error_memory:
        ld hl,err_memory
        jp exit_error
error_load:
        ld hl,err_not_found
        dec a
        jp z,exit_error
        ld hl,err_too_big
        dec a
        jp z,exit_error
        ld hl,err_file
        dec a
        jp z,exit_error
        ld hl,err_memory
        jp exit_error
error_midi:
        ld hl,err_midi
        jp exit_error
error_transport:
        ld hl,err_transport

; HL=bit-7-terminated error report.
exit_error:
        push hl
        call cleanup
        pop hl
        ld a,1
        jp exit_common

; HL=zero-terminated message printed before a successful return.
exit_success:
        push hl
        call cleanup
        pop hl
        xor a

; Leave the private stack before unmapping it. The order SP first, MMU3 second
; is safe even if the caller's stack is itself inside $6000-$7fff: an interrupt
; in between pushes and pops within the same mapping.
exit_common:
        ld (exit_failed),a
        ld (exit_message),hl
        ld sp,(saved_sp)
        ld a,(work_mapped)
        or a
        jp z,.unmapped
        ld bc,NEXTREG_SELECT
        in a,(c)
        ld e,a
        ld a,NXR_MMU3
        out (c),a
        inc b
        ld a,(saved_mmu3)
        out (c),a
        dec b
        ld a,e
        out (c),a
        xor a
        ld (work_mapped),a
        ld a,(work_bank)
        call free_bank
.unmapped:
        ld hl,(exit_message)
        ld a,(exit_failed)
        or a
        jp nz,.report
        call print_z
        or a
        ret
.report:
        xor a                   ; A=0: custom report text at HL
        scf
        ret

no_work_bank:
        ld hl,err_memory
        ld a,1
        jp exit_common

; Modules, in assembly order. Their order is part of the binary layout.
        include "golem/cli.s"
        include "golem/memory.s"
        include "golem/reader.s"
        include "golem/smf.s"
        include "golem/scheduler.s"
        include "golem/events.s"
        include "golem/golem_client.s"
        include "golem/transport.s"
        include "golem/data.s"
