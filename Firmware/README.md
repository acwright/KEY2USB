KEY2USB — Firmware
==================

Two independent firmwares that share exactly one thing: the **event byte**.

    Cart/         6502 autostart ROM for the 28C64 (C64 + C128 banks)
    Controller/   ATmega328/328P V-USB HID keyboard

    ┌──────────┐  scan matrix   ┌─────────┐  write $DE00   ┌─────────┐  RDY   ┌──────────┐  USB HID
    │ C64/C128 │ ─────────────► │  6502   │ ─────────────► │ 74LS273 │ ─────► │ ATmega328│ ───────►  PC
    │ keyboard │                │  ROM    │                │ + 74LS74│  latch │  (V-USB) │           (VICE)
    └──────────┘                └─────────┘                └─────────┘        └──────────┘

Event byte (`$DE00` → latch → ATmega):

    bit 7      1 = pressed (make), 0 = released (break)
    bits 6..0  keyID  (C64 matrix code col*8+row, 0..63; C128 extended 64+)

The 6502 reports only matrix positions; the ATmega owns keyID → USB HID.

Build both
----------
    cd Cart && make                 # -> Cart.bin  (program the 28C64)
    cd Controller && pio run        # -> firmware.hex (program the 328)

See each subdirectory's README for flashing and fuse details.

Status
------
Verified in emulation / at build time:
- Both ROM banks autostart and render the splash in VICE (`x64sc`, `x128`).
- System bring-up is handled by the ROM itself (needed because autostart runs
  before the KERNAL sets up the screen).
- Controller compiles clean for 328 and 328P; HID report descriptor validated.

To verify on hardware (see bring-up plan below):
- 6502 matrix scan → `$DE00` emission (VICE can't inject matrix keys headlessly).
- USB enumeration + the latch/RDY handshake + end-to-end keystrokes.
- C128 extended-key labels (keyIDs 64+).

Bring-up plan (minimise reprogramming)
--------------------------------------
1. **ROM alone.** Program `Cart.bin`, MODE = C64. Power the C64: confirm the
   `KEY2USB / V0.1 / C64 MODE` splash. Flip MODE = C128 on a C128: confirm
   `C128 MODE`. (No USB needed yet.)
2. **Latch emission.** With a logic analyzer on `/IO1`, `R/W`, `PHI2` and
   `D0-D7`: press keys and confirm one write to `$DE00` per make/break, with the
   expected event byte (e.g. `A` press = `0x8A` → keyID 10 | 0x80; release =
   `0x0A`). Confirm `RDY` asserts on each write. This validates the whole 6502
   path independent of USB.
3. **Controller alone.** Program the 328 (code + fuses). Plug USB into the PC:
   the device should enumerate as `KEY2USB` HID keyboard. With the ROM emitting
   events, keystrokes should now reach the PC.
4. **End to end in VICE.** Start `x64sc`, select the **Positional** keymap, and
   type on the C64 — characters should appear in the emulator. Use `x128` for
   C128 extended keys.

Tips
----
- If nothing enumerates: re-check the 16 MHz fuses, D+/D- wiring (D+ must be on
  PD2/INT0), and the 68Ω / 1.5k / zener front end.
- If keys are wrong in VICE: confirm Positional (not Symbolic) keymap, then tune
  `Controller/src/keymap.h`.
- If keys stick or drop under fast typing: check the 6502 emit pacing and the
  RDY handshake timing on the analyzer.
