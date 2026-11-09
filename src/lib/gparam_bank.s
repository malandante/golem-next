; gp_* sound-parameter library (gparam.s) as a loadable 8K bank, for clients
; that cannot include the source: ZX Basic (src/lib/gparam.bas), C or any
; language that can map a bank and call an address. MIT licence, like
; src/lib/gparam.s.
;
; Include this file from a top file that sets the address of the slot where
; the bank will be mapped (gparam_4000.s ... gparam_e000.s):
;         org <slot address>
;         include "gparam_bank.s"
; The bank holds the code, the buffers (GP_MAX_DATA 256) and the 16-byte
; driver buffer, so it must be mapped at $4000 or above.
;
; Calls: map the bank in its slot and CALL slot address + 3 x n:
;   0 init      no arguments: the library writes and reads with GOLEM.DRV
;   1 info      A = page, HL = destination, B = its size (gp_info)
;   2 write     HL = request block (gp_write)
;   3 read      HL = request block (gp_read)
;   4 blob_put  HL = file block (gp_blob_put)
;   5 blob_get  HL = file block (gp_blob_get)
;   6 update    B = WRITE budget, once per frame (gp_update)
;   7 result    A = state, B = error, DE = detail, C:HL = bytes done
;   8 reserved  (returns at once)
; Same rules as gparam.s: carry and A = GP_ERR_* when a call is refused, IX
; preserved, IY unused. Every entry maps the ROM in MMU0/1 for the call and
; restores them, so the caller may run from slot 1. The request block, the
; data, the destination, the file block and its bank table are read and
; written during later updates too: keep them where they stay visible, out
; of MMU0/1, this slot and the file block's MMU slot, until the operation
; ends. The stack may not lie in MMU0/1 or in this slot either.
; At slot address + 27: "GPAR", major 1, minor 0, so a loader can check it.

GP_MAX_DATA     equ 256

gpb_table:
        jp gpb_e0
        jp gpb_e1
        jp gpb_e2
        jp gpb_e3
        jp gpb_e4
        jp gpb_e5
        jp gpb_e6
        jp gpb_e7
        jp gpb_e8
gpb_signature:
        db "GPAR",1,0

gpb_e0:
        ld (gpb_hl),hl
        ld hl,gpb_init
        jp gpb_rom
gpb_e1:
        ld (gpb_hl),hl
        ld hl,gp_info
        jp gpb_rom
gpb_e2:
        ld (gpb_hl),hl
        ld hl,gp_write
        jp gpb_rom
gpb_e3:
        ld (gpb_hl),hl
        ld hl,gp_read
        jp gpb_rom
gpb_e4:
        ld (gpb_hl),hl
        ld hl,gp_blob_put
        jp gpb_rom
gpb_e5:
        ld (gpb_hl),hl
        ld hl,gp_blob_get
        jp gpb_rom
gpb_e6:
        ld (gpb_hl),hl
        ld hl,gp_update
        jp gpb_rom
gpb_e7:
        ld (gpb_hl),hl
        ld hl,gp_result
        jp gpb_rom
gpb_e8:
        or a
        ret

; HL = routine; A, B, C, DE and gpb_hl are its arguments. Returns its A, B,
; C, DE, HL and flags, with MMU0/1 and the NextReg selector as they were.
gpb_rom:
        ld (gpb_target),hl
        ld (gpb_bc),bc
        ld (gpb_af),a
        ld bc,GP_NEXTREG_SELECT
        in a,(c)
        ld (gpb_select),a
        ld a,$50
        out (c),a
        inc b
        in a,(c)
        ld (gpb_mmu0),a
        ld a,$ff
        out (c),a
        dec b
        ld a,$51
        out (c),a
        inc b
        in a,(c)
        ld (gpb_mmu1),a
        ld a,$ff
        out (c),a
        dec b
        ld a,(gpb_select)
        out (c),a
        ld bc,(gpb_bc)
        ld a,(gpb_af)
        ld hl,(gpb_hl)
        call gpb_jump
        ld (gpb_bc),bc
        push af
        ld bc,GP_NEXTREG_SELECT
        in a,(c)
        ld (gpb_select),a
        ld a,$50
        out (c),a
        inc b
        ld a,(gpb_mmu0)
        out (c),a
        dec b
        ld a,$51
        out (c),a
        inc b
        ld a,(gpb_mmu1)
        out (c),a
        dec b
        ld a,(gpb_select)
        out (c),a
        pop af
        ld bc,(gpb_bc)
        ret

gpb_jump:
        push hl
        ld hl,(gpb_target)
        ex (sp),hl
        ret

gpb_init:
        ld hl,gpb_io
        jp gp_init

        include "gparam.s"

gpb_hl:         dw 0
gpb_bc:         dw 0
gpb_af:         db 0
gpb_target:     dw 0
gpb_select:     db 0
gpb_mmu0:       db 0
gpb_mmu1:       db 0
gpb_io:         ds 16
