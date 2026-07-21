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
`lock`). **The critical one is LFUSE**: a factory-fresh 328 ships at `0x62`
(internal 8 MHz RC ÷8 = 1 MHz) and must become `0xFF` for the external 16 MHz
crystal, or V-USB will not run.

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
(`gtk3_pos.vkm`), and that inversion is the whole design of this table: a HID
usage is itself a *position* (`0x04` means "the key where a US keyboard has A",
not the letter A), so each entry answers "which PC key sits where this C64 key
sits?" — never "which character does this key type?". VICE's **Positional**
keymap then maps those PC positions back onto C64 matrix positions and the
round trip closes. Symbolic breaks it by translating to characters through a PC
layout; see the top-level README's [VICE Setup](../../README.md#vice-setup).

Non-obvious defaults that match VICE positional:

    C64 CTRL  -> HID Tab          C64 C=        -> HID Left Ctrl (modifier)
    C64 R/S   -> HID Escape       C64 CLR/HOME  -> HID Home
    C64 £     -> HID End          C64 =         -> HID Page Down
    C64 up    -> HID '\'          C64 left      -> HID '`'

Edit the table freely for other hosts/emulators. keyIDs 64–87 (C128 extended
keys) are unmapped by default — see the Cart README to enable that scan.

Joysticks
---------
Both joystick ports are scanned by the cartridge and arrive as ordinary key
events, so the host just sees keystrokes. Defaults:

| Port | keyIDs | Up | Down | Left | Right | Fire |
|------|--------|----|------|------|-------|------|
| 2    | 112–116| Keypad 8 | Keypad 2 | Keypad 4 | Keypad 6 | Keypad 0 |
| 1    | 120–124| Keypad − | Keypad + | Keypad / | Keypad &ast; | Keypad enter |

Port 1 avoids the function-key row because **F12 proved undeliverable on a
macOS + GTK3 VICE host** (verified 2026-07-19: F8–F11 all registered, F12 never
did — including pressed directly on the host keyboard with the cartridge
unplugged). The standard-function-keys setting, macOS symbolic hotkeys, VICE's
hotkey files and the SDL menu key were all ruled out; the root cause was never
found, so port 1 steers clear of that row entirely.

Keypad **digits** are equally unusable: VICE's Numpad device — the port-2
setting — claims KP 7/9/1/3 for diagonals and KP 0/5 for fire, so digits would
cross-trigger between the two ports. Only the symbols are free, and they sit
sensibly on the pad (`/` left of `*`, `−` above `+`).

Point VICE at them with **Settings → Joystick → Keyset A / Keyset B**, then
assign the keyset to the emulated port.

Both sets use usages that **no matrix key can produce**, which is deliberate.
A held port-1 direction grounds a row line and phantom-presses all 8 keys in
that row, so an earlier mapping to `W/S/A/D` was indistinguishable from the
stick's own crosstalk — pressing left emitted `A, D, G, J, L`, which is exactly
row 2 of the C64 matrix. F8–F12 and the keypad never appear in the keyboard
table above, so they are unambiguous.

Two things to know:

- **Keypad usages can depend on NumLock** on some hosts. If port 2 misbehaves,
  either switch NumLock on or retarget those five entries.
- The HID boot keyboard reports **6 non-modifier keys at once**, and
  `keyDown()` silently drops past six. This is why the cartridge scans the
  joysticks *before* the matrix: a held port-1 direction generates 8 phantom
  key events, which would otherwise claim every slot and starve the real
  joystick event. Port 1 remains inherently noisy — the phantoms are genuine
  C64 behaviour — so port 2 is the one to use in practice.
