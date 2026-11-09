; .GPARAM: the Golem's sound parameters from the Next (docs/sound-params.md),
; through the gp_* library (src/lib/gparam.s). For trying the protocol on the
; hardware and for loading OPL3 banks from the Next's card.
;
;   .gparam info                     version, name and what the Golem has
;   .gparam get AREA ADDRESS LENGTH  reads, in hexadecimal (LENGTH 1-100)
;   .gparam set AREA ADDRESS BYTE..  writes 1-16 bytes, confirmed
;   .gparam put FILE                 uploads a WOPL bank (up to 512K): the
;                                    working bank
;   .gparam save FILE                downloads the working bank (up to 128K)
;   .gparam put mt32 FILE            uploads an MT-32 dump (.SYX, DT1 messages)
;   .gparam save mt32 FILE           downloads the MT-32's timbre and patch
;                                    memory, rhythm setup and system (.SYX)
;   .gparam put fx FILE              uploads FluidSynth's effects (.CFG text)
;   .gparam save fx FILE             downloads them, as a SoundFont profile
;   .gparam sbi FILE PROGRAM         a 2-operator .SBI instrument as that
;   .gparam sbi FILE drum NOTE       program (melodic bank 0) or drum note
;                                    (percussion bank 0) of the working bank
;
; Numbers are hexadecimal. AREA: 00 the MT-32's memory (Roland's addresses),
; 04 its ROM timbres (n x 200), 01 OPL3 instruments (address bank << 14 |
; program << 7 | offset, 128 bytes each), 02 OPL3 bank directory and header,
; 10 settings (section << 14 | parameter). Example, total level of operator 1
; of program 0: .gparam set 01 26 3F
;
; Runs with its stack and buffers in a private bank at MMU3; the file is kept
; in 8K banks seen through MMU4 (DMXOPL3, the default bank, is 116K as WOPL). Restores MMU3, MMU4, the NextReg
; selector and the banks on every exit. SPACE stops a transfer.

        opt zxnext
        include "../../include/mt32_api.inc"

GP_MAX_DATA     equ 256

M_GETSETDRV     equ $89
F_OPEN          equ $9a
F_CLOSE         equ $9b
F_READ          equ $9d
F_WRITE         equ $9e
M_P3DOS         equ $94
IDE_BANK        equ $01bd
FA_READ         equ $01
FA_WRITE_NEW    equ $0e         ; write, create or truncate

NEXTREG_SELECT  equ $243b
NXR_MMU3        equ $53
NXR_MMU4        equ $54
SCR_CT          equ 23692

IO_BUFFER       equ $6000       ; private bank at MMU3
REQ_BLOCK       equ $6010
FILE_BLOCK      equ $6020
BANK_TABLE      equ $6100       ; count, then up to MAX_BANKS banks
NAME_BUFFER     equ $6180       ; 64 bytes
DATA_BUFFER     equ $6200       ; 256
LOCAL_STACK     equ $7ff0
FILE_WINDOW     equ $8000       ; MMU4
MAX_BANKS       equ 64          ; put: 512K, the Golem's limit
SAVE_BANKS      equ 16          ; save: room for 128K
SAVE_BANKS_MT32 equ 3           ; an MT-32 dump is 17841 bytes

        org $2000

start:
        ld (args),hl
        ld (saved_sp),sp
        xor a
        ld (work_mapped),a
        ld (acquired),a
        ld (file_open),a
        ld (bank_count),a
        ld bc,NEXTREG_SELECT
        in a,(c)
        ld (saved_select),a
        ld a,NXR_MMU3
        out (c),a
        inc b
        in a,(c)
        ld (saved_mmu3),a
        dec b
        ld a,NXR_MMU4
        out (c),a
        inc b
        in a,(c)
        ld (saved_mmu4),a

        call allocate_bank          ; on the caller's stack
        ld hl,err_memory
        jp nc,fail
        ld (work_bank),a
        ld d,NXR_MMU3
        call map_bank
        ld sp,LOCAL_STACK
        ld a,1
        ld (work_mapped),a

        ld hl,(args)                ; which order?
        call skip_spaces
        call word_to_lower
        ld de,word_info
        call match
        jp z,cmd_info
        ld de,word_get
        call match
        jp z,cmd_get
        ld de,word_set
        call match
        jp z,cmd_set
        ld de,word_put
        call match
        jp z,cmd_put
        ld de,word_save
        call match
        jp z,cmd_save
        ld de,word_sbi
        call match
        jp z,cmd_sbi
usage:
        ld hl,err_usage
        jp fail

; ---------------------------------------------------------------------------
; The orders

cmd_info:
        call open_driver
        xor a
        ld hl,DATA_BUFFER
        ld b,40
        call gp_info
        call wait_done
        ld a,(DATA_BUFFER+2)        ; platform
        or a
        ld hl,msg_firmware
        jr z,.platform
        ld hl,msg_golemd
.platform:
        call print_z
        ld a,(DATA_BUFFER+3)        ; version
        call print_dec
        ld a,'.'
        call putc
        ld a,(DATA_BUFFER+4)
        call print_dec
        ld a,'.'
        call putc
        ld a,(DATA_BUFFER+5)
        call print_dec
        ld hl,msg_protocol
        call print_z
        ld a,(DATA_BUFFER+0)
        call print_dec
        ld a,'.'
        call putc
        ld a,(DATA_BUFFER+1)
        call print_dec
        ld a,13
        call putc
        ld hl,msg_banks             ; OPL3 banks, chips
        call print_z
        ld a,(DATA_BUFFER+19)
        call print_dec
        ld hl,msg_chips
        call print_z
        ld a,(DATA_BUFFER+14)
        call print_dec
        ld a,13
        call putc
        ld a,1                      ; page 1: the name
        ld hl,DATA_BUFFER
        ld b,60
        call gp_info
        call wait_done
        call gp_result              ; HL = bytes
        ld b,l
        ld hl,DATA_BUFFER
        ld a,b
        or a
        jr z,.named
.name:  ld a,(hl)
        inc hl
        push hl
        push bc
        call putc
        pop bc
        pop hl
        djnz .name
.named: ld a,13
        call putc
        jp done

cmd_get:
        call area_address
        call next_byte              ; length
        jp c,usage
        ld a,l
        or a
        jp z,usage
        cp 101
        jp nc,usage
        ld (REQ_BLOCK+6),hl
        ld hl,DATA_BUFFER
        ld (REQ_BLOCK+4),hl
        call open_driver
        ld hl,REQ_BLOCK
        call gp_read
        call wait_done
        ld hl,DATA_BUFFER           ; 8 per line: "000026 3F 00 ..."
        ld a,(REQ_BLOCK+6)
        ld b,a
.line:  push bc
        push hl
        call print_address
        pop hl
        pop bc
        ld c,8
.byte:  ld a,' '
        call putc
        ld a,(hl)
        inc hl
        push hl
        push bc
        call print_hex
        pop bc
        pop hl
        call advance_address
        dec b
        jr z,.end
        dec c
        jr nz,.byte
        ld a,13
        call putc
        jr .line
.end:   ld a,13
        call putc
        jp done

cmd_set:
        call area_address
        ld de,DATA_BUFFER
        ld b,0
.value: push bc
        push de
        call next_byte
        pop de
        pop bc
        jr c,.values
        ld a,l
        cp $80
        jp nc,usage
        ld (de),a
        inc de
        inc b
        ld a,b
        cp 17
        jp nc,usage
        jr .value
.values:
        ld a,b
        or a
        jp z,usage
        ld l,a
        ld h,0
        ld (REQ_BLOCK+6),hl
        ld hl,DATA_BUFFER
        ld (REQ_BLOCK+4),hl
        ld a,GP_FLAG_CONFIRM
        ld (REQ_BLOCK+8),a
        call open_driver
        ld hl,REQ_BLOCK
        call gp_write
        call wait_done
        ld hl,msg_ok
        call print_z
        jp done

cmd_put:
        call file_type
        call file_name
        call name_last
        xor a
        rst $08
        db M_GETSETDRV
        ld hl,NAME_BUFFER
        ld b,FA_READ
        rst $08
        db F_OPEN
        ld hl,err_open
        jp c,fail
        ld (file_handle),a
        ld a,1
        ld (file_open),a
        ld hl,0
        ld (file_size),hl
        xor a
        ld (file_size+2),a
.bank:  ld a,(bank_count)           ; read 8K at a time into new banks
        cp MAX_BANKS
        ld hl,err_big
        jp nc,fail
        call allocate_bank
        ld hl,err_memory
        jp nc,fail
        call add_bank
        ld d,NXR_MMU4
        call map_bank
        ld a,(file_handle)
        ld hl,FILE_WINDOW
        ld bc,$2000
        rst $08
        db F_READ
        push af
        push bc
        ld a,(saved_mmu4)
        ld d,NXR_MMU4
        call map_bank
        pop bc
        pop af
        ld hl,err_read
        jp c,fail
        ld hl,(file_size)
        add hl,bc
        ld (file_size),hl
        ld a,(file_size+2)
        adc a,0
        ld (file_size+2),a
        ld a,b
        cp $20
        jr z,.bank                  ; a whole bank: maybe more
        call close_file
        ld hl,(file_size)
        ld a,(file_size+2)
        or h
        or l
        ld hl,err_empty
        jp z,fail
        ld hl,msg_sending
        call print_z
        ld hl,(file_size)
        ld a,(file_size+2)
        call print_dec24
        ld hl,msg_bytes
        call print_z
        call open_driver
        call fill_file_block
        ld hl,(file_size)
        ld (FILE_BLOCK+2),hl
        ld a,(file_size+2)
        ld (FILE_BLOCK+4),a
        ld hl,FILE_BLOCK
        call gp_blob_put
        call wait_done
        ld hl,msg_loaded
        ld a,(blob_type)
        cp GP_FILE_WOPL
        jr z,.said
        ld hl,msg_mt32_loaded
        cp GP_FILE_MT32
        jr z,.said
        ld hl,msg_fx_loaded
.said:  call print_z
        jp done

cmd_save:
        call file_type
        call file_name
        call name_last
        ld hl,0                     ; room: SAVE_BANKS x 8K, 128K
        ld c,SAVE_BANKS/8
        ld a,(blob_type)
        cp GP_FILE_WOPL
        ld a,SAVE_BANKS
        jr z,.room
        ld a,(blob_type)
        cp GP_FILE_MT32
        ld a,SAVE_BANKS_MT32        ; an MT-32 dump: 24K
        ld hl,SAVE_BANKS_MT32*$2000
        jr z,.small
        ld a,1                      ; effects: a few hundred bytes, 8K
        ld hl,$2000
.small: ld c,0
.room:  ld (save_room),a
        ld (FILE_BLOCK+2),hl        ; fill_file_block leaves the size alone
        ld a,c
        ld (FILE_BLOCK+4),a
.bank:  call allocate_bank
        ld hl,err_memory
        jp nc,fail
        call add_bank
        ld a,(save_room)
        ld b,a
        ld a,(bank_count)
        cp b
        jr c,.bank
        call open_driver
        call fill_file_block
        ld hl,FILE_BLOCK
        call gp_blob_get
        call wait_done
        call gp_result              ; C:HL = file size
        ld (file_size),hl
        ld a,c
        ld (file_size+2),a
        xor a
        rst $08
        db M_GETSETDRV
        ld hl,NAME_BUFFER
        ld b,FA_WRITE_NEW
        rst $08
        db F_OPEN
        ld hl,err_open
        jp c,fail
        ld (file_handle),a
        ld a,1
        ld (file_open),a
        ld hl,BANK_TABLE+1
        ld (bank_at),hl
.write: ld a,(file_size+2)          ; 8K from each bank, the rest from the last
        ld hl,(file_size)
        ld b,a
        or h
        or l
        jr z,.written
        ld a,b
        or a
        jr nz,.whole
        ld a,h
        cp $20
        jr nc,.whole
        ld b,h                      ; under 8K left: all of it
        ld c,l
        ld hl,0
        ld (file_size),hl
        jr .bank_out
.whole: ld bc,$2000
        ld de,$2000
        or a
        sbc hl,de
        ld (file_size),hl
        ld a,(file_size+2)
        sbc a,0
        ld (file_size+2),a
.bank_out:
        push bc
        ld hl,(bank_at)
        ld a,(hl)
        inc hl
        ld (bank_at),hl
        ld d,NXR_MMU4
        call map_bank
        pop bc
        ld a,(file_handle)
        ld hl,FILE_WINDOW
        rst $08
        db F_WRITE
        push af
        ld a,(saved_mmu4)
        ld d,NXR_MMU4
        call map_bank
        pop af
        ld hl,err_write
        jp c,fail
        jr .write
.written:
        call close_file
        ld hl,msg_saved
        call print_z
        call gp_result
        ld a,c
        call print_dec24
        ld hl,msg_bytes
        call print_z
        jp done

; A .SBI file: "SBI",$1a, a 32-byte name and 11 register bytes, modulator
; then carrier for each of $20, $40, $60, $80 and $e0, then $c0. It becomes a
; whole 128-byte record of area 01 (sound-params.md 6.3), as golembank.py
; add does: 2 operators, operator 1 the carrier and operator 2 the modulator.
SBI_SIZE        equ 47              ; what is read: the rest is not used
SBI_REGS        equ 36
SBI_RECORD      equ DATA_BUFFER     ; 128 bytes
SBI_FILE        equ DATA_BUFFER+128 ; 52 bytes

cmd_sbi:
        call file_name
        ld hl,(args_at)             ; PROGRAM, or drum NOTE
        call skip_spaces
        or $20
        cp 'd'
        jr nz,.melodic
        call word_to_lower
        ld de,word_drum
        call match
        jp nz,usage
        call sbi_number
        ld (sbi_key),a              ; the drum's note: also the note it plays
        ld (sbi_slot),a
        ld a,$40                    ; percussion bank 0
        jr .read
.melodic:
        call sbi_number
        ld (sbi_slot),a
        xor a
        ld (sbi_key),a              ; melodic bank 0
.read:  ld (sbi_bank),a
        xor a
        rst $08
        db M_GETSETDRV
        ld hl,NAME_BUFFER
        ld b,FA_READ
        rst $08
        db F_OPEN
        ld hl,err_open
        jp c,fail
        ld (file_handle),a
        ld a,1
        ld (file_open),a
        ld a,(file_handle)
        ld hl,SBI_FILE
        ld bc,SBI_SIZE
        rst $08
        db F_READ
        ld hl,err_read
        jp c,fail
        ld a,c
        cp SBI_SIZE
        jr c,.not_sbi
        call close_file
        ld hl,SBI_FILE              ; "SBI",$1a
        ld de,sbi_magic
        ld b,4
.magic: ld a,(de)
        cp (hl)
        jr nz,.not_sbi
        inc hl
        inc de
        djnz .magic
        jr .record
.not_sbi:
        ld hl,err_sbi
        jp fail
.record:
        ld hl,SBI_RECORD            ; the record: zero, then the fields
        ld de,SBI_RECORD+1
        ld bc,127
        ld (hl),0
        ldir
        ld a,(sbi_key)
        ld (SBI_RECORD+$04),a
        ld a,64                     ; no note, velocity or detune offsets
        ld (SBI_RECORD+$05),a
        ld (SBI_RECORD+$06),a
        ld (SBI_RECORD+$07),a
        ld (SBI_RECORD+$08),a
        ld (SBI_RECORD+$11),a       ; no fine tune (WOPLX)
        ld (SBI_RECORD+$12),a
        ld a,(SBI_FILE+SBI_REGS+10) ; $c0: feedback and connection
        ld b,a
        and 1
        ld (SBI_RECORD+$0a),a
        ld a,b
        rrca
        and 7
        ld (SBI_RECORD+$09),a
        ld hl,SBI_RECORD+$20        ; operator 1: the carrier
        ld de,SBI_FILE+SBI_REGS+1
        call sbi_operator
        ld hl,SBI_RECORD+$30        ; operator 2: the modulator
        ld de,SBI_FILE+SBI_REGS
        call sbi_operator
        ld hl,SBI_FILE+4            ; the name, 7-bit, zero-ended
        ld de,SBI_RECORD+$60
        ld b,31
.name:  ld a,(hl)
        and $7f
        ld (de),a
        jr z,.named
        inc hl
        inc de
        djnz .name
.named:
        ld a,(sbi_slot)             ; area 01: bank << 14 | slot << 7
        rrca
        and $80
        ld (REQ_BLOCK+1),a          ; bits 0-7
        ld a,(sbi_slot)
        srl a
        ld b,a
        ld a,(sbi_bank)
        rrca
        rrca
        and $c0
        or b
        ld (REQ_BLOCK+2),a          ; bits 8-15
        ld a,(sbi_bank)
        srl a
        srl a
        ld (REQ_BLOCK+3),a          ; bits 16-20
        ld a,$01
        ld (REQ_BLOCK+0),a
        ld hl,SBI_RECORD
        ld (REQ_BLOCK+4),hl
        ld hl,128
        ld (REQ_BLOCK+6),hl
        ld a,GP_FLAG_CONFIRM
        ld (REQ_BLOCK+8),a
        call open_driver
        ld hl,REQ_BLOCK
        call gp_write
        call wait_done
        ld hl,SBI_RECORD+$60
        call print_z
        ld hl,msg_sbi
        call print_z
        jp done

; The next number, 0-7F: A. Usage if there is none or it is larger.
sbi_number:
        call next_byte
        jp c,usage
        ld a,l
        cp $80
        jp nc,usage
        ret

; HL = operator block, DE = its first register byte in the .SBI ($20; then
; $40, $60, $80 and $e0 at DE+2, +4, +6, +8)
sbi_operator:
        ld a,(de)                   ; $20: AM, vibrato, sustain, KSR, multiplier
        ld b,4
.bits:  rlca
        push af
        and 1
        ld (hl),a
        inc hl
        pop af
        djnz .bits
        ld a,(de)
        and $0f
        ld (hl),a                   ; +4 multiplier
        inc hl
        inc de
        inc de
        ld a,(de)                   ; $40: KSL, total level
        ld c,a
        rlca
        rlca
        and 3
        ld (hl),a
        inc hl
        ld a,c
        and $3f
        ld (hl),a
        inc hl
        inc de
        inc de
        call .nibbles               ; $60: attack, decay
        inc de
        inc de
        call .nibbles               ; $80: sustain level, release
        inc de
        inc de
        ld a,(de)                   ; $e0: waveform
        and 7
        ld (hl),a
        ret
.nibbles:
        ld a,(de)
        rrca
        rrca
        rrca
        rrca
        and $0f
        ld (hl),a
        inc hl
        ld a,(de)
        and $0f
        ld (hl),a
        inc hl
        ret

; ---------------------------------------------------------------------------
; Exits

done:
        ld hl,0
        xor a
        ld (failed),a
        jr finish

fail:
        ld a,1
        ld (failed),a
finish:
        ld (exit_message),hl
        call close_file
        ld a,(acquired)
        or a
        jr z,.released
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_RELEASE
        rst $08
        db NEXTZXOS_M_DRVAPI
.released:
        ld a,(bank_count)           ; the file banks
        or a
        jr z,.banks_freed
        ld b,a
        ld hl,BANK_TABLE+1
.free:  ld a,(hl)
        inc hl
        push hl
        push bc
        call free_bank
        pop bc
        pop hl
        djnz .free
.banks_freed:
        ld a,(saved_mmu4)
        ld d,NXR_MMU4
        call map_bank
        ld sp,(saved_sp)            ; leave the private stack before unmapping
        ld a,(work_mapped)
        or a
        jr z,.unmapped
        ld a,(saved_mmu3)
        ld d,NXR_MMU3
        call map_bank
        ld a,(work_bank)
        call free_bank
.unmapped:
        ld bc,NEXTREG_SELECT
        ld a,(saved_select)
        out (c),a
        ld hl,(exit_message)
        ld a,(failed)
        or a
        ret z
        xor a                       ; custom error report, last char bit 7
        scf
        ret

close_file:
        ld a,(file_open)
        or a
        ret z
        xor a
        ld (file_open),a
        ld a,(file_handle)
        rst $08
        db F_CLOSE
        ret

; ---------------------------------------------------------------------------
; The driver and the library

open_driver:
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_QUERY
        rst $08
        db NEXTZXOS_M_DRVAPI
        ld a,l                      ; capabilities, before HL is reused
        ld hl,err_driver
        jp c,fail
        and MT32_CAP_RX_NONBLOCKING
        ld hl,err_no_rx
        jp z,fail
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_ACQUIRE
        rst $08
        db NEXTZXOS_M_DRVAPI
        ld hl,err_driver
        jp c,fail
        ld a,1
        ld (acquired),a
        ld hl,IO_BUFFER
        jp gp_init

; Runs the operation one frame at a time until it ends. On a failure, prints
; the error and leaves.
wait_done:
        jr c,.refused               ; the call itself refused it: A = error
.frame: ld bc,$7ffe                 ; SPACE stops
        in a,(c)
        bit 0,a
        ld hl,err_stopped
        jp z,fail
        ei
        halt
        ld b,4                      ; 64 bytes a frame: the cable's speed
        call gp_update
        cp GP_BUSY
        jr z,.frame
        cp GP_DONE
        ret z
        call gp_result              ; B = error, DE = position
        jr .report
.refused:
        ld b,a
        ld de,$3fff
.report:
        ld a,b
        ld (gp_err),a
        ld (gp_pos_detail),de
        ld hl,msg_error
        call print_z
        ld a,(gp_err)
        call print_hex
        ld hl,error_names           ; a word for the common ones
.name:  ld a,(hl)
        inc hl
        cp $ff
        jr z,.named
        ld b,a
        ld a,(gp_err)
        cp b
        jr z,.found
.skip:  ld a,(hl)
        inc hl
        or a
        jr nz,.skip
        jr .name
.found: ld a,' '
        call putc
        call print_z
.named: ld hl,(gp_pos_detail)
        ld a,h
        cp $3f
        jr nz,.at
        ld a,l
        cp $ff
        jr z,.line
.at:    push hl
        ld hl,msg_at
        call print_z
        pop hl
        call print_dec16
.line:  ld a,13
        call putc
        jp done

; "mt32" before the file name: an MT-32 dump; "fx": FluidSynth's effects;
; otherwise an OPL3 bank
file_type:
        ld a,GP_FILE_WOPL
        ld (blob_type),a
        ld hl,(args_at)
        call skip_spaces
        push hl
        call word_to_lower
        ld de,word_mt32
        call match
        jr z,.mt32
        ld de,word_fx
        call match
        pop hl
        jr z,.fx
        ld (args_at),hl             ; not a type: the file name starts here
        ret
.mt32:  pop hl
        ld a,GP_FILE_MT32
        ld (blob_type),a
        ret
.fx:    ld a,GP_FILE_FX
        ld (blob_type),a
        ret

fill_file_block:
        ld a,(blob_type)
        ld (FILE_BLOCK+0),a
        xor a
        ld (FILE_BLOCK+1),a         ; the working bank
        ld hl,BANK_TABLE
        ld (FILE_BLOCK+5),hl
        ld hl,0
        ld (FILE_BLOCK+7),hl
        ld a,NXR_MMU4
        ld (FILE_BLOCK+9),a
        ld a,(bank_count)
        ld (BANK_TABLE),a
        ret

; A = bank: appended to the table
add_bank:
        push af
        ld a,(bank_count)
        ld e,a
        ld d,0
        inc a
        ld (bank_count),a
        ld hl,BANK_TABLE+1
        add hl,de
        pop af
        ld (hl),a
        ret

; ---------------------------------------------------------------------------
; Arguments

; AREA ADDRESS into the request block. Leaves HL on what follows.
area_address:
        call next_byte
        jp c,usage
        ld a,l
        cp $80
        jp nc,usage
        ld (REQ_BLOCK+0),a
        call next_hex
        jp c,usage
        ld a,(hex_high)
        cp $20
        jp nc,usage                 ; 21 bits
        ld (REQ_BLOCK+1),hl
        ld (REQ_BLOCK+3),a
        ld (address),hl
        ld (address+2),a
        xor a
        ld (REQ_BLOCK+8),a
        ret

; The next hexadecimal number of the arguments, up to 6 digits: HL = low 16
; bits, hex_high = bits 16-23. Carry if there is none.
next_hex:
        ld hl,(args_at)
        call skip_spaces
        ld de,0
        xor a
        ld (hex_high),a
        ld (hex_digits),a
.digit: ld a,(hl)
        call hex_value
        jr c,.end
        inc hl
        push hl
        ld hl,hex_digits
        inc (hl)
        ld b,4                      ; hex_high:DE <<= 4
.shift: sla e
        rl d
        push af
        ld a,(hex_high)
        rla
        ld (hex_high),a
        pop af
        djnz .shift
        pop hl
        or e
        ld e,a
        ld a,(hex_digits)
        cp 7
        jp nc,usage
        jr .digit
