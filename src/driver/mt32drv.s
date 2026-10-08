; golem-next minimal NextZXOS driver image.
; Assemble at origin 0. The output is 512 bytes followed by relocations.

        opt zxnext
        include "../../include/mt32_api.inc"

UART_TX        equ $133b
UART_RX_BAUD   equ $143b
UART_SELECT    equ $153b
UART_FRAME     equ $163b
NEXTREG_SELECT equ $243b
NEXTREG_DATA   equ $253b

; NextReg $A2 while acquired: bits 7:6=11 stereo I2S and bit 4=1 PCM_DOUT from
; the Pi (docs/architecture.md); $D2 is the value validated on hardware with
; mt32-pi on 2026-10-05.
I2S_FROM_PI    equ $d2

        org $0000

api_entry:
        ld a,b
        or a
        jr z,query
        dec a
        jr z,acquire
        dec a
reloc_dispatch_write:
        jp z,write
        dec a
reloc_dispatch_status:
        jp z,status
        dec a
reloc_dispatch_drain:
        jp z,drain_status
        dec a
reloc_dispatch_release:
        jp z,release
        dec a
reloc_dispatch_read:
        jp z,read

unsupported:
        xor a                   ; A=0 is the NextZXOS unsupported-call result
        scf
        ret

; B=0 QUERY
; Out: BC="MT", DE=$0002, HL=capabilities.
query:
        ld bc,MT32_SIGNATURE
        ld de,MT32_ABI_VERSION
        ld hl,MT32_CAP_PARTIAL_WRITE | MT32_CAP_RX_NONBLOCKING
        or a
        ret

; B=1 ACQUIRE
; Saves all readable state affected by this driver, selects the Pi UART,
; configures 31250 baud 8N1 and enables I2S reception from the Pi (NextReg
; $A2). The Pi UART divisor is write-only; RELEASE leaves it at 31250.
acquire:
reloc_acquire_read:
        ld a,(acquired)
        or a
reloc_acquire_busy:
        jp nz,error_busy

        ld bc,NEXTREG_SELECT
        in a,(c)
reloc_save_nextreg_selector:
        ld (saved_nextreg_selector),a
        ld a,$a0
        out (c),a
        inc b                   ; $253b
        in a,(c)
reloc_save_nextreg_a0:
        ld (saved_nextreg_a0),a
        or $30                  ; UART enabled, Pi wiring direction
        and $3f                 ; keep reserved bits 7:6 clear
        out (c),a

        dec b                   ; $243b: I2S configuration
        ld a,$a2
        out (c),a
        inc b                   ; $253b
        in a,(c)
reloc_save_nextreg_a2:
        ld (saved_nextreg_a2),a
        ld a,I2S_FROM_PI
        out (c),a

        dec b                   ; $243b: select system-clock register
        ld a,$11
        out (c),a
        inc b                   ; $253b
        in a,(c)
        and $07                 ; video timing / system-clock index 0..7
        add a,a
        ld e,a
        ld d,0
reloc_baud_table:
        ld hl,baud_31250
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)               ; DE=prescaler for exactly 31250 baud

        dec b                   ; $243b
reloc_restore_selector_after_acquire:
        ld a,(saved_nextreg_selector)
        out (c),a

        ld bc,UART_SELECT
        in a,(c)
reloc_save_uart_select:
        ld (saved_uart_select),a
        ld a,$50                ; Pi UART + write top prescaler bits (zero)
        out (c),a

        ld bc,UART_FRAME
        in a,(c)
reloc_save_uart_frame:
        ld (saved_uart_frame),a

        ld bc,UART_RX_BAUD
        ld a,e
        and $7f                 ; prescaler bits 6:0
        out (c),a
        ld a,d
        rl e                    ; prescaler bit 7 into carry
        rla                     ; prescaler bits 13:7
        or $80
        out (c),a

        ld bc,UART_FRAME
        ld a,$98                ; reset FIFOs, 8N1
        out (c),a
        ld a,$18
        out (c),a

        ld a,1
reloc_acquire_write:
        ld (acquired),a
        or a
        ret

; B=2 WRITE
; In: HL=visible buffer ($4000..$ffff), DE=length.
; Out: BC=accepted prefix (0..16). Never waits for FIFO capacity.
write:
reloc_write_check:
        ld a,(acquired)
        or a
reloc_write_not_acquired:
        jp z,error_not_acquired
        ld a,h
        cp $40
reloc_write_invalid:
        jp c,error_invalid
reloc_write_enter:
        call pi_enter
        ld a,d                  ; A=min(DE,16)
        or a
        ld a,MT32_MAX_WRITE
        jr nz,write_budget
        ld a,e
        cp MT32_MAX_WRITE
        jr c,write_budget
        ld a,MT32_MAX_WRITE
write_budget:
        push de                 ; requested length
        ld e,a                  ; E=bytes still allowed, D=bytes moved
        ld d,0
        ld bc,UART_TX
        or a
        jr z,write_end
write_loop:
        in a,(c)                ; BC=UART_TX: status
        and 2                   ; TX FIFO full: zero progress is not an error
        jr nz,write_end
        ld a,(hl)
        out (c),a
        inc d
        inc hl
        ld a,h                  ; stop before wrapping into driver/ROM space
        or l
        jr z,write_end
        dec e
        jr nz,write_loop
write_end:
        ld c,d
        ld b,0                  ; BC=bytes moved
        ex (sp),hl              ; HL=requested length, stack=pointer
        or a
        sbc hl,bc
        ex de,hl                ; DE=remaining
        pop hl                  ; HL=advanced pointer
reloc_write_leave:
        jp pi_leave

; B=3 STATUS
; Out: BC bit 0=acquired, bit 1=TX FIFO full, bit 2=TX FIFO empty,
;             bit 3=RX data available. Always reports the Pi UART.
status:
reloc_status_enter:
        call pi_enter
        ld bc,0
reloc_status_acquired:
        ld a,(acquired)
        or a
        jr z,status_uart
        set 0,c
status_uart:
        push bc
        ld bc,UART_TX
        in a,(c)
        ld d,a
        pop bc
        bit 1,d
        jr z,status_not_full
        set 1,c
status_not_full:
        bit 4,d
        jr z,status_rx
        set 2,c
status_rx:
        bit 0,d
        jr z,status_done
        set 3,c
status_done:
reloc_status_leave:
        jp pi_leave

; B=4 DRAIN_STATUS
; Out: BC=$ffff only when the hardware TX FIFO is empty, else BC=0.
drain_status:
reloc_drain_check:
        ld a,(acquired)
        or a
reloc_drain_not_acquired:
        jp z,error_not_acquired
reloc_drain_enter:
        call pi_enter
        ld bc,UART_TX
        in a,(c)
        ld bc,0
        bit 4,a
        jr z,drain_done
        dec bc
drain_done:
reloc_drain_leave:
        jp pi_leave

; B=5 RELEASE
; Restores readable configuration: UART selection and frame, NextReg $A0, $A2
; and selector. No prescaler bit is written, so the Pi divisor stays a
; coherent 31250 and the ESP divisor is never touched (docs/driver-api.md).
release:
reloc_release_check:
        ld a,(acquired)
        or a
        jr z,error_not_acquired

        ld bc,UART_FRAME
reloc_restore_uart_frame:
        ld a,(saved_uart_frame)
        out (c),a
        ld bc,UART_SELECT
reloc_restore_uart_select:
        ld a,(saved_uart_select)
        and $ef                 ; selection only; do not write prescaler bits
        out (c),a

        ld bc,NEXTREG_SELECT
        in a,(c)
        ld d,a
        ld a,$a0
        out (c),a
        inc b
reloc_restore_nextreg_a0:
        ld a,(saved_nextreg_a0)
        out (c),a
        dec b
        ld a,$a2
        out (c),a
        inc b
reloc_restore_nextreg_a2:
        ld a,(saved_nextreg_a2)
        out (c),a
        dec b
        ld a,d
        out (c),a

        xor a
reloc_release_write:
        ld (acquired),a
        ret

error_busy:
        ld a,MT32_ERR_BUSY
        scf
        ret
error_not_acquired:
        ld a,MT32_ERR_NOT_ACQUIRED
        scf
        ret
error_invalid:
        ld a,MT32_ERR_INVALID
        scf
        ret

; B=6 READ
; In: HL=visible destination buffer ($4000..$ffff), DE=capacity.
; Out: BC=received prefix (0..16), HL advanced, DE remaining.
; Never waits for RX data and never reads an empty FIFO.
read:
reloc_read_check:
        ld a,(acquired)
        or a
reloc_read_not_acquired:
        jp z,error_not_acquired
        ld a,h
        cp $40
reloc_read_invalid:
        jp c,error_invalid
reloc_read_enter:
        call pi_enter
        ld a,d                  ; A=min(DE,16)
        or a
        ld a,MT32_MAX_READ
        jr nz,read_budget
        ld a,e
        cp MT32_MAX_READ
        jr c,read_budget
        ld a,MT32_MAX_READ
read_budget:
        push de                 ; requested length
        ld e,a                  ; E=bytes still allowed, D=bytes moved
        ld d,0
        ld bc,UART_TX
        or a
        jr z,read_end
read_loop:
        in a,(c)                ; BC=UART_TX: status
        and 1                   ; do not consume RX when its FIFO is empty
        jr z,read_end
        inc b                   ; $143B: RX data
        in a,(c)
        dec b
        ld (hl),a
        inc d
        inc hl
        ld a,h                  ; stop before wrapping into driver/ROM space
        or l
        jr z,read_end
        dec e
        jr nz,read_loop
read_end:
        ld c,d
        ld b,0                  ; BC=bytes moved
        ex (sp),hl              ; HL=requested length, stack=pointer
        or a
        sbc hl,bc
        ex de,hl                ; DE=remaining
        pop hl                  ; HL=advanced pointer
reloc_read_leave:
        jp pi_leave

; Select the Pi UART for one call and remember the caller's selection, so that
; another UART user (for example the ESP) between calls cannot divert MIDI.
; Preserves HL and DE.
pi_enter:
        ld bc,UART_SELECT
        in a,(c)
reloc_save_caller_select:
        ld (caller_select),a
        ld a,$40                ; Pi UART; bit 4 clear, prescaler untouched
        out (c),a
        ret

; Restore the caller's UART selection and return success with BC intact.
pi_leave:
        push bc
        ld bc,UART_SELECT
reloc_restore_caller_select:
        ld a,(caller_select)
        and $ef                 ; selection only
        out (c),a
        pop bc
        or a
        ret

acquired:
        db 0
saved_nextreg_selector:
        db 0
saved_nextreg_a0:
        db 0
saved_uart_select:
        db 0
saved_uart_frame:
        db 0
saved_nextreg_a2:
        db 0
caller_select:
        db 0

; Fsys / 31250 for NextReg $11 values 0..7, rounded as in the official UART
; driver table: 28, 28.57, 29.46, 30, 31, 32, 33 and 27 MHz.
baud_31250:
        dw 896,914,943,960,992,1024,1056,864

code_end:
        ds 512-(code_end-api_entry)    ; origin-independent (CI assembles at $0100 too)

; Offsets of the high byte of every absolute address relocated by .INSTALL.
reloc_start:
        dw reloc_dispatch_write+2
        dw reloc_dispatch_status+2
        dw reloc_dispatch_drain+2
        dw reloc_dispatch_release+2
        dw reloc_dispatch_read+2
        dw reloc_acquire_read+2
        dw reloc_acquire_busy+2
        dw reloc_save_nextreg_selector+2
        dw reloc_save_nextreg_a0+2
        dw reloc_baud_table+2
        dw reloc_restore_selector_after_acquire+2
        dw reloc_save_uart_select+2
        dw reloc_save_uart_frame+2
        dw reloc_acquire_write+2
        dw reloc_write_check+2
        dw reloc_write_not_acquired+2
        dw reloc_write_invalid+2
        dw reloc_status_acquired+2
        dw reloc_drain_check+2
        dw reloc_drain_not_acquired+2
        dw reloc_release_check+2
        dw reloc_restore_uart_frame+2
        dw reloc_restore_uart_select+2
        dw reloc_restore_nextreg_a0+2
        dw reloc_release_write+2
        dw reloc_read_check+2
        dw reloc_read_not_acquired+2
        dw reloc_read_invalid+2
        dw reloc_save_nextreg_a2+2
        dw reloc_restore_nextreg_a2+2
        dw reloc_write_enter+2
        dw reloc_write_leave+2
        dw reloc_status_enter+2
        dw reloc_status_leave+2
        dw reloc_drain_enter+2
        dw reloc_drain_leave+2
        dw reloc_read_enter+2
        dw reloc_read_leave+2
        dw reloc_save_caller_select+2
        dw reloc_restore_caller_select+2
reloc_end:
