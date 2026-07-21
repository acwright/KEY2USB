KEY2USB — Firmware
==================

Two independent firmwares that share exactly one thing: the **event byte**.

    Cart/         6502 autostart ROM for the 28C64 (C64 + C128 banks)
    Controller/   ATmega328/328P V-USB HID keyboard

    ┌──────────┐  scan matrix   ┌─────────┐  write $DE00   ┌─────────┐  RDY   ┌──────────┐  USB HID
    │ C64/C128 │ ─────────────► │  6502   │ ─────────────► │ 74LS273 │ ─────► │ ATmega328│ ───────►  PC
    │ keyboard │                │  ROM    │                │ + 74LS74│  latch │  (V-USB) │           (VICE)
    └──────────┘                └─────────┘                └─────────┘        └──────────┘

The 6502 ROM scans the keyboard matrix and writes one event byte to `$DE00`
per key transition; the 74LS273 latches it and the 74LS74 raises `RDY`. The
ATmega reads the latch, translates the keyID to a USB HID usage, and sends
boot-keyboard reports. The 6502 reports only matrix positions — the ATmega owns
the keyID → USB HID mapping.

Event byte (`$DE00` → latch → ATmega):

    bit 7      1 = pressed (make), 0 = released (break)
    bits 6..0  keyID   0..63    C64 matrix, col*8+row
                       64..87   C128 extended keys (optional scan)
                       112..116 joystick port 2 (up/down/left/right/fire)
                       120..124 joystick port 1 (up/down/left/right/fire)

Both joystick ports are scanned alongside the matrix — they already sit on
CIA#1, so this needs no extra hardware. Contacts are reported as ordinary key
events; `Controller/src/keymap.h` decides what they type.

Build and flash
---------------
    cd Cart && make eeprom          # build + program the 28C64
    cd Controller && pio run -t upload   # build + program the 328 (code + fuses)

See each subdirectory's README for details (linker/bank layout, fuses, keymap).

Notes
-----
- **VICE must use the Positional keymap**, not Symbolic. The path is positional
  end to end: the 6502 reports a matrix position, the ATmega emits the HID usage
  for the PC key in the matching physical spot, and Positional maps that back to
  a C64 matrix position. (HID usages are themselves positional — `0x04` means
  "the key where a US keyboard has A", not the letter A; the host layout decides
  the character.) Symbolic inserts a character translation using a PC layout and
  produces the wrong C64 key even though every keystroke arrived correctly. Full
  explanation in the top-level README's [VICE Setup](../README.md#vice-setup).
- The keyID → USB HID table lives in `Controller/src/keymap.h` and is easy to
  retarget for other hosts/emulators.
