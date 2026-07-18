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

`make eeprom` runs `minipro -p "AT28C64B" -w Cart.bin`. Use minipro's **plain
`AT28C64B`** profile — **not** `AT28C64B(Non-Standard)`, a separate profile whose
write timing is broken (only ~1 byte in 5 sticks; readback shows correct bytes
at offsets 0, 5, 10… with `0xFF` between, "fixable" only with `-u -o pulse=10000`
that masks the wrong-profile choice). `minipro -l | grep` can truncate and hide
the plain entry; confirm a profile with `minipro -d AT28C64B`. Override for a
different part, e.g. `make eeprom EEPROM="AM28C64B@DIP28"`.

Event byte protocol
-------------------
Written to `$DE00`:

    bit 7      1 = key pressed (make), 0 = key released (break)
    bits 6..0  keyID  (C64 matrix code = col*8 + row, 0..63)

`keyID` is exactly the classic C64 KERNAL "keyboard code". The 6502 side is
matrix-position only; the ATmega owns the keyID → USB HID mapping. C128 extended
keys (keypad/ESC/TAB/ALT/HELP/cursor pad) are scanned via `$D02F` and numbered
`64 + kcol*8 + row` — the scan mechanism is in place but the per-key labels
still need confirmation on real C128 hardware.

What's verified
---------------
Both banks were booted in VICE (`x64sc`, `x128 -40col`): autostart triggers, the
system is brought up correctly (the C64 bank calls `IOINIT/RAMTAS/RESTOR/CINT`;
both banks then force a known 40-col VIC-II screen — required on C128, where the
function ROM runs before the editor is initialised), and the centered splash
renders. The matrix-scan → `$DE00` emission path can only be exercised on real
hardware (VICE can't inject matrix-level keypresses headlessly) — verify it with
a logic analyzer on `/IO1`/`R/W`/`D0-D7` during bring-up.

Notes
-----
- RESTORE is wired to NMI (not in the matrix); the firmware installs a harmless
  NMI handler so RESTORE does not drop back to BASIC.
- The splash uses a light-blue border / black background / white text so an
  attached monitor gives an obvious "cartridge is alive" indication. The
  cartridge is fully functional headless.