.end:   ld (args_at),hl
        ld a,(hex_digits)
        or a
        scf
        ret z
        ex de,hl
        or a
        ret

; The next number, 0-255 (HL); carry if there is none, usage if larger
next_byte:
        call next_hex
        ret c
        ld a,(hex_high)
        or h
        jp nz,usage
        ret

; A = character: 0-15, carry if not a hexadecimal digit
hex_value:
        sub '0'
        ret c
        cp 10
        ccf
        ret nc
        or $20                      ; lower case ('A'-'0' | $20 = 'a'-'0')
        sub 'a'-'0'
        ret c
        cp 6
        ccf
        ret c
        add a,10
        ret

; The file name: the next word, which may be in quotes. A ':' belongs to
; it (c:/opl3/bank.wopl), not to BASIC.
file_name:
        ld hl,(args_at)
        call skip_spaces
        cp '"'
        jr nz,.start
        inc hl
.start: ld de,NAME_BUFFER
        ld b,63
.copy:  ld a,(hl)
        or a
        jr z,.end
        cp 13
        jr z,.end
        cp ' '
        jr z,.end
        cp '"'
        jr z,.end
        ld (de),a
        inc hl
        inc de
        djnz .copy
.end:   cp '"'                      ; past a closing quote
        jr nz,.after
        inc hl
.after: ld (args_at),hl             ; for what follows the name
        xor a
        ld (de),a
        ld a,(NAME_BUFFER)
        or a
        jp z,usage
        ret

; Nothing may follow the file name of put and save: with "save fx now.cfg"
; and a .GPARAM that does not know "fx", the bank went to a file called FX
name_last:
        ld hl,(args_at)
        call skip_spaces
        jp nz,usage
        ret

; HL = arguments: skips spaces. Z at the end of the arguments.
skip_spaces:
        ld a,(hl)
        cp ' '
        jr nz,end_of_args
        inc hl
        jr skip_spaces

; Z if A ends the arguments (0, CR, ':')
end_of_args:
        or a
        ret z
        cp 13
        ret z
        cp ':'
        ret

; HL = a word of the arguments: copied in lower case to the word buffer
word_to_lower:
        ld de,word
        ld b,7
.copy:  ld a,(hl)
        call end_of_args
        jr z,.end
        cp ' '
        jr z,.end
        cp 'A'
        jr c,.keep
        cp 'Z'+1
        jr nc,.keep
        or $20
.keep:  ld (de),a
        inc hl
        inc de
        djnz .copy
.end:   ld (args_at),hl
        xor a
        ld (de),a
        ret

; DE = a word, zero-ended: Z if it is the one in the word buffer
match:
        ld hl,word
.next:  ld a,(de)
        cp (hl)
        ret nz
        or a
        ret z
        inc hl
        inc de
        jr .next

; ---------------------------------------------------------------------------
; Printing

; The current address, 6 digits
print_address:
        ld a,(address+2)
        call print_hex
        ld a,(address+1)
        call print_hex
        ld a,(address)
        jp print_hex

advance_address:
        push hl
        ld hl,(address)
        inc hl
        ld (address),hl
        ld a,h
        or l
        jr nz,.done
        ld hl,address+2
        inc (hl)
.done:  pop hl
        ret

print_hex:
        push af
        rrca
        rrca
        rrca
        rrca
        call .digit
        pop af
.digit:
        and $0f
        add a,'0'
        cp '9'+1
        jr c,.out
        add a,7
.out:   call putc
        ret

; A = 0-255 in decimal
print_dec:
        ld l,a
        ld h,0
; HL = 0-65535 in decimal
print_dec16:
        xor a
; A:HL = 0-16777215 in decimal, without leading zeros
print_dec24:
        ld e,a
        xor a
        ld (dec_count),a
        ld a,e
.digit: call div10                  ; A:HL /= 10, C = remainder
        push af
        push hl
        ld a,(dec_count)
        ld e,a
        ld d,0
        inc a
        ld (dec_count),a
        ld hl,dec_digits
        add hl,de
        ld a,c
        add a,'0'
        ld (hl),a
        pop hl
        pop af
        ld e,a
        or h
        or l
        ld a,e
        jr nz,.digit
        ld a,(dec_count)            ; the digits, last found first
        ld b,a
