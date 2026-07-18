KEY2USB — Cartridge ROM (6502)
==============================

Autostart ROM for the KEY2USB expansion-port cartridge. It takes over the
C64/C128, shows a `KEY2USB` splash, then continuously scans the CIA#1 keyboard
matrix and writes a make/break **event byte** to `$DE00` (`/IO1`) on every key
transition. The 74LS273 latches the byte and the 74LS74 raises `RDY` for the
ATmega328 controller.

Two banks, one source
---------------------
The 28C64 (8K) is split by the `MODE` switch, which drives EEPROM `A12`:

| MODE   | A12 | Bank      | Autostart |
|--------|-----|-----------|-----------|
| GND    | 0   | lower 4K  | C64 (`CBM80`, forces C128 into C64 mode) |
| +5V    | 1   | upper 4K  | C128 (function-ROM `CBM` signature) |

`Cart.asm` is assembled twice (the C128 build passes `--asm-define TARGET_C128`)
and the two 4K images are concatenated into the 8K `Cart.bin`. Only bus
`A0..A11` reach the EEPROM, so each 4K bank mirrors across the `$8000-$9FFF`
ROML window.

Build
-----
Requires [cc65](https://cc65.github.io/) (`cl65` on PATH).

    make            # -> Cart.bin (8192 bytes)
    make view       # hexdump Cart.bin
    make clean

Program the EEPROM
------------------
    make eeprom     # build, then program the AT28C64B via minipro

`make eeprom` runs `minipro -p "AT28C64B" -w Cart.bin`. Use minipro's plain
`AT28C64B` profile (confirm with `minipro -d AT28C64B`) — not the separate
`AT28C64B(Non-Standard)` entry. Override the device for a different part, e.g.
`make eeprom EEPROM="AM28C64B@DIP28"`.

Event byte protocol
-------------------
Written to `$DE00`:

    bit 7      1 = key pressed (make), 0 = key released (break)
    bits 6..0  keyID  (C64 matrix code = col*8 + row, 0..63)

`keyID` is exactly the classic C64 KERNAL "keyboard code". The 6502 side is
matrix-position only; the ATmega owns the keyID → USB HID mapping.

C128 extended keys
------------------
The C128's extra keys (numeric keypad / ESC / TAB / ALT / HELP / cursor pad) are
read via `$D02F` as keyIDs `64 + kcol*8 + row`. This scan is experimental and
gated behind a `.define SCAN_EXTENDED` build flag in `Cart.asm`; it is **not**
compiled in by default. With it off, the C128 bank scans the standard 8×8 matrix
(the full C64-compatible key subset). To enable it, define the flag and add the
corresponding keyID 64+ entries to `Controller/src/keymap.h`.

Notes
-----
- RESTORE is wired to NMI (not in the matrix); the firmware installs a harmless
  NMI handler so RESTORE does not drop back to BASIC.
- Runtime key-state is kept in zero page. On the C128 the external-function-ROM
  memory config maps `$C000-$FFFF` to ROM, so 6502 scratch must live in low RAM
  / zero page to work on both machines.
- The splash uses a light-blue border / black background / white text so an
  attached monitor gives an obvious "cartridge is alive" indication; the
  cartridge is fully functional headless.
