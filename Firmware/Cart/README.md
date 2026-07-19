KEY2USB — Cartridge ROM (6502)
==============================

Autostart ROM for the KEY2USB expansion-port cartridge. It takes over the
C64/C128, shows a `KEY2USB` splash, then continuously scans the CIA#1 keyboard
matrix and both joystick ports, writing a make/break **event byte** to `$DE00`
(`/IO1`) on every transition. The 74LS273 latches the byte and the 74LS74 raises
`RDY` for the ATmega328 controller.

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

    bit 7      1 = pressed (make), 0 = released (break)
    bits 6..0  keyID

| keyID     | Source |
|-----------|--------|
| `0..63`   | C64 matrix, `col*8 + row` (the classic KERNAL "keyboard code") |
| `64..87`  | C128 extended keys (optional scan, off by default) |
| `112..116`| Joystick **port 2** — up, down, left, right, fire |
| `120..124`| Joystick **port 1** — up, down, left, right, fire |

The 6502 side reports switch positions only; the ATmega owns the keyID → USB
HID mapping, so joystick contacts arrive at the host as ordinary keystrokes.

Joysticks
---------
Both ports share CIA#1 with the keyboard — port 2 on port A (the column drive),
port 1 on port B (the row read). **No extra hardware is involved** — the DE9
ports were always on these lines.

Port A must be switched to inputs (`DDRA = $00`) before reading. While the
matrix scan owns it, `DDRA = $FF` makes PA0–PA4 push-pull outputs and a
grounded contact does *not* read back as low, so port 2 reads permanently idle
— this is why every stock C64 joystick routine clears `DDRA` first. Port B is
already an input. A short settle delay follows the DDR change, because as
inputs the lines rise only through the CIA's passive pull-ups against joystick
cable capacitance.

Because no column is driven during the read, a pressed key can never
phantom-press a joystick contact. The reverse crosstalk is inherent to the
wiring and is deliberately left alone so the cartridge behaves like the bare
machine:

- a held **port 2** direction grounds a column line, so keys in that column
  alias into other columns' row reads;
- a held **port 1** direction grounds a row line, so that row reads as pressed
  in *every* column — the classic "stick in port 1 breaks menus" behaviour.

In practice this only matters if you type while holding a direction.

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
- `emit_event` must preserve `Y`: `process_column` holds its row index there
  across the call, while the pacing delay uses `Y` as its own counter. Getting
  this wrong emits every event after the first in a column as `keybase+1`
  (fixed in v1.1.0 — it was latent in v1.0, where two same-column keys changing
  within one 10 ms scan was rare enough to go unnoticed).
