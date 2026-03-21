        .setcpu "6502"

BASIC_GLOBAL    = $BE00
BASIC_VECTOUT   = $BE30
BASIC_VECTIN    = $BE32
COUT1           = $FDF0
CTRL_E          = $05
CTRL_K          = $0B
NBYTES_MAX      = $20

STATE_IDLE      = $00
STATE_ACTIVE    = $01

PARSE_MODE_FALLBACK    = $00
PARSE_MODE_COMPOSEONLY = $01

JAMO_KIND_INITIAL = $00
JAMO_KIND_VOWEL   = $01

        .segment "CODE"

start:
        jsr     check_environment
        bcs     unsupported_environment
        jsr     install_hooks
        jsr     print_banner
        rts

unsupported_environment:
        jsr     print_unsupported
        rts

check_environment:
        lda     BASIC_GLOBAL
        cmp     #$4C
        bne     not_prodos
        lda     BASIC_GLOBAL+3
        cmp     #$4C
        bne     not_prodos
        clc
        rts

not_prodos:
        sec
        rts

install_hooks:
        lda     BASIC_VECTOUT
        sta     saved_output
        lda     BASIC_VECTOUT+1
        sta     saved_output+1
        lda     BASIC_VECTIN
        sta     saved_input
        lda     BASIC_VECTIN+1
        sta     saved_input+1

        lda     #<output_hook
        sta     BASIC_VECTOUT
        lda     #>output_hook
        sta     BASIC_VECTOUT+1
        lda     #<input_hook
        sta     BASIC_VECTIN
        lda     #>input_hook
        sta     BASIC_VECTIN+1
        rts

print_banner:
        ldx     #$00

print_loop:
        lda     banner,x
        beq     print_done
        jsr     call_saved_output
        inx
        bne     print_loop

print_done:
        rts

print_unsupported:
        ldx     #$00

unsupported_loop:
        lda     unsupported_banner,x
        beq     unsupported_done
        jsr     COUT1
        inx
        bne     unsupported_loop

unsupported_done:
        rts

output_hook:
        sta     output_char
        txa
        pha
        tya
        pha

        lda     output_char
        and     #$7F
        cmp     #CTRL_K
        beq     output_start_span
        cmp     #CTRL_E
        beq     output_end_or_pass

        lda     output_state
        beq     output_passthrough

        ldx     output_length
        cpx     #NBYTES_MAX
        bcs     output_overflow_store
        lda     output_char
        sta     output_buffer,x
        inx
        stx     output_length
        jmp     output_return

output_overflow_store:
        lda     #$01
        sta     output_overflow
        jmp     output_return

output_start_span:
        lda     #STATE_ACTIVE
        sta     output_state
        lda     #$00
        sta     output_length
        sta     output_overflow
        jmp     output_return

output_end_or_pass:
        lda     output_state
        beq     output_passthrough
        jsr     flush_output_span
        jmp     output_return

output_passthrough:
        lda     output_char
        jsr     call_saved_output

output_return:
        pla
        tay
        pla
        tax
        lda     output_char
        rts

input_hook:
input_fetch:
        jsr     call_saved_input
        sta     input_char
        and     #$7F
        cmp     #CTRL_K
        beq     input_start_span
        cmp     #CTRL_E
        beq     input_end_or_pass

        lda     input_state
        beq     input_return_char

        ldx     input_length
        cpx     #NBYTES_MAX
        bcs     input_overflow_store
        lda     input_char
        sta     input_buffer,x
        inx
        stx     input_length
        jmp     input_fetch

input_overflow_store:
        lda     #$01
        sta     input_overflow
        jmp     input_fetch

input_start_span:
        lda     input_state
        bne     input_store_literal
        lda     #STATE_ACTIVE
        sta     input_state
        lda     #$00
        sta     input_length
        sta     input_overflow
        jmp     input_fetch

input_store_literal:
        ldx     input_length
        cpx     #NBYTES_MAX
        bcs     input_fetch
        lda     input_char
        sta     input_buffer,x
        inx
        stx     input_length
        jmp     input_fetch

input_end_or_pass:
        lda     input_state
        beq     input_return_char
        jsr     flush_input_span
        jmp     input_fetch

input_return_char:
        lda     input_char
        rts

flush_input_span:
        lda     #<input_buffer
        sta     <parse_ptr
        lda     #>input_buffer
        sta     <parse_ptr+1
        lda     input_length
        sta     parse_length
        lda     #PARSE_MODE_COMPOSEONLY
        sta     parse_mode
        jsr     parse_and_emit_span
        lda     #STATE_IDLE
        sta     input_state
        lda     #$00
        sta     input_length
        sta     input_overflow
        rts

flush_output_span:
        lda     #<output_buffer
        sta     <parse_ptr
        lda     #>output_buffer
        sta     <parse_ptr+1
        lda     output_length
        sta     parse_length
        lda     #PARSE_MODE_FALLBACK
        sta     parse_mode
        jsr     parse_and_emit_span
        lda     #STATE_IDLE
        sta     output_state
        lda     #$00
        sta     output_length
        sta     output_overflow
        rts

parse_and_emit_span:
        ldx     #$00

parse_loop:
        cpx     parse_length
        bcs     parse_done
        stx     parse_index
        jsr     try_emit_syllable
        bcs     parse_advance
        jsr     try_emit_standalone_jamo
        bcs     parse_advance
        lda     parse_mode
        bne     parse_skip_raw
        ldy     parse_index
        lda     (parse_ptr),y
        jsr     call_saved_output
        ldx     parse_index
        inx
        jmp     parse_loop

parse_skip_raw:
        ldx     parse_index
        inx
        jmp     parse_loop

parse_advance:
        ldx     parse_index
        clc
        lda     consumed_count
        adc     parse_index
        tax
        jmp     parse_loop

parse_done:
        rts

try_emit_syllable:
        ldy     parse_index
        lda     (parse_ptr),y
        jsr     map_initial
        bcs     try_fail
        sta     l_index

        iny
        cpy     parse_length
        bcs     try_fail
        sty     token_index
        jsr     map_vowel_token
        bcs     try_fail
        sta     v_index

        lda     #$01
        sta     consumed_count
        clc
        adc     token_size
        sta     consumed_count

        lda     #$00
        sta     t_index

        ldy     token_index
        lda     token_size
        cmp     #$02
        bcc     after_vowel_extra
        iny
after_vowel_extra:
        iny
        cpy     parse_length
        bcs     compose_current

        sty     token_index
        jsr     map_final_token
        bcs     compose_current
        sta     candidate_t

        lda     token_size
        cmp     #$01
        bne     use_final

        sty     lookahead_index
        iny
        cpy     parse_length
        bcs     use_final

        sty     token_index
        jsr     map_vowel_token
        bcs     use_final

        ldy     lookahead_index
        lda     (parse_ptr),y
        jsr     is_base_consonant
        bcc     use_final
        jmp     compose_current

use_final:
        lda     candidate_t
        sta     t_index
        clc
        lda     consumed_count
        adc     token_size
        sta     consumed_count

compose_current:
        jsr     emit_modified_syllable
        sec
        rts

try_fail:
        clc
        rts

try_emit_standalone_jamo:
        ldy     parse_index
        sty     token_index
        jsr     map_vowel_token
        bcc     emit_standalone_vowel

        ldy     parse_index
        lda     (parse_ptr),y
        jsr     map_initial
        bcs     standalone_fail
        sta     token_value
        lda     #$01
        sta     consumed_count
        lda     #JAMO_KIND_INITIAL
        sta     jamo_kind
        jsr     emit_modified_jamo
        sec
        rts

emit_standalone_vowel:
        sta     token_value
        lda     token_size
        sta     consumed_count
        lda     #JAMO_KIND_VOWEL
        sta     jamo_kind
        jsr     emit_modified_jamo
        sec
        rts

standalone_fail:
        clc
        rts

emit_modified_syllable:
        lda     #$00
        sta     code_lo
        lda     #$4C
        sta     code_hi

        ldx     l_index
        lda     l_offset_lo,x
        clc
        adc     code_lo
        sta     code_lo
        lda     l_offset_hi,x
        adc     code_hi
        sta     code_hi

        ldx     v_index
        lda     v_offset_lo,x
        clc
        adc     code_lo
        sta     code_lo
        lda     v_offset_hi,x
        adc     code_hi
        sta     code_hi

        lda     t_index
        clc
        adc     code_lo
        sta     code_lo
        bcc     emit_modified_pair
        inc     code_hi

emit_modified_pair:
        lda     code_hi
        jsr     call_saved_output
        lda     code_lo
        jsr     call_saved_output
        rts

emit_modified_jamo:
        lda     #$41
        sta     code_hi
        lda     jamo_kind
        beq     emit_initial_jamo

emit_initial_jamo:
        lda     token_value
        sta     code_lo
        jmp     emit_modified_pair

emit_vowel_jamo:
        lda     token_value
        clc
        adc     #$61
        sta     code_lo
        jmp     emit_modified_pair

map_initial:
        and     #$7F
        ldx     #$00

map_initial_loop:
        cmp     initial_chars,x
        beq     map_initial_found
        inx
        cpx     #INITIAL_COUNT
        bcc     map_initial_loop
        sec
        rts

map_initial_found:
        lda     initial_indices,x
        clc
        rts

map_vowel_token:
        ldy     token_index
        lda     (parse_ptr),y
        and     #$7F
        sta     token_char
        lda     #$01
        sta     token_size
        cpy     parse_length
        bcs     map_vowel_single
        iny
        cpy     parse_length
        bcs     map_vowel_single
        lda     (parse_ptr),y
        and     #$7F
        sta     token_char_next
        ldx     #$00

map_vowel_pair_loop:
        lda     token_char
        cmp     vowel_pair_first,x
        bne     map_vowel_pair_next
        lda     token_char_next
        cmp     vowel_pair_second,x
        beq     map_vowel_pair_found
map_vowel_pair_next:
        inx
        cpx     #VOWEL_PAIR_COUNT
        bcc     map_vowel_pair_loop

map_vowel_single:
        lda     token_char
        ldx     #$00

map_vowel_loop:
        cmp     vowel_chars,x
        beq     map_vowel_found
        inx
        cpx     #VOWEL_COUNT
        bcc     map_vowel_loop
        sec
        rts

map_vowel_pair_found:
        lda     #$02
        sta     token_size
        lda     vowel_pair_indices,x
        clc
        rts

map_vowel_found:
        lda     vowel_indices,x
        clc
        rts

map_final_token:
        ldy     token_index
        lda     (parse_ptr),y
        and     #$7F
        sta     token_char
        lda     #$01
        sta     token_size
        cpy     parse_length
        bcs     map_final_single
        iny
        cpy     parse_length
        bcs     map_final_single
        lda     (parse_ptr),y
        and     #$7F
        sta     token_char_next
        ldx     #$00

map_final_pair_loop:
        lda     token_char
        cmp     final_pair_first,x
        bne     map_final_pair_next
        lda     token_char_next
        cmp     final_pair_second,x
        beq     map_final_pair_found
map_final_pair_next:
        inx
        cpx     #FINAL_PAIR_COUNT
        bcc     map_final_pair_loop

map_final_single:
        lda     token_char
        ldx     #$00

map_final_loop:
        cmp     final_chars,x
        beq     map_final_found
        inx
        cpx     #FINAL_COUNT
        bcc     map_final_loop
        sec
        rts

map_final_pair_found:
        lda     #$02
        sta     token_size
        lda     final_pair_indices,x
        clc
        rts

map_final_found:
        lda     final_indices,x
        clc
        rts

is_base_consonant:
        and     #$7F
        cmp     #'A'
        beq     is_consonant_yes
        cmp     #'C'
        beq     is_consonant_yes
        cmp     #'D'
        beq     is_consonant_yes
        cmp     #'E'
        beq     is_consonant_yes
        cmp     #'F'
        beq     is_consonant_yes
        cmp     #'G'
        beq     is_consonant_yes
        cmp     #'Q'
        beq     is_consonant_yes
        cmp     #'R'
        beq     is_consonant_yes
        cmp     #'S'
        beq     is_consonant_yes
        cmp     #'T'
        beq     is_consonant_yes
        cmp     #'V'
        beq     is_consonant_yes
        cmp     #'W'
        beq     is_consonant_yes
        cmp     #'X'
        beq     is_consonant_yes
        cmp     #'Z'
        beq     is_consonant_yes
        cmp     #'e'
        beq     is_consonant_yes
        cmp     #'q'
        beq     is_consonant_yes
        cmp     #'r'
        beq     is_consonant_yes
        cmp     #'t'
        beq     is_consonant_yes
        cmp     #'w'
        beq     is_consonant_yes
        clc
        rts

is_consonant_yes:
        sec
        rts

call_saved_input:
        lda     saved_input
        sta     input_call+1
        lda     saved_input+1
        sta     input_call+2
input_call:
        jsr     $FFFF
        rts

call_saved_output:
        pha
        lda     saved_output
        sta     output_call+1
        lda     saved_output+1
        sta     output_call+2
        pla
output_call:
        jsr     $FFFF
        rts

        .segment "ZEROPAGE"

parse_ptr:
        .res    2

        .segment "RODATA"

banner:
        .byte   $C1, $B2, $C8, $C1, $CE, $A0
        .byte   $C9, $CE, $D3, $D4, $C1, $CC, $CC, $C5, $C4
        .byte   $8D, $00

unsupported_banner:
        .byte   $D0, $D2, $CF, $C4, $CF, $D3, $A0
        .byte   $CF, $CE, $CC, $D9, $8D, $00

initial_chars:
        .byte   'R', 'r', 'S', 'E', 'e', 'F', 'A', 'Q', 'q', 'T', 't', 'D', 'W', 'w'
        .byte   'C', 'Z', 'X', 'V', 'G'
initial_indices:
        .byte   $00, $01, $02, $03, $04, $05, $06, $07, $08, $09, $0A, $0B, $0C, $0D
        .byte   $0E, $0F, $10, $11, $12
INITIAL_COUNT = * - initial_chars

vowel_chars:
        .byte   'K', 'O', 'I', 'o', 'J', 'P', 'U', 'p', 'H', 'Y', 'N', 'B', 'M', 'L'
vowel_indices:
        .byte   $00, $01, $02, $03, $04, $05, $06, $07, $08, $0C, $0D, $11, $12, $14
VOWEL_COUNT = * - vowel_chars

vowel_pair_first:
        .byte   'H', 'H', 'H', 'N', 'N', 'N', 'M'
vowel_pair_second:
        .byte   'K', 'O', 'L', 'J', 'P', 'L', 'L'
vowel_pair_indices:
        .byte   $09, $0A, $0B, $0E, $0F, $10, $13
VOWEL_PAIR_COUNT = * - vowel_pair_first

final_chars:
        .byte   'R', 'r', 'S', 'E', 'F', 'A', 'Q', 'T', 't', 'D', 'W', 'C', 'Z', 'X', 'V', 'G'
final_indices:
        .byte   $01, $02, $04, $07, $08, $10, $11, $13, $14, $15, $16, $17, $18, $19, $1A, $1B
FINAL_COUNT = * - final_chars

final_pair_first:
        .byte   'R', 'S', 'S', 'F', 'F', 'F', 'F', 'F', 'F', 'F', 'Q'
final_pair_second:
        .byte   'T', 'W', 'G', 'R', 'A', 'Q', 'T', 'X', 'V', 'G', 'T'
final_pair_indices:
        .byte   $03, $05, $06, $09, $0A, $0B, $0C, $0D, $0E, $0F, $12
FINAL_PAIR_COUNT = * - final_pair_first

l_offset_lo:
        .byte   $00, $4C, $98, $E4, $30, $7C, $C8, $14, $60, $AC, $F8, $44, $90, $DC
        .byte   $28, $74, $C0, $0C, $58
l_offset_hi:
        .byte   $00, $02, $04, $06, $09, $0B, $0D, $10, $12, $14, $17, $19, $1B, $1E
        .byte   $20, $22, $25, $27, $29

v_offset_lo:
        .byte   $00, $1C, $38, $54, $70, $8C, $A8, $C4, $E0, $FC, $18, $34, $50, $6C
        .byte   $88, $A4, $C0, $DC, $F8, $14, $30
v_offset_hi:
        .byte   $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $01, $01, $01
        .byte   $01, $01, $01, $01, $01, $02, $02

        .segment "DATA"

saved_output:
        .word   COUT1
saved_input:
        .word   $0000

input_state:
        .byte   STATE_IDLE
input_length:
        .byte   $00
input_overflow:
        .byte   $00
input_char:
        .byte   $00
input_buffer:
        .res    NBYTES_MAX

output_state:
        .byte   STATE_IDLE
output_length:
        .byte   $00
output_overflow:
        .byte   $00
output_char:
        .byte   $00
output_buffer:
        .res    NBYTES_MAX

parse_length:
        .byte   $00
parse_index:
        .byte   $00
consumed_count:
        .byte   $00
lookahead_index:
        .byte   $00
token_index:
        .byte   $00
token_size:
        .byte   $00

l_index:
        .byte   $00
v_index:
        .byte   $00
t_index:
        .byte   $00
candidate_t:
        .byte   $00
parse_mode:
        .byte   $00
token_char:
        .byte   $00
token_char_next:
        .byte   $00
token_value:
        .byte   $00
jamo_kind:
        .byte   $00

code_lo:
        .byte   $00
code_hi:
        .byte   $00
