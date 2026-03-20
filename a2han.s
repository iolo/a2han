        .setcpu "6502"

COUT    = $FDED
WARM    = $03D0

        .segment "CODE"

start:
        ldx     #$00

print_loop:
        lda     message,x
        beq     done
        jsr     COUT
        inx
        bne     print_loop

done:
        jmp     WARM

message:
        .byte   $C1, $B2, $C8, $C1, $CE, $A0
        .byte   $C2, $D5, $C9, $CC, $C4, $A0
        .byte   $D4, $C5, $D3, $D4
        .byte   $8D, $00
