; .MIDIMON: shows every MIDI message that reaches GOLEM.DRV, in hexadecimal.
;
; A USB keyboard on the Golem after `.golem set keys on`, or a DIN keyboard on
; a joystick port's MIDI IN after `.golem output left|right`. The Golem's own
; replies are not shown (src/lib/midiin.s drops them). SPACE ends.
;
; Runs at 28 MHz with its buffers and stack in a private bank at MMU3, and
; restores the speed, MMU3, the NextReg selector and the bank on every exit.

        opt zxnext
        include "../../include/mt32_api.inc"

M_P3DOS         equ $94
IDE_BANK        equ $01bd
NEXTREG_SELECT  equ $243b
NXR_TURBO       equ $07
NXR_MMU3        equ $53
SCR_CT          equ 23692       ; lines before "scroll?"; kept high
RX_BUFFER       equ $6000       ; 16 bytes, in the private bank
SYSEX_BUFFER    equ $6010
SYSEX_SIZE      equ 128
LOCAL_STACK     equ $7ff0

        org $2000

start:
        ld (saved_sp),sp
        xor a
        ld (work_mapped),a
        ld (acquired),a
        ld bc,NEXTREG_SELECT
        in a,(c)
        ld (saved_select),a
        ld a,NXR_TURBO
        out (c),a
        inc b
        in a,(c)
        and 3
        ld (saved_speed),a
        dec b
        ld a,NXR_MMU3
        out (c),a
        inc b
        in a,(c)
        ld (saved_mmu3),a

        call allocate_bank          ; on the caller's stack
        ld hl,err_memory
        jp nc,fail
        ld (work_bank),a
        ld bc,NEXTREG_SELECT
        ld a,NXR_MMU3
        out (c),a
        inc b
        ld a,(work_bank)
        out (c),a
        ld sp,LOCAL_STACK
        ld a,1
        ld (work_mapped),a
        ld bc,NEXTREG_SELECT
        ld a,NXR_TURBO
        out (c),a
        inc b
        ld a,3                      ; 28 MHz: printing keeps up with playing
        out (c),a

        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_QUERY
        rst $08
        db NEXTZXOS_M_DRVAPI
        ld hl,err_driver
        jp c,fail
        ld a,l
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

        ld hl,RX_BUFFER
        ld de,SYSEX_BUFFER
        ld b,SYSEX_SIZE
        call mi_init
        ld hl,msg_start
        call print_z

monitor:
        ld bc,$7ffe                 ; SPACE ends
        in a,(c)
        bit 0,a
        jr z,done
        call mi_get
        ld hl,err_read
        jp c,fail
        cp MI_GET_SHORT
        jr z,.short
        cp MI_GET_SYSEX
        jr nz,monitor
        ld a,c                      ; SysEx: B bytes kept, C = 1 if cut
        ld (sysex_cut),a
        ld hl,SYSEX_BUFFER
        call print_bytes
        ld a,(sysex_cut)
        or a
        ld hl,msg_cut
        call nz,print_z
        jr .line_end
.short:
        ld hl,mi_message            ; B = length
        call print_bytes
.line_end:
        ld a,13
        rst $10
        ld a,255
        ld (SCR_CT),a               ; never stop at "scroll?"
        jr monitor

done:
        ld hl,msg_end
        xor a
        ld (failed),a
        jr finish

fail:
        ld a,1
        ld (failed),a
finish:
        ld (exit_message),hl
        ld a,(acquired)
        or a
        jr z,.released
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_RELEASE
        rst $08
        db NEXTZXOS_M_DRVAPI
.released:
        ld sp,(saved_sp)            ; leave the private stack before unmapping
        ld a,(work_mapped)
        or a
        jr z,.unmapped
        ld bc,NEXTREG_SELECT
        ld a,NXR_MMU3
        out (c),a
        inc b
        ld a,(saved_mmu3)
        out (c),a
        ld a,(work_bank)
        call free_bank
.unmapped:
        ld bc,NEXTREG_SELECT
        ld a,NXR_TURBO
        out (c),a
        inc b
        ld a,(saved_speed)
        out (c),a
        dec b
        ld a,(saved_select)
        out (c),a
        ld hl,(exit_message)
        ld a,(failed)
        or a
        jr nz,.report
        call print_z
        or a
        ret
.report:
        xor a                       ; custom error report, last char bit 7
        scf
        ret

; HL = bytes, B = count (1-255): "90 3C 64 ".
print_bytes:
        ld a,(hl)
        push hl
        push bc
        call print_hex
        ld a,' '
        rst $10
        pop bc
        pop hl
        inc hl
        djnz print_bytes
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
        add a,7                     ; 'A' - '9' - 1
.out:
        rst $10
        ret

print_z:
        ld a,(hl)
        inc hl
        or a
        ret z
        push hl
        rst $10
        pop hl
        jr print_z

; Out: carry set and A=bank on success.
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

        include "../lib/midiin.s"

msg_start:   db 13,"MIDIMON: MIDI in hex; SPACE ends",13,0
msg_end:     db "MIDIMON: end",13,0
msg_cut:     db "...",0
err_memory:  db "MIDIMON: out of memory bank",'s'+$80
err_driver:  db "MIDIMON: GOLEM.DRV missing or in us",'e'+$80
err_no_rx:   db "MIDIMON: GOLEM.DRV has no RX (ABI 0.2",')'+$80
err_read:    db "MIDIMON: driver read erro",'r'+$80

saved_sp:     dw 0
exit_message: dw 0
saved_select: db 0
saved_speed:  db 0
saved_mmu3:   db 0
work_bank:    db 0
work_mapped:  db 0
acquired:     db 0
failed:       db 0
sysex_cut:    db 0
