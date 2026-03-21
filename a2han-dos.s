        .setcpu "6502"

CSW             = $0036
KSW             = $0038
FRETOP          = $006F
HIMEM           = $0073
DOSWARM         = $03D0
DOS_REHOOK      = $03EA
BASIC_GLOBAL    = $BE00
BASIC_VECTOUT   = $BE30
BASIC_VECTIN    = $BE32
KEYIN           = $FD1B
COUT1           = $FDF0
RESIDENT_START  = $9600

MODE_DOS        = $00
MODE_PRODOS     = $01

        .segment "CODE"

start:
        jsr     reserve_memory
        jsr     install_hooks
        jsr     print_banner
        jmp     exit_program

install_hooks:
        lda     BASIC_GLOBAL
        cmp     #$4C
        bne     install_dos
        lda     BASIC_GLOBAL+3
        cmp     #$4C
        bne     install_dos

install_prodos:
        lda     #MODE_PRODOS
        sta     install_mode

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

install_dos:
        lda     #MODE_DOS
        sta     install_mode

        lda     #<output_hook
        sta     CSW
        lda     #>output_hook
        sta     CSW+1
        lda     #<input_hook
        sta     KSW
        lda     #>input_hook
        sta     KSW+1
        jsr     DOS_REHOOK
        rts

reserve_memory:
        lda     #<RESIDENT_START
        sta     FRETOP
        sta     HIMEM
        lda     #>RESIDENT_START
        sta     FRETOP+1
        sta     HIMEM+1
        rts

print_banner:
        ldx     #$00

print_loop:
        lda     banner,x
        beq     done
        jsr     output_hook
        inx
        bne     print_loop

done:
        rts

output_hook:
        pha
        lda     install_mode
        cmp     #MODE_PRODOS
        beq     output_saved
        pla
        jmp     COUT1

output_saved:
        pla
        jmp     (saved_output)

input_hook:
        lda     install_mode
        cmp     #MODE_PRODOS
        beq     input_saved
        jmp     KEYIN

input_saved:
        jmp     (saved_input)

exit_program:
        lda     install_mode
        cmp     #MODE_PRODOS
        beq     exit_prodos
        jmp     DOSWARM

exit_prodos:
        rts

        .segment "RODATA"

banner:
        .byte   $C1, $B2, $C8, $C1, $CE, $A0
        .byte   $C9, $CE, $D3, $D4, $C1, $CC, $CC, $C5, $C4
        .byte   $8D, $00

        .segment "DATA"

install_mode:
        .byte   MODE_DOS
saved_output:
        .word   COUT1
saved_input:
        .word   KEYIN
