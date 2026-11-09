; Golem sound-parameter client library (docs/sound-params.md, section 10). MIT
; licence.
;
; Reads and writes the Golem's sound parameters (OPL3 instruments and banks,
; settings) and uploads or downloads whole files (WOPL banks) from a program on
; the Next, through GOLEM.DRV. Include this file from a client; it needs the
; constants of include/mt32_api.inc. It does not acquire GOLEM.DRV: the client
; does ACQUIRE before the first operation and RELEASE at the end.
;
; Nothing waits inside: an operation is started (gp_info, gp_write, gp_read,
; gp_blob_put, gp_blob_get) and finished by gp_update, called once per frame.
; One operation at a time; gp_result says how it went.
;
; Calling rules (all routines):
; - Carry set when a call is refused, with A = GP_ERR_*. Otherwise NC.
; - IX is preserved. IY is never used: the ROM interrupt routine needs it.
;   AF, BC, DE and HL are not preserved.
; - MMU0/MMU1 must hold the ROM during gp_update (GOLEM.DRV requirement), and
;   the 16-byte buffer given to gp_init must be visible between $4000 and
;   $FFFF.
;
; Size: define GP_MAX_DATA (1-256) before including this file: the largest
; read, write or file chunk. Each of the library's three buffers takes
; GP_MAX_DATA plus a seventh plus 24 bytes (64: 286 bytes in all). The Golem
; accepts up to 256.
;
; Writing: by default gp_update sends with GOLEM.DRV WRITE itself. With GSEQ
; playing, its pump must be the only one writing (sound-params.md 10.5): call
; gp_set_sender with HL = gs_send_long, and the library hands its messages to
; GSEQ's queue instead.
;
; Reading: by default gp_update reads the replies with GOLEM.DRV READ (up to
; four READs per call). A client that reads the UART itself (for MIDI input,
; say) passes A = 1 to gp_set_sender and gives every received byte to gp_feed;
; the library takes the Golem replies and ignores everything else.
;
; gp_init      HL = 16-byte driver buffer ($4000-$FFFF). Writes and reads with
;              GOLEM.DRV; no operation in progress.
; gp_set_sender
;              HL = 0 (WRITE) or a routine that takes a message (HL = start,
;              DE = length; DE = 0 asks only) and returns carry while the
;              previous one is still being sent, like gs_send_long.
;              A = 1: the client reads and calls gp_feed; 0: gp_update reads.
; gp_info      A = page (0: numbers, 1: name), HL = destination, B = its size.
;              GET_INFO; the page's bytes (without page number and checksum)
;              go to the destination, cut to its size. gp_result HL = bytes.
; gp_write     HL = request block (GP_REQ_*): PARAM_WRITE of 1-GP_MAX_DATA
;              7-bit bytes. Without GP_FLAG_CONFIRM it is done once sent.
; gp_read      HL = request block: PARAM_READ into the data address.
; gp_blob_put  HL = file block (GP_FILE_*): uploads a file (BLOB) kept in 8K
;              banks, in chunks of GP_MAX_DATA, each confirmed.
; gp_blob_get  HL = file block: downloads a file into the banks. The size field
;              is the room available; gp_result C:HL = the file's size.
; gp_update    B = how many WRITEs of up to 16 bytes this call may make (0
;              counts as 1). Receives, sends and counts the time out. Once per
;              frame. Out: A = state (GP_*).
; gp_feed      A = one byte received from the UART (with gp_set_sender A = 1).
; gp_result    Out: A = state, B = error (GP_ERR_* or the Golem's code),
;              DE = detail (position of the refused byte, $3FFF if none),
;              C:HL = bytes done (24 bits: files reach 512K).

GP_IDLE         equ 0           ; nothing started
GP_BUSY         equ 1
GP_DONE         equ 2
GP_FAILED       equ 3

; Errors of the library; below $20 they are the Golem's (sound-params.md 3.5):
; $04 value, $05 unavailable, $07 checksum, $08 address, $09 too long,
; $0A busy, $0B sequence...
GP_ERR_TIMEOUT  equ $20         ; no reply in time
GP_ERR_DRIVER   equ $21         ; GOLEM.DRV refused a WRITE or READ
GP_ERR_SIZE     equ $22         ; length 0 or above GP_MAX_DATA, or file too big
GP_ERR_BUSY     equ $23         ; an operation is in progress
GP_ERR_REPLY    equ $24         ; a reply that does not fit the request
GP_ERR_VALUE    equ $25         ; a byte above 127 in a PARAM_WRITE

; Areas (sound-params.md 3.2)
GP_AREA_MT32        equ $00     ; Roland's addresses, a2 << 14 | a1 << 7 | a0
GP_AREA_OPL3_INSTR  equ $01     ; bank << 14 | program << 7 | offset; 128 bytes each
GP_AREA_OPL3_BANKS  equ $02
GP_AREA_MT32_ROM    equ $04     ; ROM timbre n at n << 8, 256 bytes each; read-only
GP_AREA_SETTINGS    equ $10     ; section << 14 | parameter

GP_FILE_WOPL        equ $01     ; BLOB type: OPL3 bank, WOPL or WOPLX
GP_FILE_FX          equ $03     ; BLOB type: FluidSynth effects profile (.CFG text)
GP_FILE_MT32        equ $04     ; BLOB type: MT-32 dump, DT1 messages (.SYX)

; Request block for gp_write and gp_read
GP_REQ_AREA     equ 0           ; 1 byte
GP_REQ_ADDRESS  equ 1           ; 3 bytes, little endian (21 bits used)
GP_REQ_DATA     equ 4           ; 2 bytes: source (write) or destination (read)
GP_REQ_LENGTH   equ 6           ; 2 bytes: 1-GP_MAX_DATA
GP_REQ_FLAGS    equ 8           ; 1 byte: GP_FLAG_CONFIRM (write only)
GP_REQ_SIZE     equ 9
GP_FLAG_CONFIRM equ $01

; File block for gp_blob_put and gp_blob_get. The file lives in 8K banks, as a
; GSEQ sequence: a table with the number of banks and then their numbers, and
; where the file starts in the first bank. The banks are paged in through the
; MMU slot given (NextReg $50-$57), which is restored afterwards.
GP_FILE_TYPE    equ 0           ; GP_FILE_*
GP_FILE_SLOT    equ 1           ; target or origin: 0 the working one
GP_FILE_SIZE    equ 2           ; 3 bytes: file size (put), room (get); up to 2M
GP_FILE_BANKS   equ 5           ; 2 bytes: bank table (up to 255 banks)
GP_FILE_OFFSET  equ 7           ; 2 bytes: 0-8191
GP_FILE_MMU     equ 9           ; 1 byte: $50-$57
GP_FILE_BLOCK   equ 10

GP_TIMEOUT_FAST equ 25          ; frames: a reply, plus up to 300 bytes on the cable
GP_TIMEOUT_SLOW equ 1500        ; BLOB END: the Golem builds the new bank

GP_FRAME_SIZE   equ GP_MAX_DATA + (GP_MAX_DATA + 6) / 7 + 24

GP_CMD_INFO     equ $07
GP_CMD_WRITE    equ $08
GP_CMD_READ     equ $09
GP_CMD_BLOB     equ $0c
GP_R_ACCEPTED   equ $40
GP_R_READY      equ $41
GP_R_ERROR      equ $42
GP_R_INFO       equ $44
GP_R_DATA       equ $45

GP_STEP_NONE    equ 0
GP_STEP_INFO    equ 1
GP_STEP_WRITE   equ 2
GP_STEP_READ    equ 3
GP_STEP_BEGIN   equ 4
GP_STEP_CHUNK   equ 5
GP_STEP_END     equ 6
GP_STEP_SIZE    equ 7
GP_STEP_GET     equ 8

GP_NEXTREG_SELECT equ $243b
GP_NEXTREG_ACCESS equ $253b

; ---------------------------------------------------------------------------
gp_init:
        ld (gp_io),hl
        ld hl,0
        ld (gp_sender),hl
        xor a
        ld (gp_external),a
        ld (gp_rx_on),a
        ld a,$20
        ld (gp_tt),a
        jp gp_reset_op

gp_set_sender:
        ld (gp_sender),hl
        ld (gp_external),a
        or a
        ret

gp_result:
        ld hl,(gp_detail)
        ex de,hl
        ld a,(gp_count+2)
        ld c,a
        ld hl,(gp_count)
        ld a,(gp_error)
        ld b,a
        ld a,(gp_status)
        or a
        ret

; ---------------------------------------------------------------------------
; Operations

gp_info:
        ld c,a
        ld (gp_dest),hl
        ld a,b
        ld (gp_dest_size),a
        push bc
        call gp_check_free
        pop bc
        ret c
        ld a,GP_STEP_INFO
        ld (gp_step),a
        xor a
        ld (gp_flags),a
        push bc
        ld a,GP_CMD_INFO
        call gp_frame_start
        pop bc
        ld a,c
        and $7f
        call gp_put
        jp gp_frame_end

gp_write:
        ld (gp_req),hl
        call gp_check_free
        ret c
        call gp_check_length              ; BC = length, checked
        ret c
        ld hl,(gp_req)
        ld de,GP_REQ_DATA
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl                        ; HL = data
        push hl
        push bc
.check: ld a,(hl)
        inc hl
        bit 7,a
        jr nz,.value
        dec bc
        ld a,b
        or c
        jr nz,.check
        ld hl,(gp_req)
        ld de,GP_REQ_FLAGS
        add hl,de
        ld a,(hl)
        and GP_FLAG_CONFIRM
        ld (gp_flags),a
        ld a,GP_STEP_WRITE
        ld (gp_step),a
        ld a,GP_CMD_WRITE
        call gp_area_address            ; header, flags, area, address
        pop bc
        pop hl
.data:  ld a,(hl)
        inc hl
        call gp_put
        dec bc
        ld a,b
        or c
        jr nz,.data
        jp gp_frame_end
.value: pop bc
        pop hl
        ld a,GP_ERR_VALUE
        scf
        ret

gp_read:
        ld (gp_req),hl
        call gp_check_free
        ret c
        call gp_check_length
        ret c
        ld (gp_len),bc
        ld hl,(gp_req)
        ld de,GP_REQ_DATA
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (gp_dest),de
        xor a
        ld (gp_flags),a
        ld a,GP_STEP_READ
        ld (gp_step),a
        ld a,GP_CMD_READ
        call gp_area_address
        ld hl,(gp_len)
        call gp_put14
        jp gp_frame_end

gp_blob_put:
        ld (gp_req),hl
        call gp_check_free
        ret c
        call gp_file_bytes              ; A:HL = size
        ld (gp_size),hl
        ld (gp_size+2),a
        or h
        or l
        jp z,gp_size_error
        xor a
        ld (gp_flags),a
        ld a,GP_STEP_BEGIN
        ld (gp_step),a
        ld a,GP_CMD_BLOB
        call gp_frame_start
        xor a                           ; BEGIN
        call gp_put
        call gp_file_type_slot
        ld hl,(gp_size)
        ld a,(gp_size+2)
        call gp_put21
        jp gp_frame_end

gp_blob_get:
        ld (gp_req),hl
        call gp_check_free
        ret c
        xor a
        ld (gp_flags),a
        ld a,GP_STEP_SIZE
        ld (gp_step),a
        ld a,GP_CMD_BLOB
        call gp_frame_start
        ld a,4                          ; READ, length 0: the size
        call gp_put
        call gp_file_type_slot
        xor a
        ld h,a
        ld l,a
        call gp_put21
        ld hl,0
        call gp_put14
        jp gp_frame_end

; ---------------------------------------------------------------------------
; gp_update: B = WRITE budget
gp_update:
        push ix
        ld a,b
        or a
        jr nz,.budget
        inc a
.budget:
        ld (gp_budget),a
        ld a,(gp_external)
        or a
        call z,gp_receive
        jr c,.driver
        call gp_send
        jr c,.driver
        ld a,(gp_status)                ; time out while waiting for a reply
        cp GP_BUSY
        jr nz,.out
        ld a,(gp_waiting)
        or a
        jr z,.out
        ld hl,(gp_timer)
        dec hl
        ld (gp_timer),hl
        ld a,h
        or l
        jr nz,.out
        ld a,GP_ERR_TIMEOUT
        call gp_fail
.out:   pop ix
        ld a,(gp_status)
        or a
        ret
.driver:
        ld a,GP_ERR_DRIVER
        call gp_fail
        jr .out

; Up to four READs, while each one fills the buffer. Carry: driver error.
gp_receive:
        ld a,4
        ld (gp_reads),a
.read:  ld hl,(gp_io)
        push hl
        pop ix                          ; HL in a dot command, IX in a program
        ld de,MT32_MAX_READ
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_READ
        rst $08
        db NEXTZXOS_M_DRVAPI
        ret c
        ld a,c
        or a
        ret z
        ld (gp_got),a
        ld b,a
        ld hl,(gp_io)
.byte:  ld a,(hl)
        inc hl
        push bc
        push hl
        call gp_feed
        pop hl
        pop bc
        djnz .byte
        ld a,(gp_got)
        cp MT32_MAX_READ
        jr nz,.done
        ld hl,gp_reads
        dec (hl)
        jr nz,.read
.done:  or a
        ret

; Sends what is pending. Carry: driver error.
gp_send:
        ld a,(gp_status)
        cp GP_BUSY
        jp nz,gp_nc
        ld a,(gp_waiting)
        or a
        jp nz,gp_nc
        ld hl,(gp_sender)
        ld a,h
        or l
        jr nz,.hook
.own:   ld hl,(gp_tx_len)
        ld de,(gp_tx_sent)
        or a
        sbc hl,de
        jr z,gp_sent
        ld a,h
        or a
        ld a,MT32_MAX_WRITE
        jr nz,.count
        ld a,l
        cp MT32_MAX_WRITE
        jr c,.count
        ld a,MT32_MAX_WRITE
.count: ld (gp_wlen),a
        ld c,a
        ld b,0
        ld hl,gp_tx
        add hl,de
        ld de,(gp_io)
        ldir
        ld a,(gp_wlen)
        ld e,a
        ld d,0
        ld hl,(gp_io)
        push hl
        pop ix                          ; NextZXOS takes HL in a dot command, IX
        ld c,MT32_DRIVER_ID             ; in a program
        ld b,MT32_FN_WRITE
        rst $08
        db NEXTZXOS_M_DRVAPI
        ret c
        ld b,0
        ld hl,(gp_tx_sent)
        add hl,bc
        ld (gp_tx_sent),hl
        ld a,(gp_wlen)
        cp c
        jp nz,gp_nc                     ; the driver took part: more next frame
        ld hl,gp_budget
        dec (hl)
        jr nz,.own
        ld hl,(gp_tx_len)               ; budget spent: finished only if all out
        ld de,(gp_tx_sent)
        or a
        sbc hl,de
        jr z,gp_sent
        jp gp_nc
.hook:  ld a,(gp_tx_handed)
        or a
        jr nz,.handed
        ld hl,(gp_tx_len)
        ex de,hl
        ld hl,gp_tx
        call gp_call_sender             ; carry: the queue is busy, try later
        jp c,gp_nc
        ld a,1
        ld (gp_tx_handed),a
.handed:
        ld de,0                         ; still being sent?
        ld hl,gp_tx
        call gp_call_sender
        jp c,gp_nc
gp_sent:                                ; the request is out: wait for its reply
        ld a,(gp_step)
        cp GP_STEP_WRITE
        jr nz,.wait
        ld a,(gp_flags)                 ; an unconfirmed write has no reply
        or a
        jr nz,.wait
        ld hl,(gp_len)
        ld (gp_count),hl
        call gp_finish
        jp gp_nc
.wait:  ld a,1
        ld (gp_waiting),a
        ld hl,GP_TIMEOUT_FAST
        ld a,(gp_step)
        cp GP_STEP_END
        jr nz,.timer
        ld hl,GP_TIMEOUT_SLOW
.timer: ld (gp_timer),hl
gp_nc:  or a
        ret

gp_call_sender:
        push hl
        ld hl,(gp_sender)
        ex (sp),hl
        ret

; ---------------------------------------------------------------------------
; gp_feed: A = a received byte. Keeps the Golem replies only.
gp_feed:
        cp $f8
        jp nc,gp_nc                     ; real time
        cp $f0
        jr nz,.not_start
        ld hl,0
        ld (gp_rx_len),hl
        ld a,1
        ld (gp_rx_on),a
        ld c,$f0
        jr gp_rx_store
.not_start:
        ld c,a
        ld a,(gp_rx_on)
        or a
        ret z
        ld a,c
        cp $f7
        jr z,.end
        bit 7,a
        jr nz,gp_rx_drop                ; another status: not a Golem reply
        jr gp_rx_store
.end:   call gp_rx_store
        ld a,(gp_rx_on)
        or a
        ret z
        xor a
        ld (gp_rx_on),a
        jp gp_frame

gp_rx_store:                            ; C = byte
        ld hl,(gp_rx_len)
        ld de,GP_FRAME_SIZE
        push hl
        or a
        sbc hl,de
        pop hl
        jr nc,gp_rx_drop                ; too long for the buffer
        ld a,h
        or a
        jr nz,.keep
        ld a,l
        cp 6
        jr nc,.keep
        ld e,l                          ; the first six bytes: F0 7D 47 4C 4D 01
        ld d,0
        push hl
        ld hl,gp_header
        add hl,de
        ld a,(hl)
        pop hl
        cp c
        jr nz,gp_rx_drop
.keep:  push hl
        ld de,gp_rx
        add hl,de
        ld (hl),c
        pop hl
        inc hl
        ld (gp_rx_len),hl
        or a
        ret
gp_rx_drop:
        xor a
        ld (gp_rx_on),a
        ret

; A whole Golem frame in gp_rx: F0 7D 47 4C 4D 01 tt rr cc payload F7
gp_frame:
        ld a,(gp_status)
        cp GP_BUSY
        ret nz
        ld hl,(gp_rx_len)
        ld de,10
        or a
        sbc hl,de
        ret c
        ld (gp_plen),hl
        ld a,(gp_rx+6)
        ld hl,gp_tt
        cp (hl)
        ret nz
        ld a,(gp_rx+8)
        ld hl,gp_cmd
        cp (hl)
        ret nz
        ld a,(gp_rx+7)
        ld (gp_resp),a
        cp GP_R_ERROR
        jr z,gp_got_error
        ld a,(gp_step)
        cp GP_STEP_INFO
        jp z,gp_got_info
        cp GP_STEP_WRITE
        jp z,gp_got_write
        cp GP_STEP_READ
        jp z,gp_got_read
        cp GP_STEP_BEGIN
        jp z,gp_got_begin
        cp GP_STEP_CHUNK
        jp z,gp_got_chunk
        cp GP_STEP_END
        jp z,gp_got_end
        cp GP_STEP_SIZE
        jp z,gp_got_size
        cp GP_STEP_GET
        jp z,gp_got_get
        ret

gp_got_error:
        ld hl,(gp_plen)
        ld a,h
        or l
        jr z,gp_bad_reply
        ld a,l
        cp 3
        jr c,.code
        ld hl,gp_rx+10
        call gp_get14
        ld (gp_detail),de
.code:  ld a,(gp_rx+9)
        jp gp_fail

gp_bad_reply:
        ld a,GP_ERR_REPLY
        jp gp_fail

gp_got_info:
        ld a,(gp_resp)
        cp GP_R_INFO
        jr nz,gp_bad_reply
        call gp_payload_cs
        jr c,gp_bad_reply
        ld bc,(gp_plen)                 ; page, data, checksum
        dec bc
        dec bc
        bit 7,b
        jr nz,gp_bad_reply
        ld a,(gp_dest_size)
        ld l,a
        ld h,0
        or a
        sbc hl,bc
        jr nc,.fits
        ld c,a
        ld b,0
.fits:  ld (gp_count),bc
        ld a,b
        or c
        jr z,.done
        ld hl,gp_rx+10
        ld de,(gp_dest)
        ldir
.done:  jp gp_finish

gp_got_write:
        ld a,(gp_resp)
        cp GP_R_READY
        jr nz,gp_bad_reply
        ld hl,(gp_len)
        ld (gp_count),hl
        jp gp_finish

gp_got_read:
        ld a,(gp_resp)
        cp GP_R_DATA
        jr nz,gp_bad_reply
        call gp_payload_cs
        jr c,gp_bad_reply
        ld hl,(gp_plen)                 ; area, address (3), data, checksum
        ld de,5
        or a
        sbc hl,de
        ld de,(gp_len)
        or a
        sbc hl,de
        jr nz,gp_bad_reply
        ld (gp_count),de
        ld b,d
        ld c,e
        ld hl,gp_rx+13
        ld de,(gp_dest)
        ldir
        jp gp_finish

gp_got_begin:
        ld a,(gp_resp)
        cp GP_R_READY
        jp nz,gp_bad_reply
        ld a,(gp_rx+9)
        or a
        jp nz,gp_bad_reply
        call gp_pos_zero
        ld hl,0
        ld (gp_seq),hl
        jp gp_send_chunk

gp_got_chunk:
        ld a,(gp_resp)
        cp GP_R_READY
        jp nz,gp_bad_reply
        ld a,(gp_rx+9)
        cp 1
        jp nz,gp_bad_reply
        ld hl,gp_rx+10
        call gp_get14
        ld hl,(gp_seq)
        or a
        sbc hl,de
        jp nz,gp_bad_reply
        inc de
        ld (gp_seq),de
        call gp_pos_advance             ; also bytes done
        call gp_pos_at_end
        jp nz,gp_send_chunk
        xor a                           ; all sent: END
        ld (gp_flags),a
        ld a,GP_STEP_END
        ld (gp_step),a
        ld a,GP_CMD_BLOB
        call gp_frame_start
        ld a,2
        call gp_put
        jp gp_frame_end

gp_got_end:
        ld a,(gp_resp)
        cp GP_R_ACCEPTED
        jr nz,.ready
        ld hl,GP_TIMEOUT_SLOW           ; the Golem is building the bank
        ld (gp_timer),hl
        ret
.ready: cp GP_R_READY
        jp nz,gp_bad_reply
        ld a,(gp_rx+9)
        cp 2
        jp nz,gp_bad_reply
        jp gp_finish

gp_got_size:
        ld a,(gp_resp)
        cp GP_R_DATA
        jp nz,gp_bad_reply
        call gp_payload_cs
        jp c,gp_bad_reply
        ld a,(gp_rx+9)
        cp 4
        jp nz,gp_bad_reply
        ld hl,gp_rx+10
        call gp_get21                   ; A:DE = size
        ld (gp_size),de
        ld (gp_size+2),a
        ld (gp_count),de
        ld (gp_count+2),a
        ld c,a
        push de
        call gp_file_bytes              ; A:HL = room
        pop de
        or a                            ; (keeps A)
        sbc hl,de
        sbc a,c
        jp c,gp_size_fail
        call gp_pos_zero
        call gp_pos_at_end              ; an empty file
        jp z,gp_finish
        jp gp_send_get

gp_got_get:
        ld a,(gp_resp)
        cp GP_R_DATA
        jp nz,gp_bad_reply
        call gp_payload_cs
        jp c,gp_bad_reply
        ld a,(gp_rx+9)
        cp 4
        jp nz,gp_bad_reply
        ld hl,gp_rx+10
        call gp_get21                   ; A:DE = the position it answers
        ld hl,gp_pos+2
        cp (hl)
        jp nz,gp_bad_reply
        ld hl,(gp_pos)
        or a
        sbc hl,de
        jp nz,gp_bad_reply
        ld hl,(gp_plen)                 ; 04, position (3), packed, checksum
        ld de,5
        or a
        sbc hl,de
        ld b,h
        ld c,l
        ld hl,gp_rx+13
        call gp_unpack                  ; DE = bytes
        jp c,gp_bad_reply
        ld hl,(gp_chunk_len)
        or a
        sbc hl,de
        jp nz,gp_bad_reply
        ld b,d
        ld c,e
        ld a,1                          ; gp_tmp -> banks
        call gp_bank_xfer
        jp c,gp_size_fail
        ld hl,(gp_count)                ; bytes done: the size, kept
        push hl
        ld a,(gp_count+2)
        push af
        call gp_pos_advance
        pop af
        ld (gp_count+2),a
        pop hl
        ld (gp_count),hl
        call gp_pos_at_end
        jp z,gp_finish
        jp gp_send_get

; Next chunk of an upload: from the banks, packed, confirmed
gp_send_chunk:
        call gp_next_chunk_len          ; BC
        ld a,0                          ; banks -> gp_tmp
        call gp_bank_xfer
        jp c,gp_size_fail
        ld a,GP_FLAG_CONFIRM
        ld (gp_flags),a
        ld a,GP_STEP_CHUNK
        ld (gp_step),a
        ld a,GP_CMD_BLOB
        call gp_frame_start
        ld a,1
        call gp_put
        ld hl,(gp_seq)
        call gp_put14
        ld hl,gp_tmp
        ld bc,(gp_chunk_len)
        call gp_put_packed
        jp gp_frame_end

; Next chunk of a download: BLOB READ at the position
gp_send_get:
        call gp_next_chunk_len
        xor a
        ld (gp_flags),a
        ld a,GP_STEP_GET
        ld (gp_step),a
        ld a,GP_CMD_BLOB
        call gp_frame_start
        ld a,4
        call gp_put
        call gp_file_type_slot
        ld hl,(gp_pos)
        ld a,(gp_pos+2)
        call gp_put21
        ld hl,(gp_chunk_len)
        call gp_put14
        jp gp_frame_end

; BC = min(GP_MAX_DATA, size - pos), also in gp_chunk_len
gp_next_chunk_len:
        ld hl,(gp_size)
        ld de,(gp_pos)
        or a
        sbc hl,de                       ; low 16 bits of what is left
        ld a,(gp_pos+2)                 ; (loads keep the borrow)
        ld e,a
        ld a,(gp_size+2)
        sbc a,e
        jr nz,.max                      ; 64K or more left
        push hl
        ld de,GP_MAX_DATA
        or a
        sbc hl,de
        pop hl
        jr c,.left
.max:   ld hl,GP_MAX_DATA
.left:  ld (gp_chunk_len),hl
        ld b,h
        ld c,l
        ret

; The file position: zero; plus the chunk (also the bytes done); Z at the end
gp_pos_zero:
        ld hl,0
        ld (gp_pos),hl
        xor a
        ld (gp_pos+2),a
        ret

gp_pos_advance:
        ld hl,(gp_pos)
        ld de,(gp_chunk_len)
        add hl,de
        ld (gp_pos),hl
        ld (gp_count),hl
        ld a,(gp_pos+2)
        adc a,0
        ld (gp_pos+2),a
        ld (gp_count+2),a
        ret

gp_pos_at_end:
        ld hl,(gp_pos)
        ld de,(gp_size)
        or a
        sbc hl,de
        ret nz
        ld a,(gp_size+2)
        ld hl,gp_pos+2
        cp (hl)
        ret

gp_size_fail:
        ld a,GP_ERR_SIZE
        jp gp_fail

gp_finish:
        ld a,GP_DONE
        ld (gp_status),a
        xor a
        ld (gp_waiting),a
        ld (gp_step),a
        ret

gp_fail:                                ; A = error
        ld (gp_error),a
        ld a,GP_FAILED
        ld (gp_status),a
        xor a
        ld (gp_waiting),a
        ld (gp_step),a
        ret

; ---------------------------------------------------------------------------
; Helpers

gp_check_free:
        ld a,(gp_status)
        cp GP_BUSY
        jr z,.busy
        call gp_reset_op
        or a
        ret
.busy:  ld a,GP_ERR_BUSY
        scf
        ret

gp_reset_op:
        xor a
        ld (gp_step),a
        ld (gp_status),a
        ld (gp_error),a
        ld (gp_waiting),a
        ld (gp_tx_handed),a
        ld hl,0
        ld (gp_tx_len),hl
        ld (gp_tx_sent),hl
        ld (gp_count),hl
        ld (gp_count+2),a
        ld (gp_len),hl
        ld hl,$3fff
        ld (gp_detail),hl
        or a
        ret

gp_size_error:
        ld a,GP_ERR_SIZE
        scf
        ret

; BC = the request's length, carry (A = GP_ERR_SIZE) if 0 or above GP_MAX_DATA
gp_check_length:
        ld hl,(gp_req)
        ld de,GP_REQ_LENGTH
        add hl,de
        ld c,(hl)
        inc hl
        ld b,(hl)
        ld (gp_len),bc
        ld a,b
        or c
        jr z,gp_size_error
        ld hl,GP_MAX_DATA
        or a
        sbc hl,bc
        jr c,gp_size_error
        ret

; A:HL = the file block's size field (24 bits). DE is not kept.
gp_file_bytes:
        ld hl,(gp_req)
        inc hl
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,(hl)
        ex de,hl
        ret

gp_file_type_slot:
        ld hl,(gp_req)
        ld a,(hl)
        and $7f
        call gp_put
        inc hl
        ld a,(hl)
        and $7f
        jp gp_put

; A = command. Header, area and address of the request block.
gp_area_address:
        call gp_frame_start
        ld hl,(gp_req)
        ld a,(hl)
        and $7f
        call gp_put
        inc hl
        ld c,(hl)                       ; address, little endian
        inc hl
        ld b,(hl)
        inc hl
        ld e,(hl)
        ld a,b                          ; a2 = bits 14-20
        rlca
        rlca
        and 3
        ld d,a
        ld a,e
        add a,a
        add a,a
        or d
        and $7f
        call gp_put
        ld a,c                          ; a1 = bits 7-13
        rlca
        and 1
        ld d,a
        ld a,b
        add a,a
        or d
        and $7f
        call gp_put
        ld a,c                          ; a0
        and $7f
        jp gp_put

; A = command: F0 7D 47 4C 4D 01 tt cc flags (a new transaction)
gp_frame_start:
        ld (gp_cmd),a
        ld hl,gp_header
        ld de,gp_tx
        ld bc,6
        ldir
        ld a,(gp_tt)
        inc a
        and $7f
        ld (gp_tt),a
        ld (de),a
        inc de
        ld a,(gp_cmd)
        ld (de),a
        inc de
        ld a,(gp_flags)
        ld (de),a
        inc de
        ld (gp_sum),a
        ld (gp_wp),de
        ret

; A = a 7-bit byte, appended and added to the checksum. Keeps BC, DE, HL.
gp_put:
        push hl
        ld hl,(gp_wp)
        ld (hl),a
        inc hl
        ld (gp_wp),hl
        ld hl,gp_sum
        add a,(hl)
        ld (hl),a
        pop hl
        ret

; HL = 14-bit value: low 7 bits, then high 7 bits
gp_put14:
        ld a,l
        and $7f
        call gp_put
        ld a,l
        rlca
        and 1
        ld e,a
        ld a,h
        add a,a
        or e
        and $7f
        jp gp_put

; A:HL = a 21-bit value: a2 a1 a0
gp_put21:
        add a,a
        add a,a
        ld e,a
        ld a,h
        rlca
        rlca
        and 3
        or e
        and $7f
        call gp_put
        ld a,l
        rlca
        and 1
        ld e,a
        ld a,h
        add a,a
        or e
        and $7f
        call gp_put
        ld a,l
        and $7f
        jp gp_put

; Checksum, F7: the request is ready to go
gp_frame_end:
        ld a,(gp_sum)
        neg
        and $7f
        ld hl,(gp_wp)
        ld (hl),a
        inc hl
        ld (hl),$f7
        inc hl
        ld de,gp_tx
        or a
        sbc hl,de
        ld (gp_tx_len),hl
        ld hl,0
        ld (gp_tx_sent),hl
        xor a
        ld (gp_tx_handed),a
        ld (gp_waiting),a
        ld a,GP_BUSY
        ld (gp_status),a
        or a
        ret

; HL = source, BC = count: 7 in 8 (a byte with the high bits, then up to 7)
gp_put_packed:
        ld a,b
        or c
        ret z
        ld a,b
        or a
        ld a,7
        jr nz,.group
        ld a,c
        cp 7
        jr c,.group
        ld a,7
.group: ld (gp_group),a
        push bc
        push hl
        ld b,a
        ld d,0
        ld e,1
.high:  ld a,(hl)
        inc hl
        bit 7,a
        jr z,.next
        ld a,d
        or e
        ld d,a
.next:  sla e
        djnz .high
        ld a,d
        call gp_put
        pop hl
        ld a,(gp_group)
        ld b,a
.low:   ld a,(hl)
        inc hl
        and $7f
        call gp_put
        djnz .low
        pop bc
        ld a,c
        ld e,a
        ld a,(gp_group)
        ld d,a
        ld a,e
        sub d
        ld c,a
        ld a,b
        sbc a,0
        ld b,a
        jr gp_put_packed

; HL = packed bytes, BC = their count. Out: gp_tmp, DE = bytes; carry if
; malformed or longer than GP_MAX_DATA.
gp_unpack:
        ld de,gp_tmp
.group: ld a,b
        or c
        jr z,.end
        ld a,(hl)
        inc hl
        dec bc
        ld (gp_hibits),a
        ld a,b
        or c
        scf
        ret z                           ; high bits with no bytes
        ld a,b
        or a
        ld a,7
        jr nz,.count
        ld a,c
        cp 7
        jr c,.count
        ld a,7
.count: ld (gp_group),a
        push bc
        ld b,a
.byte:  push hl                         ; room left?
        ld hl,gp_tmp+GP_FRAME_SIZE
        or a
        sbc hl,de
        pop hl
        jr z,.over
        ld a,(gp_hibits)
        rrca
        ld (gp_hibits),a
        ld a,(hl)
        inc hl
        jr nc,.low
        or $80
.low:   ld (de),a
        inc de
        djnz .byte
        pop bc
        ld a,(gp_group)
        ld (gp_hibits),a
        ld a,c
        push hl
        ld hl,gp_hibits
        sub (hl)
        pop hl
        ld c,a
        ld a,b
        sbc a,0
        ld b,a
        jr .group
.over:  pop bc
        scf
        ret
.end:   ex de,hl
        ld de,gp_tmp
        or a
        sbc hl,de
        ex de,hl
        push hl
        ld hl,GP_MAX_DATA
        or a
        sbc hl,de
        pop hl
        ret

; HL = 7-bit low, 7-bit high. Out: DE (14 bits).
gp_get14:
        ld e,(hl)
        inc hl
        ld d,(hl)
        srl d
        ret nc
        set 7,e
        or a
        ret

; HL = a2 a1 a0. Out: A:DE, the 21-bit value (A = bits 16-20).
gp_get21:
        ld a,(hl)
        inc hl
        push af
        rrca
        rrca
        and $c0
        ld d,a
        ld a,(hl)
        inc hl
        ld b,a
        srl a
        or d
        ld d,a
        ld e,(hl)
        bit 0,b
        jr z,.high
        set 7,e
.high:  pop af
        rrca
        rrca
        and $1f
        ret

; Sum of the reply's payload (checksum included) must be a multiple of 128.
; Carry if not, or empty.
gp_payload_cs:
        ld bc,(gp_plen)
        ld a,b
        or c
        scf
        ret z
        ld hl,gp_rx+9
        ld d,0
.add:   ld a,d
        add a,(hl)
        ld d,a
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,.add
        ld a,d
        and $7f
        ret z
        scf
        ret

; Copies BC bytes between the file, at position gp_pos, and gp_tmp.
; A = 0: file to gp_tmp; 1: gp_tmp to file. Carry if past the last bank.
gp_bank_xfer:
        ld (gp_dir),a
        ld (gp_left),bc
        ld hl,(gp_req)                  ; the MMU slot and its window
        ld de,GP_FILE_MMU
        add hl,de
        ld a,(hl)
        ld (gp_mmu),a
        sub $50
        rrca
        rrca
        rrca
        and $e0
        ld (gp_window),a
        ld bc,GP_NEXTREG_SELECT         ; keep what the slot holds
        ld a,(gp_mmu)
        out (c),a
        ld bc,GP_NEXTREG_ACCESS
        in a,(c)
        ld (gp_mmu_saved),a
        ld hl,(gp_req)                  ; offset + position: bank and place
        ld de,GP_FILE_OFFSET
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld hl,(gp_pos)
        add hl,de                       ; offset + position: bits 0-15
        ld a,(gp_pos+2)
        adc a,0                         ; bits 16-23
        cp $20
        jp nc,.past                     ; beyond 255 banks
        add a,a
        add a,a
        add a,a
        ld b,a
        ld a,h
        rlca
        rlca
        rlca
        and 7
        or b
        ld (gp_bank),a                  ; bank index = bits 13-20
        ld a,h
        and $1f
        ld h,a
        ld (gp_within),hl
        ld hl,gp_tmp
        ld (gp_tmp_at),hl
.segment:
        ld hl,(gp_left)
        ld a,h
        or l
        jr z,.restore
        ld hl,(gp_req)                  ; page the bank in
        ld de,GP_FILE_BANKS
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld a,(gp_bank)
        ex de,hl
        cp (hl)                         ; index < number of banks?
        jr nc,.past
        inc a
        ld e,a
        ld d,0
        add hl,de
        ld a,(hl)
        ld bc,GP_NEXTREG_SELECT
        ld e,a
        ld a,(gp_mmu)
        out (c),a
        ld bc,GP_NEXTREG_ACCESS
        out (c),e
        ld hl,8192                      ; this segment: min(left, 8192 - within)
        ld de,(gp_within)
        or a
        sbc hl,de
        ld de,(gp_left)
        push hl
        or a
        sbc hl,de
        pop hl
        jr c,.count
        ex de,hl
.count: ld b,h
        ld c,l
        ld hl,(gp_left)
        or a
        sbc hl,bc
        ld (gp_left),hl
        ld a,(gp_window)                ; HL = window + within
        ld hl,(gp_within)
        add a,h
        ld h,a
        ld de,(gp_tmp_at)
        ld a,(gp_dir)
        or a
        jr z,.copy
        ex de,hl                        ; gp_tmp -> bank
.copy:  ldir
        ld a,(gp_dir)
        or a
        jr z,.read
        ld (gp_tmp_at),hl
        jr .next
.read:  ld (gp_tmp_at),de
.next:  ld hl,0
        ld (gp_within),hl
        ld hl,gp_bank
        inc (hl)
        jr .segment
.past:  call .restore
        scf
        ret
.restore:
        ld bc,GP_NEXTREG_SELECT
        ld a,(gp_mmu)
        out (c),a
        ld bc,GP_NEXTREG_ACCESS
        ld a,(gp_mmu_saved)
        out (c),a
        or a
        ret

; ---------------------------------------------------------------------------
gp_header:      db $f0, $7d, $47, $4c, $4d, $01

gp_io:          dw 0
gp_sender:      dw 0
gp_external:    db 0
gp_status:      db 0
gp_error:       db 0
gp_detail:      dw $3fff
gp_count:       ds 3
gp_step:        db 0
gp_tt:          db $20
gp_cmd:         db 0
gp_resp:        db 0
gp_flags:       db 0
gp_waiting:     db 0
gp_timer:       dw 0
gp_budget:      db 0
gp_reads:       db 0
gp_got:         db 0
gp_wlen:        db 0
gp_req:         dw 0
gp_dest:        dw 0
gp_dest_size:   db 0
gp_len:         dw 0
gp_size:        ds 3
gp_pos:         ds 3
gp_seq:         dw 0
gp_chunk_len:   dw 0
gp_sum:         db 0
gp_wp:          dw 0
gp_group:       db 0
gp_hibits:      db 0
gp_tx_len:      dw 0
gp_tx_sent:     dw 0
gp_tx_handed:   db 0
gp_rx_on:       db 0
gp_rx_len:      dw 0
gp_plen:        dw 0
gp_dir:         db 0
gp_left:        dw 0
gp_mmu:         db 0
gp_mmu_saved:   db 0
gp_window:      db 0
gp_bank:        db 0
gp_within:      dw 0
gp_tmp_at:      dw 0
gp_tx:          ds GP_FRAME_SIZE
gp_rx:          ds GP_FRAME_SIZE
gp_tmp:         ds GP_FRAME_SIZE
