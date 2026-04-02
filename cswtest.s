        .setcpu "6502"

.ifdef CSWTEST_TARGET_DOS33
HOOK_OUTPUT_VEC = $0036
DOSFET          = $03EA
.else
HOOK_OUTPUT_VEC = $BE30
.endif

COUT1           = $FDF0
CR              = $8D

        .segment "CODE"

start:
.ifdef CSWTEST_TARGET_DOS33
        jsr     DOSFET
.endif
        jsr     print_banner

        lda     #'R'|$80
        jsr     call_rom_output
        lda     #'K'|$80
        jsr     call_rom_output
        jsr     print_space
        lda     #$4C
        jsr     call_hook_output
        lda     #$00
        jsr     call_hook_output
        jsr     print_cr

        lda     #'S'|$80
        jsr     call_rom_output
        lda     #'K'|$80
        jsr     call_rom_output
        jsr     print_space
        lda     #$50
        jsr     call_hook_output
        lda     #$98
        jsr     call_hook_output
        jsr     print_cr

        lda     #'G'|$80
        jsr     call_rom_output
        lda     #'K'|$80
        jsr     call_rom_output
        lda     #'S'|$80
        jsr     call_rom_output
        jsr     print_space
        lda     #$75
        jsr     call_hook_output
        lda     #$5C
        jsr     call_hook_output
        jsr     print_cr
        rts

print_banner:
        ldx     #$00
print_banner_loop:
        lda     banner,x
        beq     print_banner_done
        jsr     call_rom_output
        inx
        bne     print_banner_loop
print_banner_done:
        rts

print_space:
        lda     #' '|$80
        jmp     call_rom_output

print_cr:
        lda     #CR
        jmp     call_rom_output

call_hook_output:
        pha
        lda     HOOK_OUTPUT_VEC
        sta     hook_call+1
        lda     HOOK_OUTPUT_VEC+1
        sta     hook_call+2
        pla
hook_call:
        jsr     $FFFF
        rts

call_rom_output:
        jsr     COUT1
        rts

        .segment "RODATA"

banner:
        .byte   'C'|$80, 'S'|$80, 'W'|$80, ' '|$80, 'T'|$80, 'E'|$80, 'S'|$80, 'T'|$80, CR
        .byte   $00
