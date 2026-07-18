; =============================================================================
;   Cart.asm - KEY2USB cartridge 6502 firmware (autostart ROM)
; =============================================================================
;
; One source, two banks. Assemble twice:
;     cl65 ... -o cart_c64.bin              -> C64 bank  (MODE = GND)
;     cl65 ... -D TARGET_C128 -o cart_c128.bin -> C128 bank (MODE = +5V)
; then concatenate C64 + C128 into the 8K 28C64 image (see Makefile).
;
; What it does:
;   1. Takes over the machine (autostart), masks IRQ, ignores RESTORE (NMI).
;   2. Draws a "KEY2USB <version>" splash on the 40-column screen (feedback
;      only - the cartridge works headless).
;   3. Continuously scans the CIA#1 keyboard matrix and, on every make/break
;      transition, writes an event byte to $DE00. The 74LS273 latches it and
;      the ATmega picks it up over the RDY handshake.
;
; The 6502 cannot read the RDY flag back, so after every $DE00 write it waits
; ~2 ms (emit pacing) to guarantee the ATmega has consumed the previous byte
; before the next transition overwrites the latch.

.setcpu "6502"
.include "Cart.inc"

VERSION_MAJOR = 1
VERSION_MINOR = 0

.ifdef TARGET_C128
BANNER_MODE_LEN = 9
BANNER_MODE_COL = 15
.else
BANNER_MODE_LEN = 8
BANNER_MODE_COL = 16
.endif

; =============================================================================
;   Autostart header at $8000
; =============================================================================
.segment "HEADER"
.ifdef TARGET_C128
        jmp     coldstart               ; $8000 cold start entry
        jmp     coldstart               ; $8003 warm start entry
        .byte   $01                     ; $8006 autostart key ($01 = boot ML now)
        .byte   $43,$42,$4D             ; $8007 "CBM" signature
.else
        .word   coldstart               ; $8000 cold start vector
        .word   coldstart               ; $8002 NMI vector
        .byte   $C3,$C2,$CD,$38,$30     ; $8004 "CBM80" signature
.endif

; =============================================================================
;   Zero-page scratch (owned once we SEI; not part of the ROM image)
; =============================================================================
.segment "ZEROPAGE"
curpress:  .res 1                       ; current pressed bitmap for a column
changed:   .res 1                       ; bits that changed this scan
presstmp:  .res 1                       ; 1 = the bit being processed is pressed
keybase:   .res 1                       ; keyID base for the current column (col*8)
idx:       .res 1                       ; outer loop column index

; =============================================================================
;   Runtime state in free RAM at $C000 (not part of the ROM image)
; =============================================================================
.segment "BSS"
prevstate: .res 8                       ; previous pressed bitmap per matrix column
prevext:   .res 3                       ; previous pressed bitmap per C128 K-column

; =============================================================================
;   Code
; =============================================================================
.segment "CODE"

coldstart:
        sei                             ; we own the machine from here
        cld
        ldx     #$ff
        txs                             ; reset stack

        ; --- bring up the machine ourselves --------------------------------
        ; A CBM80 autostart cart runs from the reset routine BEFORE the KERNAL
        ; initialises I/O and the screen, so do that init ourselves. On C128
        ; the function-ROM autostart runs after KERNAL init, so skip it there.
.ifndef TARGET_C128
        jsr     $FDA3                   ; IOINIT  - CIA / VIC / I/O setup
        jsr     $FD50                   ; RAMTAS  - clear/size RAM, set pointers
        jsr     $FD15                   ; RESTOR  - default KERNAL vectors
        jsr     $FF5B                   ; CINT    - screen editor / VIC-II init
        sei                             ; re-mask (init routines may CLI)
.endif

        ; --- silence interrupt sources -------------------------------------
        lda     #$7f
        sta     $DC0D                   ; disable all CIA#1 IRQ sources
        sta     $DD0D                   ; disable all CIA#2 NMI sources
        bit     $DC0D                   ; ack any pending
        bit     $DD0D

        ; --- redirect RESTORE (NMI) to a harmless handler ------------------
        lda     #<nmi_ignore
        sta     $0318
        lda     #>nmi_ignore
        sta     $0319

        ; --- configure CIA#1 for keyboard scanning -------------------------
        lda     #$ff
        sta     CIA1_DDRA               ; port A = outputs (column drive)
        lda     #$00
        sta     CIA1_DDRB               ; port B = inputs  (row read)
