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
;   3. Continuously scans the CIA#1 keyboard matrix and both joystick ports and,
;      on every make/break transition, writes an event byte to $DE00. The
;      74LS273 latches it and the ATmega picks it up over the RDY handshake.
;
; The 6502 cannot read the RDY flag back, so after every $DE00 write it waits
; ~2 ms (emit pacing) to guarantee the ATmega has consumed the previous byte
; before the next transition overwrites the latch.

.setcpu "6502"
.include "Cart.inc"

VERSION_MAJOR = 1
VERSION_MINOR = 1
VERSION_PATCH = 0

; ---------------------------------------------------------------------------
; Build option: C128 extended-key scan (numeric keypad / ESC / TAB / ALT /
; HELP / cursor pad via $D02F). DISABLED by default.
;
; It is unverified on real C128 hardware, the ATmega currently leaves keyIDs
; 64+ unmapped (so it adds no usable keys), and unstable extended-line reads
; flood the event pipeline - which destabilises normal key scanning on a real
; C128 (intermittent/missed keys plus erratic repeat bursts). Verify the scan
; with a logic analyzer on $D02F / $DC01, and add the keyID 64+ entries to the
; ATmega keymap, before defining this.
; ---------------------------------------------------------------------------
; .define SCAN_EXTENDED

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
;   Zero-page scratch + runtime state (owned once we SEI; not in the ROM image)
; =============================================================================
; Everything lives in zero page. Zero page is RAM on both the C64 and the C128,
; whereas $C000-$FFFF is ROM in the C128's external-function-ROM memory config -
; storing prevstate there made every write vanish, so the key-state array never
; updated and the scan emitted a flood of phantom events (garbage/stuck keys on
; a real C128). Zero page fixes it for both machines.
.segment "ZEROPAGE"
curpress:  .res 1                       ; current pressed bitmap for a column
changed:   .res 1                       ; bits that changed this scan
presstmp:  .res 1                       ; 1 = the bit being processed is pressed
keybase:   .res 1                       ; keyID base for the current column (col*8)
idx:       .res 1                       ; outer loop column index
prevstate: .res 8                       ; previous pressed bitmap per matrix column
prevext:   .res 3                       ; previous pressed bitmap per C128 K-column
joy2cur:   .res 1                       ; this scan's closed contacts, joy port 2
joy1cur:   .res 1                       ; this scan's closed contacts, joy port 1
prevjoy2:  .res 1                       ; previous closed-contact bitmap, port 2
prevjoy1:  .res 1                       ; previous closed-contact bitmap, port 1

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
        sta     prevjoy2
        sta     prevjoy1

; -----------------------------------------------------------------------------
;   Main loop: scan, emit events, repeat at ~10 ms intervals (debounce).
; -----------------------------------------------------------------------------
mainloop:
        ; Joysticks first, deliberately. A held port-1 direction grounds a row
        ; line and phantom-presses all 8 keys in that row; the HID boot report
        ; carries only 6 non-modifier keys, so if the matrix scan emits first
        ; it fills every slot and the real joystick event gets dropped on the
        ; ATmega side. Emitting the stick first lets it claim a slot.
        jsr     scan_joystick
        jsr     scan_matrix
.ifdef TARGET_C128
.ifdef SCAN_EXTENDED
        jsr     scan_extended
.endif
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
.ifdef SCAN_EXTENDED
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
.endif

; -----------------------------------------------------------------------------
;   scan_joystick - read both joystick ports and emit events on any change.
;
;   Port A must be switched to INPUTS for this. During the matrix scan DDRA is
;   $FF, so PA0..PA4 are push-pull outputs driving high, and a joystick contact
;   shorting one to ground does NOT read back as low - the read returns the
;   driven/latched level, so port 2 looks permanently idle. (This is why every
;   stock C64 joystick routine clears DDRA before reading $DC00.) Port B is
;   already all-inputs for the row read, but it is sampled in the same window
;   so both ports share one instant.
;
;   With DDRA = $00 no column is driven at all, so a pressed key cannot pull
;   either port low and keys never phantom-press the stick. The reverse
;   crosstalk (a held stick aliasing into the keyboard scan) is inherent to the
;   wiring and is left in place - see Cart.inc.
;
;   The settle delay matters: as inputs the lines rise only through the CIA's
;   passive pull-ups against joystick cable capacitance, which is far slower
;   than a driven edge. Reading too early samples the falling remnant of the
;   last column drive and invents contacts.
;
;   Bits 5..7 read high on both ports (nothing drives them low), so they invert
;   to 0 and never emit - but mask anyway to keep the contract explicit.
; -----------------------------------------------------------------------------
scan_joystick:
        lda     #$ff
        sta     CIA1_PRA                ; park the column latch high
        lda     #$00
        sta     CIA1_DDRA               ; PA -> inputs so contacts can pull low
        ldx     #16                     ; ~80 cycles for the pull-ups to settle
@settle:
        dex
        bne     @settle
        lda     CIA1_PRA                ; joystick 2 on PA0..PA4
        eor     #$ff                    ; 1 = contact closed
        and     #JOY_MASK
        sta     joy2cur
        lda     CIA1_PRB                ; joystick 1 on PB0..PB4
        eor     #$ff
        and     #JOY_MASK
        sta     joy1cur
        lda     #$ff
        sta     CIA1_DDRA               ; restore column drive for scan_matrix

        ; --- port 2 ---
        lda     joy2cur
        sta     curpress
        lda     #JOY2_BASE
        sta     keybase
        lda     prevjoy2                ; old bitmap into A for process_column
        ldx     joy2cur                 ; (ldx/stx leave A untouched)
        stx     prevjoy2
        jsr     process_column

        ; --- port 1 ---
        lda     joy1cur
        sta     curpress
        lda     #JOY1_BASE
        sta     keybase
        lda     prevjoy1
        ldx     joy1cur
        stx     prevjoy1
        jmp     process_column          ; tail call - process_column rts's for us

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
;     entry: A = event byte.  Preserves Y; destroys A and X.
;
;   Y MUST survive: process_column keeps its row index in Y across this call,
;   and the pacing delay below uses Y as its own loop counter. Without the
;   save/restore the delay returns Y = 0, so the second and every later event
;   in one column is emitted as keyID keybase+1 instead of keybase+row. That
;   only shows up when two keys in the same column change within one scan -
;   uncommon when typing, but constant for a joystick (every diagonal moves
;   two bits at once).
; -----------------------------------------------------------------------------
emit_event:
        sta     IO1                     ; latch byte + set RDY (74LS273 / 74LS74)
        tya
        pha
        jsr     delay_2ms
        pla
        tay
        rts

; ~2 ms pacing delay. Destroys A, X, Y.
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

        ldx     #0                      ; version @ row 13, col 17
@l2:    lda     banner_ver,x
        sta     SCREEN + (13*40 + 17),x
        inx
        cpx     #6
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
.ifdef SCAN_EXTENDED
; K0..K2 select patterns for $D02F.
extmask:   .byte $FE,$FD,$FB
.endif
.endif

; Screen-code text (uppercase/graphics set: A-Z = 1-26, 0-9 = $30-$39).
banner_title: .byte 11,5,25,50,21,19,2          ; "KEY2USB"
              ; "V1.1.0" - V=22, '.'=46, digits = $30+n
banner_ver:   .byte 22, $30+VERSION_MAJOR, 46, $30+VERSION_MINOR, 46, $30+VERSION_PATCH

.ifdef TARGET_C128
banner_mode:  .byte 3,49,50,56,32,13,15,4,5     ; "C128 MODE"
.else
banner_mode:  .byte 3,54,52,32,13,15,4,5        ; "C64 MODE"
.endif
