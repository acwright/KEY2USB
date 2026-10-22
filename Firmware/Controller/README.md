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
For a 16 MHz crystal, no bootloader, ISP enabled, brown-out reset at 4.3 V:

| Fuse  | Value | Meaning |
|-------|-------|---------|
| LFUSE | `0xFF`| low-power crystal 8–16 MHz, slow rising power, CKDIV8 off |
| HFUSE | `0xDF`| SPIEN on, no bootloader (BOOTRST=1), reset enabled |
| EFUSE | `0xFC`| brown-out detector at 4.3 V (v1.1 and earlier: `0xFF`, disabled) |
| LOCK  | `0xFF`| unlocked |

The brown-out level matters because 16 MHz is only in spec above ~3.8 V. With
BOD off, a supply dip leaves the chip running out of spec, where it can do
anything, including send garbage keystrokes. At 4.3 V it is held in reset
until the supply recovers. The C64's +5 V rail is regulated, so this never
trips in normal use.

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
Uses obdev's free shared VID/PID for USB keyboards, `0x16c0/0x27db`, with
manufacturer string `acwright` and product string `KEY2USB`. That PID belongs
to obdev's *serial-number* set, whose rules let a device omit the serial number
when it relies only on the operating system's default class driver — true for
a HID keyboard. See V-USB's `USB-IDs-for-free.txt`.

`bcdDevice` carries the firmware version (`1.30` = v1.3.0).

Reliability
-----------
Two mechanisms keep a key from staying held on the host:

- **SYNC.** The cartridge sends event `0x7F` at reset and about once a second
  while nothing is held; the controller then releases every key and modifier it
  still holds. This covers releases that never reached the controller.
- **Every report goes out twice.** V-USB marks an interrupt-IN report as sent
  the moment it transmits it, without waiting for the host's ACK
  (`lib/usbdrv/asmcommon.inc`). macOS sets a 24 ms HID idle rate, so it gets
  the full state again within 24 ms regardless, but a host that sets idle rate
  0 never asks again, and a lost "all released" report would leave a key held
  until the next keystroke. Hosts ignore an identical repeat.

There is no interrupt besides V-USB's: the 4 ms idle-rate tick polls the Timer0
flag. V-USB requires any other ISR to be interruptible, and a plain timer ISR
can delay the USB interrupt past what it tolerates.

Licensing
---------
The KEY2USB sources in `src/` and `include/` are MIT-licensed, but the firmware
links the vendored V-USB driver (`lib/usbdrv/`), which is licensed under the
GNU GPL v2 or v3 (`lib/usbdrv/License.txt`). The built firmware image is
therefore distributed under the GPL, with this repository as its
corresponding source.

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

    C64 RESTORE -> HID Page Up    (VICE positional's RESTORE key; keyID 126)

Edit the table freely for other hosts/emulators. keyIDs 125 and 127 are the
SYNC events and are handled before any table is consulted.

### C128 mode

When the cartridge's C128 bank is running (mode jumper on C128), it sends
**SYNC128** (`0x7D`) instead of SYNC, and the controller switches to `x128`'s host
keys until it next sees a plain SYNC. `keymap128` in `keymap.h` lists the
overrides: the inverse of VICE's `x128` positional keymap (`C128/gtk3_pos.vkm`).

| C128 key | Host key | | C128 key | Host key |
|----------|----------|-|----------|----------|
| F1 / F3 / F5 / F7 | F1 / F2 / F3 / F4 | | ESC | F9 |
| HELP | F5 | | TAB | F10 |
| LINE FEED | F6 | | ALT | F11 |
| 40/80 DISPLAY | F7 (tap) | | CAPS LOCK | F12 (tap) |
| NO SCROLL | F8 | | Keypad, cursor pad | Keypad, arrows |

`main.c` handles two cases a table cannot:

- **CRSR L/R, CRSR U/D.** `x128` gives these no host key in native mode; the host
  arrows drive the separate cursor pad, and SHIFT does not reverse the pad (the
  KERNAL's decode tables at `$FA80` give shifted → as → again). So they are sent
  as Right/Down, or Left/Up when a SHIFT is held at the moment of the press. The
  release always matches whatever was pressed.
- **CAPS LOCK, 40/80 DISPLAY.** These latch mechanically, but `x128` toggles them
  on each host key press. Every movement of the latch is sent as one tap (pressed
  for two reports, then released).

In C128 mode the joystick ports keep their C64-mode keys, which are keypad keys,
so they share host keys with the C128 keypad. That is unavoidable when `x128`
uses the whole keypad for the C128 keypad.

Joysticks
---------
Both joystick ports are scanned by the cartridge and arrive as ordinary key
events, so the host just sees keystrokes. Defaults:

| Port | keyIDs | Up | Down | Left | Right | Fire |
|------|--------|----|------|------|-------|------|
| 2    | 112–116| Keypad 8 | Keypad 2 | Keypad 4 | Keypad 6 | Keypad 0 |
| 1    | 120–124| Keypad − | Keypad + | Keypad / | Keypad &ast; | Keypad enter |

Port 1 avoids the function-key row because **F12 never arrives in VICE as a
key** (seen on hardware 2026-07-19: F8–F11 all registered, F12 never did, even
from the host keyboard). The reason: VICE's positional keymap binds F12 to
RESTORE (`gtk3_pos.vkm`: `F12 -3 0`), so VICE consumes it as the RESTORE line.

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
