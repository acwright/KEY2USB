KEY2USB — Controller (ATmega328/328P)
=====================================

Bare-metal AVR firmware that turns the KEY2USB cartridge into a **USB HID boot
keyboard** using [V-USB](https://www.obdev.at/products/vusb/). It reads C64/C128
key events from the 74LS273 latch (gated by the `RDY` flag), translates each
`keyID` to a USB HID usage, and sends 8-byte boot-keyboard reports.

Why bare-metal (no Arduino)
---------------------------
V-USB bit-bangs USB in software and needs tight, deterministic interrupt timing.
This is a frameworkless `avr-gcc` build. The V-USB stack is vendored in
`lib/usbdrv/`; the project config is `include/usbconfig.h`.

Layout
------
    include/usbconfig.h   V-USB configuration (HID boot keyboard, D+ = PD2/INT0)
    src/main.c            report loop, latch handshake, HID descriptor
    src/protocol.h        event-byte contract + pin helpers (mirrors Cart.inc)
    src/keymap.h          keyID -> HID usage table (editable)
    lib/usbdrv/           vendored V-USB
    fuses.cfg             fuse values for a 16 MHz crystal

Build & flash (PlatformIO)
--------------------------
    pio run                    # build (default env: atmega328)
    pio run -e atmega328p      # build for a 328P
    pio run -t upload          # flash CODE via minipro (uses the env's chip)

`platformio.ini` defaults to **atmega328** (the non-P chip on the test PCB).
Upload writes program memory **and** the fuses (`fuses.cfg`) each time, so a
fresh chip is fully configured in one `pio run -t upload`.

Fuses (one-time)
----------------
For a 16 MHz crystal, no bootloader, ISP enabled, BOD off:

| Fuse  | Value | Meaning |
|-------|-------|---------|
| LFUSE | `0xFF`| low-power crystal 8–16 MHz, slow rising power, CKDIV8 off |
| HFUSE | `0xDF`| SPIEN on, no bootloader (BOOTRST=1), reset enabled |
| EFUSE | `0xFF`| brown-out detector disabled |
| LOCK  | `0xFF`| unlocked |

`fuses.cfg` holds these in minipro's config format (keys `lfuse`/`hfuse`/`efuse`/
`lock`, confirmed with minipro 0.7.4). **The critical one is LFUSE**: a
factory-fresh 328 reads `lfuse = 0x62` (internal 8 MHz RC ÷8 = 1 MHz), which must
become `0xFF` for the external 16 MHz crystal or V-USB will not run.

    # optional: read current values (also confirms the file format)
    minipro -p "ATMEGA328@DIP28" -c config -r current.cfg
    # write the fuses
    minipro -p "ATMEGA328@DIP28" -c config -w fuses.cfg

minipro drives the ZIF socket directly, so it can still reprogram a chip whose
fuses select the external crystal — setting LFUSE=0xFF is not a lock-out.

USB identity
------------
Uses obdev's free shared VID/PID for HID-class devices: `0x16c0/0x27db`
(product string `KEY2USB`). Fine for personal use; see V-USB's
`USB-IDs-for-free.txt` for the rules.

The keymap
----------
`src/keymap.h` maps each `keyID` to a USB HID usage:

- `0x00`      — ignored
- `0x01..0xDF`— normal key (placed in the 6-key report array)
- `0xE0..0xE7`— modifier (Left Ctrl … Right GUI), OR-ed into the modifier byte

The defaults are the **inverse of VICE's stock C64 positional keymap**
(`gtk3_pos.vkm`). Because the cartridge sends *raw physical key positions plus
the raw SHIFT/CTRL/C= state*, use VICE's **Positional** keymap (not Symbolic) so
the C64 characters are reproduced correctly. Non-obvious defaults that match
VICE positional:

    C64 CTRL  -> HID Tab          C64 C=        -> HID Left Ctrl (modifier)
    C64 R/S   -> HID Escape       C64 CLR/HOME  -> HID Home
    C64 £     -> HID End          C64 =         -> HID Page Down
    C64 up    -> HID '\'          C64 left      -> HID '`'

Edit the table freely for other hosts/emulators. keyIDs 64–127 (C128 extended
keys) are unmapped pending hardware verification.

What's verified
---------------
Compiles clean for both the 328 and 328P; the HID report descriptor was
byte-checked (45 bytes, balanced, valid boot keyboard). USB enumeration and the
latch handshake are validated on real hardware during bring-up (V-USB traffic
can't be exercised in the build tools here).
