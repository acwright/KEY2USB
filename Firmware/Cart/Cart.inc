; =============================================================================
;   Cart.inc - shared constants for the KEY2USB 6502 firmware
; =============================================================================
;
; Keep this file in sync with the ATmega328 side (Controller/src/protocol.h).
; The two firmwares share ONE contract: the event byte written to $DE00.

; ---- CIA #1: keyboard matrix -------------------------------------------------
CIA1_PRA  = $DC00       ; port A - keyboard COLUMN select (walking zero)
CIA1_PRB  = $DC01       ; port B - keyboard ROW read      (0 = pressed)
CIA1_DDRA = $DC02       ; data direction A
CIA1_DDRB = $DC03       ; data direction B
CIA1_TBLO = $DC06       ; timer B latch, low byte
CIA1_TBHI = $DC07       ; timer B latch, high byte
CIA1_CRB  = $DC0F       ; timer B control (bit 0 = START)

; ---- Timing (system clock cycles, ~1 us each) --------------------------------
; Every delay runs on CIA#1 timer B, which counts the 1 MHz system clock no
; matter how fast the CPU is (C128 FAST mode, accelerators, Ultimate turbo).
PACE_CYCLES   = 5000    ; ~5 ms after each $DE00 write (ATmega needs << 1 ms)
SCAN_CYCLES   = 10000   ; ~10 ms between full scans (debounce)
SETTLE_CYCLES = 80      ; joystick lines rising through the CIA pull-ups
SYNC_SCANS    = 96      ; idle scans between SYNC events (~1 s)
RESTORE_SCANS = 10      ; scans RESTORE is reported held for (~100 ms)

; ---- KERNAL vectors -----------------------------------------------------------
NMINV     = $0318       ; RAM NMI vector the KERNAL NMI entry jumps through

; ---- Cartridge I/O -----------------------------------------------------------
; Writing any byte to IO1 ($DE00) pulses WRSTB, latching D0-D7 into the
; 74LS273 (KB0-7) and setting the RDY flag for the ATmega. Reads do NOT strobe.
IO1       = $DE00

; ---- VIC-II / screen ---------------------------------------------------------
SCREEN    = $0400       ; 40x25 text screen matrix (VIC-II, C64 & C128 40-col)
COLORRAM  = $D800       ; per-cell color nybble
VIC_BGCOL = $D021       ; background color 0
VIC_BORDER= $D020       ; border color

COL_WHITE = 1
COL_BLACK = 0
COL_LBLUE = 14

; ---- KERNAL ------------------------------------------------------------------
CHROUT    = $FFD2

; ---- Event byte format (written to IO1) --------------------------------------
;   bit 7      : 1 = key pressed (make), 0 = key released (break)
;   bits 6..0  : keyID  (C64 matrix = col*8+row, 0..63; C128 extended = 64+;
;                        joystick port 2 = 112..116, port 1 = 120..124;
;                        RESTORE = 126)
EV_PRESSED = $80        ; OR this into a keyID to mark a make event

; RESTORE is not in the matrix: it pulls NMI, and only on the press edge. The
; firmware reports each press as a short make/break tap on this keyID.
KEY_RESTORE = 126

; SYNC (keyID 127, break form): "nothing is held". Sent at power-up/reset and
; about once a second while no key, stick or RESTORE is down. The ATmega clears
; its whole key state on it, so a lost release can never leave a key stuck on
; the host. An ATmega without SYNC support sees an unmapped key and ignores it.
EV_SYNC   = $7F

; ---- Joysticks ---------------------------------------------------------------
; Both ports share CIA#1 with the keyboard: port 2 sits on port A (the COLUMN
; drive), port 1 on port B (the ROW read). Contacts are active low.
;
; Port A must be switched to INPUTS (DDRA = $00) before reading it. While the
; matrix scan owns it, DDRA = $FF makes PA0..PA4 push-pull outputs, and a
; grounded contact does not read back as low - port 2 then looks permanently
; idle. Every stock C64 joystick routine clears DDRA for the same reason.
; Port B is already all-inputs for the row read.
;
; With no column driven, a pressed KEY can never phantom-press a joystick
; contact. The reverse crosstalk is real and is left alone, so the cartridge
; behaves like the bare machine:
;   - a held port-2 direction grounds a column line -> that column reads as
;     permanently selected, so keys in it alias into other columns' row reads.
;   - a held port-1 direction grounds a row line -> that row reads as pressed
;     in every column (the classic "stick in port 1 breaks menus" behaviour).
;
; joystick keyIDs = base + bit  ->  up, down, left, right, fire.
JOY_MASK  = $1F         ; bits 0..4 = up, down, left, right, fire
JOY2_BASE = 112         ; port 2 -> 112..116
JOY1_BASE = 120         ; port 1 -> 120..124

; ---- C128 VIC-IIe extended keyboard ------------------------------------------
; $D02F holds the three extra keyboard column lines K0..K2 (bits 0..2, 0=select).
; Extended keyIDs are numbered 64 + kcol*8 + row.
VIC_KBD   = $D02F
EXT_BASE  = 64

; ---- C128 MMU ----------------------------------------------------------------
; The KERNAL starts a function ROM with $FF00 = $2A, which maps $C000-$FFFF to
; external function ROM HIGH. This cartridge does not decode /ROMH, so the CPU
; vectors at $FFFA-$FFFF read open bus ($FFFF in VICE) and an NMI jumps into
; nothing. $0A keeps the cartridge at $8000-$BFFF but puts the KERNAL back at
; $C000-$FFFF (I/O on, RAM at $4000-$7FFF, bank 0).
MMU_CR      = $FF00
MMU_CART_KERNAL = $0A

; ---- C128 start-up state -----------------------------------------------------
; The KERNAL calls an autostart (ID $01) function ROM straight from its ROM
; poll ($E242 -> $E26B), BEFORE IOINIT ($E109) - in every C128 KERNAL revision.
; Nothing has configured the 8502 port or the VIC-IIe at that point. With the
; port's DDR still all-inputs, bit 2 of $01 floats high and the VIC reads
; character shapes from RAM: a screen of striped garbage on real hardware
; (x128 happened to model those bits low). These are IOINIT's own values.
CPU_DDR     = $00       ; 8502 port data direction
CPU_PORT    = $01       ; 8502 port data
C128_PORT_INIT = $E3    ; colour RAM bank 1 for CPU and VIC; bit 2 = 0: the VIC
                        ; sees the character ROM
C128_DDR_INIT  = $2F    ; bits 0-3 and 5 outputs
VIC_SPENA   = $D015     ; sprite enable
VIC_IRQEN   = $D01A     ; VIC interrupt enable
VIC_CLKRATE = $D030     ; VIC-IIe: bit 0 = 2 MHz, bit 1 = test
C128_CLKRATE_INIT = $FC ; 1 MHz, test off (IOINIT's value)
C128_NMIEXIT = $FF33    ; KERNAL NMI exit: restore $FF00, Y, X, A, then RTI
NMI_STUB    = $0B00     ; RAM home of the C128 NMI stub (cassette buffer)
