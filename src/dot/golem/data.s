; golem-next .GOLEM module: Command workspace and messages.
; Included by src/dot/golem_cli.s; not assembled on its own. Uses the
; constants and labels defined there and in the other modules.
;
; Mutable workspace in the dot command area below $4000; the I/O buffer and
; local stack live in the private work bank at $6000 (IO_BUFFER, LOCAL_STACK).

saved_sp:               dw 0
driver_caps:            dw 0
work_bank:              db 0
work_mapped:            db 0
saved_mmu3:             db 0
exit_failed:            db 0
exit_message:           dw 0
command_mode:           db 0
output_choice:          db 0    ; .golem output: MT32_OUTPUT_*, $ff = report
file_handle:            db 0
file_open:              db 0
driver_acquired:        db 0
allocated_count:        db 0
mmus_saved:             db 0
cancelled:              db 0
transport_failed:       db 0
sysex_open:             db 0
sysex_owner:            dw 0
load_index:             db 0
caller_speed:           db 0
speed_saved:            db 0
file_banks:             ds MAX_FILE_BANKS
saved_mmu:              ds 4
saved_nextreg_selector: db 0
file_length:            ds 3
rd_pos:                 ds 3    ; rd_pos and rd_end must stay contiguous
rd_end:                 ds 3
rd_limit:               ds 3
rd_mapped:              db $ff
rd_saved:               ds 3
chunk_length:           ds 3
sysex_left:             dw 0
sysex_last:             db 0
sysex_had_data:         db 0
smf_format:             db 0
track_count:            db 0
tracks_left:            db 0
scan_left:              db 0
best_valid:             db 0
selected_track:         dw 0
division:               dw 0
frame_quantum:          ds 4
refresh_60:             db 0
slice_period:           dw 0
slice_remainder:        dw 0
slice_phase:            dw 0
slice_lines:            db 0
slice_base:             db 0    ; whole lines per ms
raster_lines:           dw 0
measure_max:            dw 0
measure_wraps:          db 0
measure_speed:          db 0
raster_previous:        dw 0
elapsed_lines:          ds 3
scheduler_active:       db 0
tempo:                  ds 4
time_accum:             ds 4
last_tick:              ds 4
delta_ticks:            ds 4
vlq_value:              ds 4
vlq_count:              db 0
vlq_byte:               db 0
event_type:             db 0
event_status:           db 0
write_idle:             db 0
cleanup_channel:        db 0
status_flags:           db 0
status_uart:            db 0    ; raw $133B from STATUS (#17)
cleanup_midi:           db 0
golem_command:          db 0
golem_value:            db 0
golem_value2:           db 0    ; SET_PARAM value
golem_transaction:      db 0
golem_timeout:          dw 0
golem_accepted:         db 0
golem_remote_error:     db 0
golem_read_remaining:   db 0
golem_last_count:       db 0
golem_accept_wait:      db 0
golem_no_answer:        db 0
golem_status:           ds 7
golem_rx_length:        db 0
golem_rx_frame:         ds GOLEM_RX_FRAME_MAX
note_value:             db 0
note_velocity:          db 0
note_seconds:           db 0
note_channel:           db 0
note_seconds_left:      db 0
; The file name is only needed to open the file (load_file), before
; parse_smf fills track_states, so both share the same 288 bytes.
filename:
track_states:           ds MAX_TRACKS*ST_SIZE

msg_usage:
        db $0d,".golem play|note|status|engine|"
        db "rom|soundfont|bank|output|usb|set|save|reset",$0d
        db "Help: .guide golem",$0d,0
; Error reports: the last character carries bit 7 (NextZXOS convention).
err_usage:
        db "Golem: invalid usag",'e'+$80
err_driver:
        db "Golem: GOLEM.DRV missing or incompat",'.'+$80
err_no_rx:
        db "Golem: GOLEM.DRV has no RX (ABI 0.2",')'+$80
err_memory:
        db "Golem: out of mem bank",'s'+$80
err_not_found:
        db "Golem: cannot open fil",'e'+$80
err_too_big:
        db "Golem: MIDI file of 1 MB or mor",'e'+$80
err_file:
        db "Golem: file read erro",'r'+$80
err_midi:
        db "Golem: unsupported SMF (0/1, 24 tracks",')'+$80
err_bad_event:
        db "Golem: invalid SMF even",'t'+$80
err_transport:
        db "Golem: transport error or timeou",'t'+$80
; PFX in a message prints this: a new line and "Golem: " (print_z)
msg_prefix:
        db $0d,"Golem: ",0
msg_loading:
        db PFX,"loading",0
msg_playing:
        db PFX,"playing (SPACE stops)",0
msg_cancelled:
        db PFX,"playback cancelled",$0d,0
msg_done:
        db PFX,"playback finished",$0d,0
msg_note_done:
        db PFX,"note finished",$0d,0
msg_golem_done:
        db PFX,"command accepted and applied",$0d,0
msg_golem_cancelled:
        db PFX,"wait cancelled; command may still apply",$0d,0
err_golem_rejected:
        db "Golem: command rejected by Gole",'m'+$80
err_golem_old:
        db "Golem: firmware too old for comman",'d'+$80
msg_status_free:
        db PFX,"driver OK; session free; ",0
msg_status_busy:
        db PFX,"driver OK; session in use; ",0
msg_status_full:
        db "TX full",0
msg_status_empty:
        db "TX empty",0
msg_status_active:
        db "TX busy",0
msg_status_rx_errors:
        db "; RX errors",0
msg_golem_no_rx:
        db PFX,"not queried (driver has no RX)",$0d,0
msg_golem_busy:
        db PFX,"not queried (session in use)",$0d,0
msg_golem_silent:
        db PFX,"no answer (off or external synth)",$0d,0
msg_golem_query_cancelled:
        db PFX,"query cancelled",$0d,0
msg_gs_engine:
        db PFX,"engine ",0
msg_gs_rom:
        db "; ROM ",0
msg_gs_no_mt32:
        db "; no MT32 ROM",0
msg_gs_bank:
        db "; bank ",0
msg_gs_soundfont:
        db "; SoundFont ",0
msg_gs_no_soundfont:
        db "; no SoundFont",0
msg_crlf:
        db $0d,0
text_engine_mt32:
        db "MT32",0
text_engine_fluidsynth:
        db "FS",0
text_engine_opl3:
        db "OPL3",0
text_engine_none:
        db "none",0
text_unknown:
        db "-",0
; Keyword tails after the first letter, which parse_command dispatches on.
kw_lay:
        db "lay",0
kw_ote:
        db "ote",0
kw_atus:
        db "atus",0
kw_undfont:
        db "undfont",0
kw_ngine:
        db "ngine",0
kw_t32:
        db "t32",0
kw_om:
        db "om",0
text_fluidsynth:
        db "fluidsynth",0
text_opl3:
        db "opl3",0
text_old:
        db "old",0
text_new:
        db "new",0
text_cm32l:
        db "cm32l",0
kw_utput:
        db "utput",0
text_golem:
        db "golem",0
text_left:
        db "left",0
text_right:
        db "right",0
msg_output:
        db PFX,"output ",0
text_output_golem:
        db "Golem (Accel. header)",0
text_output_left:
        db "left joystick port, pin 7",0
text_output_right:
        db "right joystick port, pin 7",0
kw_sb:
        db "sb",0
text_off:
        db "off",0
text_on:
        db "on",0
text_bridge:
        db "bridge",0
kw_eset:
        db "eset",0
kw_ve:
        db "ve",0
text_clear:
        db "clear",0
; .golem set: parameter names in GOLEM_PARAM_* order, then the value words in
; value order (show_set skips to the one it prints).
text_volume:
        db "volume",0
text_fx:
        db "fx",0
text_channels:
        db "channels",0
text_thru:
        db "thru",0
text_keys:
        db "keys",0
text_bank:
        db "bank",0
text_loud:
        db "loud",0
text_std:
        db "std",0
text_alt:
        db "alt",0
reset_messages:
        db $f0,$41,$10,$16,$12,$7f,$00,$00,$00,$01,$f7   ; MT-32: reset all
        db $f0,$7e,$7f,$09,$01,$f7                      ; GM System On
msg_usb:
        db PFX,"USB out ",0
msg_usb_devices:
        db "; USB MIDI devices ",0

binary_end:
