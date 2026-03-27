        .setcpu "6502"

.ifdef A2HAN_TARGET_DOS33
HOOK_OUTPUT_VEC = $0036
HOOK_INPUT_VEC  = $0038
DOSFET          = $03EA
KEYIN           = $FD1B
.else
HOOK_OUTPUT_VEC = $BE30
HOOK_INPUT_VEC  = $BE32
.endif
BELL            = $FF3A
COUT1           = $FDF0
SPAN_END        = $01
SPAN_START      = $0B

STATE_S0        = $00
STATE_S1        = $01
STATE_S2        = $02
STATE_S3        = $03
STATE_S4        = $04
STATE_S5        = $05
STATE_S6        = $06
STATE_S7        = $07
STATE_S8        = $08

JAMO_KIND_INITIAL = $00
JAMO_KIND_VOWEL   = $01

        .segment "CODE"

start:
        jsr     install_hooks
        jsr     print_banner
        rts

install_hooks:
.ifndef A2HAN_TARGET_DOS33
        lda     HOOK_OUTPUT_VEC
        sta     saved_output
        lda     HOOK_OUTPUT_VEC+1
        sta     saved_output+1
        lda     HOOK_INPUT_VEC
        sta     saved_input
        lda     HOOK_INPUT_VEC+1
        sta     saved_input+1
.endif

        lda     #<output_hook
        sta     HOOK_OUTPUT_VEC
        lda     #>output_hook
        sta     HOOK_OUTPUT_VEC+1
        lda     #<input_hook
        sta     HOOK_INPUT_VEC
        lda     #>input_hook
        sta     HOOK_INPUT_VEC+1
.ifdef A2HAN_TARGET_DOS33
        jsr     DOSFET
.endif
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

output_hook:
        sta     output_char
        txa
        pha
        tya
        pha

        lda     output_char
        and     #$7F
        sta     current_char

        lda     automaton_state
        beq     output_idle

        lda     current_char
        cmp     #SPAN_START
        beq     output_done
        cmp     #SPAN_END
        beq     output_close_span
        jsr     automaton_feed
        jmp     output_done

output_idle:
        lda     current_char
        cmp     #SPAN_START
        beq     output_open_span
        lda     output_char
        jsr     call_saved_output
        jmp     output_done

output_open_span:
        lda     #STATE_S1
        sta     automaton_state

output_done:
        pla
        tay
        pla
        tax
        lda     output_char
        rts

output_close_span:
        jsr     flush_buffered_state
        lda     #STATE_S0
        sta     automaton_state
        jmp     output_done

automaton_feed:
        lda     automaton_state
        cmp     #STATE_S1
        bne     :+
        jmp     handle_state_s1
:       cmp     #STATE_S2
        bne     :+
        jmp     handle_state_s2
:       cmp     #STATE_S3
        bne     :+
        jmp     handle_state_s3
:       cmp     #STATE_S4
        bne     :+
        jmp     handle_state_s4
:       cmp     #STATE_S5
        bne     :+
        jmp     handle_state_s5
:       cmp     #STATE_S6
        bne     :+
        jmp     handle_state_s6
:       cmp     #STATE_S7
        bne     :+
        jmp     handle_state_s7
:       jmp     handle_state_s8

handle_state_s1:
        lda     current_char
        jsr     map_initial
        bcs     s1_try_vowel
        lda     current_char
        jsr     begin_initial
        rts

s1_try_vowel:
        lda     current_char
        jsr     map_vowel_single
        bcs     s1_literal
        lda     current_char
        jsr     emit_standalone_vowel
        rts

s1_literal:
        jsr     emit_literal_char
        rts

handle_state_s2:
        lda     current_char
        jsr     map_initial
        bcs     s2_try_vowel
        jsr     emit_buffered_initial
        lda     current_char
        jsr     begin_initial
        rts

s2_try_vowel:
        lda     current_char
        jsr     map_vowel_single
        bcs     s2_literal
        lda     current_char
        jsr     begin_medial
        rts

s2_literal:
        jsr     emit_buffered_initial
        jsr     emit_literal_char
        lda     #STATE_S1
        sta     automaton_state
        rts

handle_state_s3:
        jsr     try_extend_compound_vowel
        bcc     s3_done

        lda     current_char
        jsr     map_final_single
        bcs     s3_try_initial
        lda     current_char
        jsr     begin_final_single
        rts

s3_try_initial:
        lda     current_char
        jsr     map_initial
        bcs     s3_try_vowel
        jsr     emit_buffered_syllable_open
        lda     current_char
        jsr     begin_initial
        rts

s3_try_vowel:
        lda     current_char
        jsr     map_vowel_single
        bcs     s3_literal
        jsr     emit_buffered_syllable_open
        lda     current_char
        jsr     emit_standalone_vowel
        lda     #STATE_S1
        sta     automaton_state
        rts

s3_literal:
        jsr     emit_buffered_syllable_open
        jsr     emit_literal_char
        lda     #STATE_S1
        sta     automaton_state

s3_done:
        rts

handle_state_s4:
        jsr     try_extend_compound_final
        bcc     s4_done

        lda     current_char
        jsr     map_initial
        bcs     s4_try_vowel
        jsr     emit_buffered_syllable_full
        lda     current_char
        jsr     begin_initial
        rts

s4_try_vowel:
        lda     current_char
        jsr     map_vowel_single
        bcs     s4_literal
        jsr     emit_buffered_syllable_open
        lda     buffered_t1_char
        jsr     begin_initial
        lda     current_char
        jsr     begin_medial
        rts

s4_literal:
        jsr     emit_buffered_syllable_full
        jsr     emit_literal_char
        lda     #STATE_S1
        sta     automaton_state

s4_done:
        rts

handle_state_s5:
        lda     current_char
        jsr     map_initial
        bcs     s5_try_vowel
        jsr     emit_buffered_syllable_full
        lda     current_char
        jsr     begin_initial
        rts

s5_try_vowel:
        lda     current_char
        jsr     map_vowel_single
        bcs     s5_literal
        jsr     emit_buffered_syllable_split_final
        lda     buffered_t2_char
        jsr     begin_initial
        lda     current_char
        jsr     begin_medial
        rts

s5_literal:
        jsr     emit_buffered_syllable_full
        jsr     emit_literal_char
        lda     #STATE_S1
        sta     automaton_state
        rts

handle_state_s6:
        lda     current_char
        jsr     map_final_single
        bcs     s6_try_initial
        lda     current_char
        jsr     begin_final_single
        lda     #STATE_S7
        sta     automaton_state
        rts

s6_try_initial:
        lda     current_char
        jsr     map_initial
        bcs     s6_try_vowel
        jsr     emit_buffered_syllable_open
        lda     current_char
        jsr     begin_initial
        rts

s6_try_vowel:
        lda     current_char
        jsr     map_vowel_single
        bcs     s6_literal
        jsr     emit_buffered_syllable_open
        lda     current_char
        jsr     emit_standalone_vowel
        lda     #STATE_S1
        sta     automaton_state
        rts

s6_literal:
        jsr     emit_buffered_syllable_open
        jsr     emit_literal_char
        lda     #STATE_S1
        sta     automaton_state
        rts

handle_state_s7:
        jsr     try_extend_compound_final
        bcc     s7_done

        lda     current_char
        jsr     map_initial
        bcs     s7_try_vowel
        jsr     emit_buffered_syllable_full
        lda     current_char
        jsr     begin_initial
        rts

s7_try_vowel:
        lda     current_char
        jsr     map_vowel_single
        bcs     s7_literal
        jsr     emit_buffered_syllable_open
        lda     buffered_t1_char
        jsr     begin_initial
        lda     current_char
        jsr     begin_medial
        rts

s7_literal:
        jsr     emit_buffered_syllable_full
        jsr     emit_literal_char
        lda     #STATE_S1
        sta     automaton_state

s7_done:
        rts

handle_state_s8:
        lda     current_char
        jsr     map_initial
        bcs     s8_try_vowel
        jsr     emit_buffered_syllable_full
        lda     current_char
        jsr     begin_initial
        rts

s8_try_vowel:
        lda     current_char
        jsr     map_vowel_single
        bcs     s8_literal
        jsr     emit_buffered_syllable_split_final
        lda     buffered_t2_char
        jsr     begin_initial
        lda     current_char
        jsr     begin_medial
        rts

s8_literal:
        jsr     emit_buffered_syllable_full
        jsr     emit_literal_char
        lda     #STATE_S1
        sta     automaton_state
        rts

flush_buffered_state:
        lda     automaton_state
        cmp     #STATE_S2
        beq     flush_initial
        cmp     #STATE_S3
        beq     flush_open
        cmp     #STATE_S4
        beq     flush_full
        cmp     #STATE_S5
        beq     flush_full
        cmp     #STATE_S6
        beq     flush_open
        cmp     #STATE_S7
        beq     flush_full
        cmp     #STATE_S8
        beq     flush_full
        rts

flush_initial:
        jsr     emit_buffered_initial
        rts

flush_open:
        jsr     emit_buffered_syllable_open
        rts

flush_full:
        jsr     emit_buffered_syllable_full
        rts

begin_initial:
        sta     buffered_initial_char
        jsr     map_initial
        sta     buffered_l_index
        lda     #STATE_S2
        sta     automaton_state
        rts

begin_medial:
        sta     buffered_vowel_char
        jsr     map_vowel_single
        sta     buffered_v_index
        lda     #STATE_S3
        sta     automaton_state
        rts

begin_final_single:
        sta     buffered_t1_char
        jsr     map_final_single
        sta     buffered_t_index
        lda     #STATE_S4
        sta     automaton_state
        rts

try_extend_compound_vowel:
        lda     buffered_vowel_char
        sta     token_char
        lda     current_char
        sta     token_char_next
        jsr     map_vowel_pair
        bcs     compound_vowel_fail
        sta     buffered_v_index
        lda     #STATE_S6
        sta     automaton_state
        clc
        rts

compound_vowel_fail:
        sec
        rts

try_extend_compound_final:
        lda     buffered_t1_char
        sta     token_char
        lda     current_char
        sta     token_char_next
        jsr     map_final_pair
        bcs     compound_final_fail
        sta     buffered_t_index
        lda     current_char
        sta     buffered_t2_char
        lda     automaton_state
        cmp     #STATE_S4
        bne     set_state_s8
        lda     #STATE_S5
        sta     automaton_state
        clc
        rts

set_state_s8:
        lda     #STATE_S8
        sta     automaton_state
        clc
        rts

compound_final_fail:
        sec
        rts

emit_literal_char:
        lda     current_char
        ora     #$80
        jsr     call_saved_output
        rts

emit_buffered_initial:
        lda     buffered_l_index
        sta     token_value
        lda     #JAMO_KIND_INITIAL
        sta     jamo_kind
        jsr     emit_modified_jamo
        rts

emit_standalone_vowel:
        jsr     map_vowel_single
        sta     token_value
        lda     #JAMO_KIND_VOWEL
        sta     jamo_kind
        jsr     emit_modified_jamo
        rts

emit_buffered_syllable_open:
        lda     buffered_l_index
        sta     l_index
        lda     buffered_v_index
        sta     v_index
        lda     #$00
        sta     t_index
        jsr     emit_modified_syllable
        rts

emit_buffered_syllable_split_final:
        lda     buffered_l_index
        sta     l_index
        lda     buffered_v_index
        sta     v_index
        lda     buffered_t1_char
        jsr     map_final_single
        sta     t_index
        jsr     emit_modified_syllable
        rts

emit_buffered_syllable_full:
        lda     buffered_l_index
        sta     l_index
        lda     buffered_v_index
        sta     v_index
        lda     buffered_t_index
        sta     t_index
        jsr     emit_modified_syllable
        rts

input_hook:
        jsr     call_saved_input
        sta     input_char
        and     #$7F
        cmp     #SPAN_START
        beq     input_ring_bell
        cmp     #SPAN_END
        bne     input_return

input_ring_bell:
        jsr     BELL

input_return:
        lda     input_char
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
        jmp     emit_vowel_jamo

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

map_vowel_single:
        and     #$7F
        ldx     #$00

map_vowel_single_loop:
        cmp     vowel_chars,x
        beq     map_vowel_single_found
        inx
        cpx     #VOWEL_COUNT
        bcc     map_vowel_single_loop
        sec
        rts

map_vowel_single_found:
        lda     vowel_indices,x
        clc
        rts

map_vowel_pair:
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
        sec
        rts

map_vowel_pair_found:
        lda     vowel_pair_indices,x
        clc
        rts

map_final_single:
        and     #$7F
        ldx     #$00

map_final_single_loop:
        cmp     final_chars,x
        beq     map_final_single_found
        inx
        cpx     #FINAL_COUNT
        bcc     map_final_single_loop
        sec
        rts

map_final_single_found:
        lda     final_indices,x
        clc
        rts

map_final_pair:
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
        sec
        rts

map_final_pair_found:
        lda     final_pair_indices,x
        clc
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

        .segment "RODATA"

banner:
        .byte   $C1, $B2, $C8, $C1, $CE, $A0
        .byte   $C9, $CE, $D3, $D4, $C1, $CC, $CC, $C5, $C4
        .byte   $8D, $00

initial_chars:
        .byte   'R', 'r', '-', 'S', 'E', 'e', '=', 'F', 'A', 'Q', 'q', '*', 'T', 't', '<', 'D', 'W', 'w'
        .byte   '>', 'C', 'Z', 'X', 'V', 'G'
initial_indices:
        .byte   $00, $01, $01, $02, $03, $04, $04, $05, $06, $07, $08, $08, $09, $0A, $0A, $0B, $0C, $0D
        .byte   $0D, $0E, $0F, $10, $11, $12
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
        .byte   'R', 'r', '-', 'S', 'E', 'F', 'A', 'Q', 'T', 't', '<', 'D', 'W', 'C', 'Z', 'X', 'V', 'G'
final_indices:
        .byte   $01, $02, $02, $04, $07, $08, $10, $11, $13, $14, $14, $15, $16, $17, $18, $19, $1A, $1B
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
.ifdef A2HAN_TARGET_DOS33
        .word   KEYIN
.else
        .word   $0000
.endif

input_char:
        .byte   $00

automaton_state:
        .byte   STATE_S0
output_char:
        .byte   $00
current_char:
        .byte   $00

buffered_initial_char:
        .byte   $00
buffered_l_index:
        .byte   $00
buffered_vowel_char:
        .byte   $00
buffered_v_index:
        .byte   $00
buffered_t1_char:
        .byte   $00
buffered_t2_char:
        .byte   $00
buffered_t_index:
        .byte   $00

token_char:
        .byte   $00
token_char_next:
        .byte   $00

l_index:
        .byte   $00
v_index:
        .byte   $00
t_index:
        .byte   $00
token_value:
        .byte   $00
jamo_kind:
        .byte   $00

code_lo:
        .byte   $00
code_hi:
        .byte   $00
