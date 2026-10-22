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
| `126`     | RESTORE — each press is a ~100 ms make/break tap |
| `127`     | SYNC (always break form, `$7F`) — "nothing is held" |

The 6502 side reports switch positions only; the ATmega owns the keyID → USB
HID mapping, so joystick contacts arrive at the host as ordinary keystrokes.

**SYNC** is sent once at power-up/reset and then about once a second for as
long as no key, joystick contact or RESTORE is held. The ATmega releases
everything it still holds when it sees one. A release that never reaches the
ATmega (a reset while a key was down, a glitch on the latch) therefore costs at
most a second of stuck key instead of a key held until it is pressed again. An
older ATmega firmware sees keyID 127 as unmapped and ignores it.

**Pacing.** The 6502 cannot read `RDY` back, so after every `$DE00` write it
waits ~5 ms before the next one, and it waits ~10 ms between full scans
(debounce). Both delays run on CIA#1 timer B, which counts the 1 MHz system
clock, so they hold at any CPU speed (C128 FAST mode, accelerators, Ultimate
turbo). The ATmega needs well under 1 ms per event.

**Modifier ordering.** All eight columns are read first, then events go out in
three passes: modifier presses (SHIFT, CTRL, C=), every other change, then
modifier releases. A shifted key pressed together with its SHIFT always
arrives shifted, whichever column each sits in.

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
- RESTORE is wired to NMI (not in the matrix). The firmware's NMI handler
  counts the press and the scan loop reports it as keyID 126, which the ATmega
  sends as Page Up — VICE's positional RESTORE key — so RUN/STOP + RESTORE works
  in the emulator. The two KERNALs enter the handler differently:
  - **C64**: `$FE43` is just `SEI` / `JMP ($0318)`; the default handler pushes
    A/X/Y *after* that, at `$FE47`. Only the CPU's own frame is on the stack, so
    the handler ends in a bare `RTI`. (v1.1 popped three bytes that were never
    pushed and crashed to BASIC on RESTORE, stranding any key held at that
    moment on the host.)
  - **C128**: `$FF05` pushes A/X/Y and `$FF00`, then switches to config 0, which
    unmaps the cartridge. The handler is copied to RAM (`$0B00`) and leaves
    through the KERNAL's own exit at `$FF33`.
- The C128 KERNAL starts a function ROM with `$FF00 = $2A`, which maps
  `$C000-$FFFF` to external function ROM *high*. The cartridge does not decode
  `/ROMH`, so the CPU vectors read open bus (`$FFFF` in VICE) and any NMI went
  nowhere. The C128 bank sets `$FF00 = $0A` (cartridge at `$8000`, KERNAL at
  `$C000`) first thing.
- Runtime key-state is kept in zero page. On the C128 the external-function-ROM
  memory config maps `$C000-$FFFF` to ROM, so 6502 scratch must live in low RAM
  / zero page to work on both machines. `Cart.cfg` deliberately has no RAM/BSS
  area for that reason.
- The splash uses a light-blue border / black background / white text so an
  attached monitor gives an obvious "cartridge is alive" indication; the
  cartridge is fully functional headless.
- `emit_event` must preserve `Y`: `process_column` holds its row index there
  across the call. Getting this wrong emits every event after the first in a
  column as `keybase+1` (fixed in v1.1.0 — it was latent in v1.0, where two
  same-column keys changing within one 10 ms scan was rare enough to go
  unnoticed). The CIA-timed delay used since v1.2.0 leaves `Y` alone.
- Each row read repeats until two consecutive reads agree, as the KERNAL's own
  scan does (`$EAAB`), so a line still settling after a column switch is never
  taken as a key press.
