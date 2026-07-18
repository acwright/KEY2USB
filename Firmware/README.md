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
**Confirmed working end-to-end on real hardware**: a C64 Ultimate running VICE,
programmed 328 + AT28C64B, delivering real keystrokes over USB (VICE's keymap
must be set to **Positional**, not Symbolic — see the top-level README's
[VICE Setup](../README.md#vice-setup) section; this is *the* thing that trips
people up first).

Still to verify:
- C128 bank on real C128 hardware (verified autostart + splash in `x128`
  emulation only so far).
- C128 extended-key labels (keyIDs 64+) — the scan mechanism is in place but
  the per-key mapping needs confirming against a real C128 keyboard.

Bring-up plan (minimise reprogramming)
--------------------------------------
1. **ROM alone.** Program `Cart.bin`, MODE = C64. Power the C64: confirm the
   `KEY2USB / V1.0 / C64 MODE` splash. Flip MODE = C128 on a C128: confirm
   `C128 MODE`. (No USB needed yet.)
2. **Latch emission.** With a logic analyzer on `/IO1`, `R/W`, `PHI2` and
   `D0-D7`: press keys and confirm one write to `$DE00` per make/break, with the
   expected event byte (e.g. `A` press = `0x8A` → keyID 10 | 0x80; release =
   `0x0A`). Confirm `RDY` asserts on each write. This validates the whole 6502
   path independent of USB.
3. **Controller alone.** Program the 328 (code + fuses). Plug USB into the PC:
   the device should enumerate as `KEY2USB` HID keyboard. With the ROM emitting
   events, keystrokes should now reach the PC.
4. **End to end in VICE.** Start `x64sc`, select the **Positional** keymap
   (Settings → Keyboard → Keyboard Mapping), and type on the C64 — characters
   should appear in the emulator. Use `x128` for C128 extended keys.

Tips
----
- If nothing enumerates: re-check the 16 MHz fuses, D+/D- wiring (D+ must be on
  PD2/INT0), and the 68Ω / 1.5k / zener front end.
- If keys are wrong (or seem to do nothing) in VICE: check the Positional vs.
  Symbolic keymap first — this is the #1 gotcha. PAL vs. NTSC does not matter
  for the keyboard. Once Positional is confirmed, tune `Controller/src/keymap.h`
  for anything still off.
- If keys stick or drop under fast typing: check the 6502 emit pacing and the
  RDY handshake timing on the analyzer.
