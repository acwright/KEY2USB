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
;   bits 6..0  : keyID  (C64 matrix = col*8+row, 0..63; C128 extended = 64+)
EV_PRESSED = $80        ; OR this into a keyID to mark a make event

; ---- C128 VIC-IIe extended keyboard ------------------------------------------
; $D02F holds the three extra keyboard column lines K0..K2 (bits 0..2, 0=select).
; Extended keyIDs are numbered 64 + kcol*8 + row.
VIC_KBD   = $D02F
EXT_BASE  = 64