.out:   ld e,b
        dec e
        ld d,0
        ld hl,dec_digits
        add hl,de
        ld a,(hl)
        call putc
        djnz .out
        ret

; A:HL = A:HL / 10, C = the remainder
div10:
        ld c,0
        ld b,24
.bit:   add hl,hl
        rla
        rl c
        push af
        ld a,c
        cp 10
        jr c,.less
        sub 10
        ld c,a
        inc l
.less:  pop af
        djnz .bit
        ret

print_z:
        ld a,(hl)
        inc hl
        or a
        ret z
        call putc
        jr print_z

; A = character, printed with the ROM; keeps BC, DE and HL
putc:
        push bc
        push de
        push hl
        rst $10
        pop hl
        pop de
        pop bc
        ret

; ---------------------------------------------------------------------------
; Memory

; Out: carry set and A = bank on success
allocate_bank:
        ld hl,$0001
        exx
        ld de,IDE_BANK
        ld c,7
        rst $08
        db M_P3DOS
        ld a,e
        ret

free_bank:
        ld e,a
        ld hl,$0003
        exx
        ld de,IDE_BANK
        ld c,7
        rst $08
        db M_P3DOS
        ret

; A = bank, D = MMU register
map_bank:
        ld bc,NEXTREG_SELECT
        ld e,a
        ld a,d
        out (c),a
        inc b
        out (c),e
        ret

        include "../lib/gparam.s"

word_info:   db "info",0
word_get:    db "get",0
word_set:    db "set",0
word_put:    db "put",0
word_save:   db "save",0
word_sbi:    db "sbi",0
word_drum:   db "drum",0
word_mt32:   db "mt32",0
word_fx:     db "fx",0
sbi_magic:   db "SBI",$1a
msg_sbi:     db ": OK",13,0
msg_firmware: db "Golem firmware ",0
msg_golemd:  db "Golem golemd ",0
msg_protocol: db ", protocol ",0
msg_banks:   db "OPL3: ",0
msg_chips:   db " banks, chips ",0
msg_ok:      db "OK",13,0
msg_sending: db "Sending ",0
msg_bytes:   db " bytes",13,0
msg_loaded:  db "Working OPL3 bank loaded",13,0
msg_mt32_loaded: db "MT-32 dump loaded",13,0
msg_fx_loaded: db "Effects loaded",13,0
msg_saved:   db "Saved ",0
msg_error:   db "Golem error ",0
msg_at:      db " at ",0
error_names: db $04,"value",0, $05,"unavailable",0, $07,"checksum",0, $08,"address",0
             db $09,"too long",0, $0a,"busy",0, $0b,"sequence",0, $20,"no answer",0
             db $21,"driver",0, $22,"size",0, $24,"bad reply",0, $ff
err_usage:   db ".gparam info|get|set|put|save|sb",'i'+$80
err_sbi:     db "GPARAM: not a 2-operator .SB",'I'+$80
err_memory:  db "GPARAM: out of memory bank",'s'+$80
err_driver:  db "GPARAM: GOLEM.DRV missing or in us",'e'+$80
err_no_rx:   db "GPARAM: GOLEM.DRV has no RX (ABI 0.2",')'+$80
err_open:    db "GPARAM: cannot open the fil",'e'+$80
err_read:    db "GPARAM: read erro",'r'+$80
err_write:   db "GPARAM: write erro",'r'+$80
err_big:     db "GPARAM: file over 512",'K'+$80
err_empty:   db "GPARAM: empty fil",'e'+$80
err_stopped: db "GPARAM: stoppe",'d'+$80

args:         dw 0
args_at:      dw 0
blob_type:    db 0
save_room:   db 0
saved_sp:     dw 0
exit_message: dw 0
file_size:    ds 3
dec_count:    db 0
dec_digits:   ds 8
bank_at:      dw 0
address:      ds 3
hex_high:     db 0
hex_digits:   db 0
gp_err:       db 0
gp_pos_detail: dw 0
word:         ds 8
saved_select: db 0
saved_mmu3:   db 0
saved_mmu4:   db 0
work_bank:    db 0
work_mapped:  db 0
acquired:     db 0
file_open:    db 0
file_handle:  db 0
bank_count:   db 0
sbi_key:      db 0
sbi_slot:     db 0
sbi_bank:     db 0
failed:       db 0