.ifdef TARGET_C128
        lda     #$ff
        sta     VIC_KBD                 ; deselect C128 extended columns
.endif

        ; --- force a known 40-column VIC-II text screen --------------------
        ; The C64 KERNAL init above sets these up, but on the C128 the
        ; function-ROM autostart runs before the 40-col editor is configured
        ; (VIC-II would otherwise read the screen from $0000 with the display
        ; disabled). Program them explicitly so both machines match.
        lda     $DD02
        ora     #$03
        sta     $DD02                   ; CIA2 PA0/PA1 = outputs
        lda     $DD00
        ora     #$03                    ; VIC bank 0 ($0000-$3FFF)
        sta     $DD00
        lda     #$15
        sta     $D018                   ; screen matrix $0400, char ROM $1000
        lda     #$c8
        sta     $D016                   ; 40 columns
        lda     #$1b
        sta     $D011                   ; display enabled, 25 rows

        ; --- screen feedback ----------------------------------------------
        lda     #COL_LBLUE
        sta     VIC_BORDER
        lda     #COL_BLACK
        sta     VIC_BGCOL
        jsr     clear_screen
        jsr     draw_banner

        ; --- initialise key state -----------------------------------------
        ldx     #7
        lda     #0
@zs:    sta     prevstate,x
        dex
        bpl     @zs
        ldx     #2
@ze:    sta     prevext,x
        dex
        bpl     @ze

; -----------------------------------------------------------------------------
;   Main loop: scan, emit events, repeat at ~10 ms intervals (debounce).
; -----------------------------------------------------------------------------
mainloop:
        jsr     scan_matrix
.ifdef TARGET_C128
        jsr     scan_extended
.endif
        jsr     scan_delay
        jmp     mainloop

; -----------------------------------------------------------------------------
;   scan_matrix - walk the 8 keyboard columns, emit events on any change.
; -----------------------------------------------------------------------------
scan_matrix:
        lda     #0
        sta     idx
@col:
        ldx     idx
        lda     colmask,x
        sta     CIA1_PRA                ; drive one column low
        lda     CIA1_PRB                ; read rows (0 = pressed)
        eor     #$ff                    ; 1 = pressed
        sta     curpress
        lda     prevstate,x             ; old bitmap
        pha
        lda     curpress
        sta     prevstate,x             ; store new bitmap
        ; keybase = col * 8
        txa
        asl     a
        asl     a
        asl     a
        sta     keybase
        pla                             ; old bitmap back into A
        jsr     process_column
        inc     idx
        lda     idx
        cmp     #8
        bne     @col
        rts

.ifdef TARGET_C128
; -----------------------------------------------------------------------------
;   scan_extended - C128 numeric keypad / ESC / TAB / ALT / HELP / cursor pad.
;   The three extra columns K0..K2 live on $D02F bits 0..2 (active low) while
;   the normal columns are deselected. Extended keyIDs = 64 + kcol*8 + row.
;   NOTE: label assignments for these keyIDs must be confirmed on real C128
;   hardware; the scan mechanism is what matters here.
; -----------------------------------------------------------------------------
scan_extended:
        lda     #$ff
        sta     CIA1_PRA                ; deselect all normal columns
        lda     #0
        sta     idx
@col:
        ldx     idx
        lda     extmask,x
        sta     VIC_KBD                 ; select one K column
        lda     CIA1_PRB
        eor     #$ff
        sta     curpress
        lda     prevext,x
        pha
        lda     curpress
        sta     prevext,x
        ; keybase = EXT_BASE + kcol * 8
        txa
        asl     a
        asl     a
        asl     a
        clc
        adc     #EXT_BASE
        sta     keybase
        pla
        jsr     process_column
        inc     idx
        lda     idx
        cmp     #3
        bne     @col
        lda     #$ff
        sta     VIC_KBD                 ; deselect extended columns again
        rts
.endif

; -----------------------------------------------------------------------------
;   process_column - emit make/break events for the changed bits of a column.
;     entry: A        = previous pressed bitmap
;            curpress = current  pressed bitmap
;            keybase  = keyID of row 0 in this column
;     note:  destroys curpress (shifted out), A, X, Y.
; -----------------------------------------------------------------------------
process_column:
        eor     curpress                ; A = changed bits
        beq     @done                   ; nothing changed - fast path
        sta     changed
        ldy     #0                      ; row / bit index
@bit:
        lsr     curpress                ; carry = pressed state of this row
        lda     #0
        rol     a
        sta     presstmp                ; 1 if pressed, else 0
        lsr     changed                 ; carry = did this row change?
        bcc     @next
        tya                             ; keyID = keybase + row
        clc
        adc     keybase
        ldx     presstmp
        beq     @send                   ; released -> bit7 = 0
        ora     #EV_PRESSED             ; pressed  -> bit7 = 1
@send:
        jsr     emit_event
@next:
        iny
        cpy     #8
        bne     @bit
@done:
        rts

; -----------------------------------------------------------------------------
;   emit_event - write one event byte to the latch, then pace ~2 ms.
;     entry: A = event byte.
; -----------------------------------------------------------------------------
emit_event:
        sta     IO1                     ; latch byte + set RDY (74LS273 / 74LS74)
        ; fall through into a ~2 ms pacing delay
delay_2ms:
        ldy     #4
@a:     ldx     #250
@b:     dex
        bne     @b                      ; 250 * ~5 = ~1250 cycles
        dey
        bne     @a                      ; * 4  = ~5000 cycles ~= 2 ms @ 1 MHz
        rts

; -----------------------------------------------------------------------------
;   scan_delay - ~10 ms between full scans (natural key debounce).
; -----------------------------------------------------------------------------
scan_delay:
        ldy     #8
@a:     ldx     #250
@b:     dex
        bne     @b
        dey
        bne     @a
        rts

; -----------------------------------------------------------------------------
;   nmi_ignore - swallow RESTORE presses so the cart keeps running.
;   The KERNAL NMI entry pushed A, X, Y before JMP ($0318); unwind and RTI.
; -----------------------------------------------------------------------------
nmi_ignore:
        pla
        tay
        pla
        tax
        pla
        rti

; -----------------------------------------------------------------------------
;   clear_screen - fill the 40x25 screen with spaces in white.
; -----------------------------------------------------------------------------
clear_screen:
        ldx     #0
@l:     lda     #32                     ; screen code for space
        sta     SCREEN+$000,x
        sta     SCREEN+$100,x
        sta     SCREEN+$200,x
        sta     SCREEN+$300,x
        lda     #COL_WHITE
        sta     COLORRAM+$000,x
        sta     COLORRAM+$100,x
        sta     COLORRAM+$200,x
        sta     COLORRAM+$300,x
        inx
        bne     @l
        rts

; -----------------------------------------------------------------------------
;   draw_banner - three centered lines of screen-code text.
; -----------------------------------------------------------------------------
draw_banner:
        ldx     #0                      ; "KEY2USB" @ row 11, col 16
@l1:    lda     banner_title,x
        sta     SCREEN + (11*40 + 16),x
        inx
        cpx     #7
        bne     @l1

        ldx     #0                      ; version @ row 13, col 18
@l2:    lda     banner_ver,x
        sta     SCREEN + (13*40 + 18),x
        inx
        cpx     #4
        bne     @l2

        ldx     #0                      ; mode line @ row 15
@l3:    lda     banner_mode,x
        sta     SCREEN + (15*40 + BANNER_MODE_COL),x
        inx
        cpx     #BANNER_MODE_LEN
        bne     @l3
        rts

; =============================================================================
;   Read-only data
; =============================================================================
.segment "RODATA"

; Walking-zero column-select patterns for $DC00 (PA0..PA7).
colmask:   .byte $FE,$FD,$FB,$F7,$EF,$DF,$BF,$7F
.ifdef TARGET_C128
; K0..K2 select patterns for $D02F.
extmask:   .byte $FE,$FD,$FB
.endif

; Screen-code text (uppercase/graphics set: A-Z = 1-26, 0-9 = $30-$39).
banner_title: .byte 11,5,25,50,21,19,2          ; "KEY2USB"
banner_ver:   .byte 22, $30+VERSION_MAJOR, 46, $30+VERSION_MINOR  ; "V1.0"

.ifdef TARGET_C128
banner_mode:  .byte 3,49,50,56,32,13,15,4,5     ; "C128 MODE"
.else
banner_mode:  .byte 3,54,52,32,13,15,4,5        ; "C64 MODE"
.endif
