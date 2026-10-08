; golem-next .GOLEM module: byte reader over a file of any size (#14).
; Included by src/dot/golem_cli.s; not assembled on its own. Uses the
; constants and labels defined there and in the other modules.
;
; The file lives in 8K banks listed in file_banks. Positions are 24-bit file
; offsets. rd_pos/rd_end (3 bytes each, contiguous, in that order) describe
; the range being read; a track keeps the same six bytes at ST_CURSOR/ST_END.
; The bank holding the byte being read is mapped at MMU7 ($E000-$FFFF).

; Out: carry set and A=byte if rd_pos < rd_end, and rd_pos advances.
;      Carry clear at the end of the range. Preserves BC, DE, HL.
rd_byte:
        push hl
        push de
        push bc
        ld hl,(rd_pos)
        ld de,(rd_end)
        or a
        sbc hl,de
        ld a,(rd_end+2)
        ld d,a
        ld a,(rd_pos+2)
        sbc a,d
        jp nc,.at_end               ; rd_pos >= rd_end
        ld hl,(rd_pos)              ; bank index = offset >> 13
        ld a,h
        rlca
        rlca
        rlca
        and $07
        ld e,a
        ld a,(rd_pos+2)
        add a,a
        add a,a
        add a,a
        or e
        ld e,a
        ld a,(rd_mapped)
        cp e
        jp z,.mapped
        ld a,e
        ld (rd_mapped),a
        ld d,0
        push hl
        ld hl,file_banks
        add hl,de
        ld e,(hl)
        ld bc,NEXTREG_SELECT
        ld a,NXR_MMU7
        out (c),a
        inc b
        out (c),e
        pop hl
.mapped:
        ld a,h                      ; HL=$E000 + offset within the bank
        and $1f
        or $e0
        ld h,a
        ld a,(hl)
        ld hl,(rd_pos)
        inc hl
        ld (rd_pos),hl
        ld e,a
        ld a,h
        or l
        jp nz,.advanced
        ld hl,rd_pos+2
        inc (hl)
.advanced:
        ld a,e
        pop bc
        pop de
        pop hl
        scf
        ret
.at_end:
        pop bc
        pop de
        pop hl
        or a
        ret

; Like rd_byte, but rd_pos does not move.
rd_peek:
        call rd_byte
        ret nc
        push hl
        ld hl,(rd_pos)
        dec hl
        ld (rd_pos),hl
        inc hl
        push af
        ld a,h
        or l
        jp nz,.done
        ld hl,rd_pos+2
        dec (hl)
.done:
        pop af
        pop hl
        scf
        ret

; Copy the cursor and end of the track at IX into rd_pos/rd_end. Each event
; starts with a fresh MMU7 mapping: OS calls between events (the driver API,
; ACQUIRE) may have changed MMU7, and one NextReg write per event is cheap.
rd_load:
        ld a,$ff
        ld (rd_mapped),a
        push ix
        pop hl
        ld de,rd_pos
        ld bc,6
        ldir
        ret

; Store rd_pos as the cursor of the track at IX.
rd_store:
        ld hl,(rd_pos)
        ld (ix+ST_CURSOR),l
        ld (ix+ST_CURSOR+1),h
        ld a,(rd_pos+2)
        ld (ix+ST_CURSOR+2),a
        ret

; In: HL=length. Carry set if rd_pos + HL <= rd_end; then rd_pos is NOT moved
; and rd_limit holds rd_pos + HL. Carry clear otherwise.
rd_check_len:
        ld de,(rd_pos)
        add hl,de
        ld (rd_limit),hl
        ld a,(rd_pos+2)
        adc a,0
        ld (rd_limit+2),a
        ld d,a                      ; D=limit high byte
        ld hl,(rd_end)
        ld bc,(rd_limit)
        or a
        sbc hl,bc
        ld a,(rd_end+2)
        sbc a,d
        ccf                         ; carry set when rd_end >= limit
        ret

; In: HL=length. Move rd_pos forward by HL if it stays within rd_end.
rd_skip:
        call rd_check_len
        ret nc
        ld hl,(rd_limit)
        ld (rd_pos),hl
        ld a,(rd_limit+2)
        ld (rd_pos+2),a
        scf
        ret

; Read a standard 1..4-byte VLQ through rd_byte. Result little-endian in
; vlq_value. Carry set on success.
rd_vlq:
        xor a
        ld (vlq_value),a
        ld (vlq_value+1),a
        ld (vlq_value+2),a
        ld (vlq_value+3),a
        ld (vlq_count),a
.next:
        call rd_byte
        ret nc
        ld (vlq_byte),a
        call shift_vlq_7
        ld a,(vlq_byte)
        and $7f
        ld b,a
        ld a,(vlq_value)
        or b
        ld (vlq_value),a
        ld a,(vlq_count)
        inc a
        ld (vlq_count),a
        ld b,a
        ld a,(vlq_byte)
        bit 7,a
        jp z,.good
        ld a,b
        cp 4
        jp c,.next
        or a
        ret
.good:
        scf
        ret

shift_vlq_7:
        ld b,7
.one:
        ld a,(vlq_value)
        add a,a
        ld (vlq_value),a
        ld a,(vlq_value+1)
        rla
        ld (vlq_value+1),a
        ld a,(vlq_value+2)
        rla
        ld (vlq_value+2),a
        ld a,(vlq_value+3)
        rla
        ld (vlq_value+3),a
        djnz .one
        ret

; Read four bytes and compare them with the text at HL. Z if equal.
; Carry clear if the range ended first.
rd_match4:
        ld b,4
        ld c,0                      ; C=0 while all bytes matched
.loop:
        call rd_byte
        ret nc
        cp (hl)
        jp z,.same
        ld c,1
.same:
        inc hl
        djnz .loop
        ld a,c
        or a                        ; Z when all four matched
        scf
        ret

; Read a 32-bit big-endian chunk length. Out: carry set, length in
; chunk_length (24-bit little-endian); the top byte must be zero.
rd_chunk_length:
        call rd_byte
        ret nc
        or a
        jp nz,.bad
        call rd_byte
        ret nc
        ld (chunk_length+2),a
        call rd_byte
        ret nc
        ld (chunk_length+1),a
        call rd_byte
        ret nc
        ld (chunk_length),a
        scf
        ret
.bad:
        or a
        ret

; rd_pos + chunk_length -> rd_limit; carry set if within rd_end.
rd_check_chunk:
        ld hl,(rd_pos)
        ld de,(chunk_length)
        add hl,de
        ld (rd_limit),hl
        ld a,(rd_pos+2)
        ld b,a
        ld a,(chunk_length+2)
        adc a,b
        jp c,.bad                   ; beyond 16 MB
        ld (rd_limit+2),a
        ld d,a
        ld hl,(rd_end)
        ld bc,(rd_limit)
        or a
        sbc hl,bc
        ld a,(rd_end+2)
        sbc a,d
        ccf
        ret
.bad:
        or a
        ret
