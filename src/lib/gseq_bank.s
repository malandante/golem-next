; GSEQ library as a loadable 8K bank, for clients that cannot include the
; source: ZX Basic (src/lib/gseq.bas), C or any language that can map a bank
; and call an address. MIT licence, like src/lib/gseq.s.
;
; Include this file from a top file that sets the address of the slot where
; the bank will be mapped (gseq_4000.s ... gseq_e000.s):
;         org <slot address>
;         include "gseq_bank.s"
; The bank holds the code, the 16-byte output buffer, a copy of the bank table
; and the 2048-byte key table, so the client only provides the bank itself.
;
; Calls: map the bank in its slot and CALL slot address + 3 x n:
;   0 init    A = MMU NextReg of the data window ($50-$57, not this slot),
;             B = 0 without key table (no re-strike on resume), else with it,
;             HL = channels the cleanups may touch (bit n = MIDI channel n+1;
;             0 = all), so channels kept for effects are left alone
;   1 open    HL = bank table (count, then the 8K banks of the file);
;             copied here, so it may live anywhere visible during the call;
;             DE = where the sequence starts in the first bank (0-8191)
;   2 start   DE = now (ms)
;   3 pump    DE = now, B = WRITE budget
;   4 pause   DE = now
;   5 resume  DE = now
;   6 stop
;   7 send    HL = message (visible during the call), B = length (1-16)
;   8 query   A = state; HL = 10-byte information block inside this bank:
;             copy it before unmapping the bank. Z clear while busy.
; Same rules as gseq.s: carry and A = GS_ERR_* on error, IX preserved, IY
; unused. Every entry maps the ROM in MMU0/1 for the call and then restores
; them, so the caller may run from slot 1 and the data window may be slot 0
; or 1. Neither the stack nor anything the call reads (the bank table, the
; message of send) may lie in MMU0/1, in this slot or in the data window.
; At slot address + 27: "GSEQ", major 1, minor 0, so a loader can check it.

GSB_MAX_BANKS   equ 224                 ; 8K banks of a 2 MB Next

gsb_table:
        jp gsb_e0
        jp gsb_e1
        jp gsb_e2
        jp gsb_e3
        jp gsb_e4
        jp gsb_e5
        jp gsb_e6
        jp gsb_e7
        jp gsb_e8
gsb_signature:
        db "GSEQ",1,0

; Each entry runs its routine with the ROM in MMU0/1, as GOLEM.DRV requires,
; and then puts back what the caller had there: the caller may run from a
; code bank in slot 1 (ZX Basic paged code) or keep data in slot 0.
gsb_e0:
        ld (gsb_hl),hl
        ld hl,gsb_init
        jp gsb_rom
gsb_e1:
        ld (gsb_hl),hl
        ld hl,gsb_open
        jp gsb_rom
gsb_e2:
        ld (gsb_hl),hl
        ld hl,gs_start
        jp gsb_rom
gsb_e3:
        ld (gsb_hl),hl
        ld hl,gs_pump
        jp gsb_rom
gsb_e4:
        ld (gsb_hl),hl
        ld hl,gs_pause
        jp gsb_rom
gsb_e5:
        ld (gsb_hl),hl
        ld hl,gs_resume
        jp gsb_rom
gsb_e6:
        ld (gsb_hl),hl
        ld hl,gs_stop
        jp gsb_rom
gsb_e7:
        ld (gsb_hl),hl
        ld hl,gs_send
        jp gsb_rom
gsb_e8:
        ld (gsb_hl),hl
        ld hl,gs_query
        jp gsb_rom

; HL = routine; A, B, DE and gsb_hl are its arguments. Returns its A, flags
; and HL (gs_query), with MMU0/1 and the NextReg selector as they were.
gsb_rom:
        ld (gsb_target),hl
        push af
        push bc
        ld bc,GS_NEXTREG_SELECT
        in a,(c)
        ld (gsb_select),a
        ld a,$50
        out (c),a
        inc b
        in a,(c)
        ld (gsb_mmu0),a
        ld a,$ff
        out (c),a
        dec b
        ld a,$51
        out (c),a
        inc b
        in a,(c)
        ld (gsb_mmu1),a
        ld a,$ff
        out (c),a
        dec b
        ld a,(gsb_select)
        out (c),a
        pop bc
        pop af
        ld hl,(gsb_hl)
        call gsb_jump
        push af
        push bc
        ld bc,GS_NEXTREG_SELECT
        in a,(c)
        ld (gsb_select),a
        ld a,$50
        out (c),a
        inc b
        ld a,(gsb_mmu0)
        out (c),a
        dec b
        ld a,$51
        out (c),a
        inc b
        ld a,(gsb_mmu1)
        out (c),a
        dec b
        ld a,(gsb_select)
        out (c),a
        pop bc
        pop af
        ret

gsb_jump:
        push hl
        ld hl,(gsb_target)
        ex (sp),hl
        ret

gsb_init:
        push hl                         ; channel mask
        ld hl,gsb_out
        ld de,0
        inc b
        dec b
        jp z,.init
        ld de,gsb_keys
.init:
        call gs_init
        pop hl
        ld a,h
        or l
        jp z,.done                      ; 0: all channels
        call gs_set_channels
.done:
        ld a,GS_STOPPED
        or a
        ret

gsb_open:
        ld a,(hl)
        cp GSB_MAX_BANKS+1
        jp nc,.too_many
        push de                         ; offset in the first bank
        ld c,a
        ld b,0
        inc bc                          ; the count and the banks
        ld de,gsb_banks
        ldir
        pop de
        ld hl,gsb_banks
        jp gs_open
.too_many:
        ld a,GS_ERR_FORMAT
        scf
        ret

        include "gseq.s"

gsb_hl:         dw 0
gsb_target:     dw 0
gsb_select:     db 0
gsb_mmu0:       db 0
gsb_mmu1:       db 0
gsb_out:        ds 16
gsb_banks:      ds GSB_MAX_BANKS+1
gsb_keys:       ds 2048
gsb_end:
