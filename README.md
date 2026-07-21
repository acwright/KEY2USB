KEY2USB
=======

![KEY2USB](./Images/KEY2USB.png)

A non-invasive **Commodore 64** expansion port cartridge that lets the machine's own physical keyboard act as a **USB HID keyboard** for a connected PC running the VICE emulator. Plug it in, power on the C64, connect a USB cable — no case modification, no soldering into the keyboard.

---

## Table of Contents

- [Overview](#overview)
- [Compatibility](#compatibility)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Mode Jumper](#mode-jumper)
- [Hardware](#hardware)
  - [KEY2USB Board](#key2usb-board)
    - [Revision History](#revision-history)
- [Firmware](#firmware)
- [VICE Setup](#vice-setup)
  - [Joysticks](#joysticks)
  - [Verifying your setup](#verifying-your-setup)
  - [VIC-20 (xvic)](#vic-20-xvic)
- [Software](#software)
- [CAD](#cad)
- [Production](#production)
- [Schematics](#schematics)
- [Libraries](#libraries)
- [Bill of Materials](#bill-of-materials)
- [Purchase](#purchase)
- [License](#license)

---

## Overview

**KEY2USB** is a C64 cartridge that solves a specific problem: when running the VICE emulator on a PC alongside a real Commodore 64, you can't easily use the C64's authentic keyboard as a USB input device without modifying the machine. KEY2USB plugs into the expansion port and bridges the C64's keyboard matrix — read by the C64's own 6502 — to a USB HID keyboard interface, using no invasive hardware modifications.

Nothing inside the machine is touched. The cartridge takes over the C64 on power-up, scans the keyboard matrix itself, and reports every make/break to the PC as a standard USB HID boot keyboard. Power comes from the expansion port; the only cable is USB.

## Compatibility

| Machine | Supported | Notes |
|---------|-----------|-------|
| **Commodore 64** (all revisions) | Yes | Primary target |
| **Commodore 64C** | Yes | Identical keyboard matrix |
| **Commodore 128 / 128D** | Yes | Runs in C64 mode — see below. Verified on real hardware |
| **Ultimate 64** | Yes | Verified on real hardware |

On a **C128**, the cartridge asserts `/EXROM`, which the C128 detects at reset and
uses to boot straight into C64 mode — so KEY2USB comes up on its own with no key
combination needed. The full C128 keyboard is *not* scanned: the extra keys
(numeric keypad, ESC, TAB, ALT, HELP, and the separate cursor pad) sit outside the
standard 8×8 matrix and are not reported. Every key the C128 shares with the C64
works normally.

If a particular C128 does not autostart, power on while holding the **C=** key to
force C64 mode.

## Quick Start

1. With the C64 **powered off**, insert KEY2USB into the expansion port.
2. Connect the USB cable to your PC. The device enumerates as a standard HID
   keyboard — no drivers needed.
3. Power on the C64. The `KEY2USB` splash screen appears; the cartridge has taken
   over the machine and is scanning the keyboard.
4. In VICE, set **Settings → Keyboard → Keyboard Mapping → Positional**. This step
   is mandatory — see [VICE Setup](#vice-setup).
5. Type on the C64. Keystrokes arrive at the PC.

While KEY2USB is running, the C64 is dedicated to being a keyboard — it does not
return to BASIC. Power off and remove the cartridge to use the machine normally.

## Architecture

- **ROM side**: A 28C64 EEPROM holds two 4K firmware banks. The bank and `/EXROM` state are selected together by a single `MODE` jumper, set to **C64** on shipping units — see [Mode Jumper](#mode-jumper).
- **Glue logic**: A 74LS32 (quad OR gate) generates a write strobe from `/IO1` + `R/W`; a 74LS273 (8-bit D flip-flop register) latches the key-event byte the 6502 firmware writes to `$DE00`; a 74LS74 (dual D flip-flop) provides a single `RDY` handshake flag.
- **USB side**: An ATmega328P-PU runs the [V-USB](https://www.obdev.at/products/vusb/index.html) software USB stack, polls the latch via the `RDY` flag, and sends 8-byte USB HID boot-protocol keyboard reports. A 16 MHz crystal clocks the MCU.
- **USB front end**: Two 68Ω series resistors on D+ and D−, two 1N5227B (3.6V) Zener diodes to clamp the lines to spec, and a 1.5kΩ D− pull-up to +5V to signal a low-speed USB device — no 3.3V rail needed.
- **PCB constraint**: 100% through-hole / DIP — no SMD parts.

The two sides share only a single byte-wide latch and one ready flag — no shared clock or bus timing requirements.

## Mode Jumper

The board carries a 3-pin `MODE` header (J1) that selects the EEPROM bank and the
`/EXROM` state together:

| Jumper position | EEPROM bank | `/EXROM` | Behavior |
|-----------------|-------------|----------|----------|
| **C64** (GND) — *factory default* | Lower 4K | Asserted | Autostarts via the `CBM80` signature. On a C128, forces a boot into C64 mode. |
| **C128** (+5V) | Upper 4K | Released | Autostarts as a C128 external function ROM in native mode. |

**Assembled cartridges ship with the jumper set to C64 and the case closed over
it.** The C64 bank is the supported configuration; it covers the C64, C64C, Ultimate 64, 
and the C128 by way of C64 mode. There is no need to change it, and the case has no opening for it.

The C128 bank is retained for developers and the curious. It is stable for the
standard 8×8 matrix — the same key coverage the C64 bank provides — but it offers
no advantage over C64 mode, since scanning of the C128-only extended keys is
incomplete and disabled. Changing the jumper means opening the case, and is
entirely at your own discretion.

## Hardware

This repository contains the KiCad 10.0 PCB design for the KEY2USB board.

### KEY2USB Board
`Hardware/`

A single cartridge PCB hosting the ROM, glue logic, and USB MCU. Provides:

- **ROM**: 28C64 EEPROM (DIP-28) preloaded with the keyboard-scan firmware
- **Write strobe**: 74LS32 quad OR gate — asserts `WRSTB` from `/IO1` + `R/W`
- **Key-event latch**: 74LS273 octal D flip-flop register — captures the byte written to `$DE00`
- **Handshake flag**: 74LS74 dual D flip-flop — one half as the `RDY`/`/CLRRDY` flag
- **USB MCU**: ATmega328P-PU (DIP-28) running V-USB, reads the latch, emits USB HID reports
- **Crystal**: 16 MHz THT crystal + 2× 20pF load capacitors
- **USB front end**: USB Type B connector, 68Ω series resistors, 1N5227B Zener clamps, 1.5kΩ D− pull-up
- **Mode select**: 3-pin 2.54mm jumper header — set to C64 at the factory (GND, asserts `/EXROM`, lower 4K EEPROM bank); see [Mode Jumper](#mode-jumper)
- **Bus connection**: 44-pin C64 expansion port edge connector
- **Power**: Drawn from the C64's own +5V via the expansion port

#### Revision History

**Rev 1.0**

- Initial release.

## Firmware

Both firmwares are implemented in `Firmware/` (see `Firmware/README.md` for build,
flash, and layout details). Set VICE's keyboard mapping to **Positional** — see
[VICE Setup](#vice-setup).

**6502 side (C64 bank — the shipping configuration):**
- Autostart via the `CBM80` signature, take over the machine, and draw a centered `KEY2USB` splash on the 40-column screen.
- Scan the 8×8 keyboard matrix directly via CIA #1 (`$DC00`/`$DC01`) for raw make/break events and modifier state — no KERNAL buffer.
- Scan **both joystick ports** on the same CIA #1 ports (they share the matrix lines, so no extra hardware is involved).
- On any key or joystick state change, write a one-byte event to `$DE00`.

The upper bank holds the C128 native-mode firmware, which autostarts from a
`CBM` / `$01` external function ROM header and scans the same 8×8 matrix. Extended-key
scanning via `$D02F` is present in the source but gated behind a build flag and not
compiled in — it is unverified on hardware. See `Firmware/Cart/README.md`.

**ATmega328/328P side:**
- Poll `RDY`; on set, read the key byte from `PINC`/`PINB`, pulse `/CLRRDY`.
- Run V-USB (low-speed USB 1.1); translate to USB HID usages and send an 8-byte boot-protocol keyboard report.
- Configured as a self-powered USB device.

## VICE Setup

One setting trips people up every time, so set it before anything else:

- **Keyboard mapping must be Positional, not Symbolic.** In VICE:
  **Settings → Keyboard → Keyboard Mapping → Positional**. This is the single
  most common first-time setup mistake — if keys look wrong, check this first.
  The reason is worth understanding, because it explains the whole signal path:

  A USB keyboard never transmits characters. Press `A` and it sends HID usage
  `0x04`; the USB spec names that "Keyboard a and A", but the name is only
  documentation — the code means *"the key where a US keyboard has A"*. Your OS
  decides it is an `A` by applying the selected layout. On AZERTY the same key
  sends the same `0x04` and the OS renders `Q`.

  KEY2USB is positional end to end for exactly that reason. The 6502 detects a
  key by matrix position (`col*8 + row`) and never computes a character; the
  ATmega looks that keyID up in `keymap.h` and emits the HID usage for the PC key
  in the corresponding physical spot; VICE's Positional keymap maps PC positions
  back onto C64 matrix positions. Positions in, positions through, positions out
  — nothing resolves to a character until VICE finally does it.

  Symbolic breaks that chain by inserting a translation. Press **SHIFT + 2**,
  which is `"` on a C64. The cartridge sends shift plus the position code for
  `2`; the host applies its US layout and concludes you typed `@`. Symbolic then
  asks "which C64 key produces `@`?" and presses that one — wrong. Positional
  ignores the character entirely, sees "physical shift + physical 2", and gives
  you the `"` you actually pressed. The keystroke arrived correctly either way;
  Symbolic just did an unwanted extra translation using a PC layout that does
  not match a C64's.
- USB HID reports are sent as a standard boot-protocol keyboard — no special
  VICE driver or configuration is needed beyond the keymap.

### Joysticks

Both joystick ports are scanned by the cartridge and arrive at the host as
**ordinary keystrokes**, so VICE has to be told which keys mean "joystick".
Everything lives on the numeric keypad, split so the two ports cannot collide:

**Port 2** — the easy one, no configuration at all:

> **Settings → Joystick → Joystick Port #2 → Numpad**

VICE's built-in Numpad device already maps keypad digits (`8/2/4/6` for
directions, `7/9/1/3` for diagonals, `0`/`5` for fire), and the cartridge's
port-2 mapping was chosen to match it exactly.

**Port 1** — needs a keyset, because Numpad can only serve one port:

> **Settings → Joystick → Joystick Port #1 → Keyset A**, then
> **Configure Keyset A**:

| Direction | Key |
|-----------|-----|
| North | Keypad **−** |
| South | Keypad **+** |
| West  | Keypad **/** |
| East  | Keypad **&ast;** |
| Fire  | Keypad **enter** |

Port 1 uses keypad *symbols* rather than digits or function keys for two
reasons: the digits are already claimed by the Numpad device serving port 2,
and the function-key row proved unreliable — F12 was silently undeliverable on
a macOS + GTK3 VICE host, with no identifiable cause. The symbols are untouched
by both.

### A caveat worth knowing

A held joystick direction grounds a line in the keyboard matrix, so it also
**phantom-presses real keys** — exactly as it does on a real C64. This is
inherent to the wiring, not a firmware choice, and it is left in place so the
cartridge behaves like the bare machine.

It hits **port 1** hardest: a held direction grounds a matrix *row*, pressing
all 8 keys in it — which includes RETURN, INST/DEL and CLR/HOME. Expect stray
keystrokes while a port-1 direction is held. **Port 2 is the one to use in
practice**; it grounds a column instead, which only aliases if you are also
pressing a key in that same column.

### Verifying your setup

`Software/key2usbtest.prg` shows live joystick state for both ports plus the
last keys received, so you can confirm the cartridge and your VICE
configuration in one place. See [Software/](Software/).

### VIC-20 (`xvic`)

The cartridge also drives VICE's VIC-20 emulator, with the same **Positional**
setting and no keymap changes. This works because VICE's two positional keymaps
are the same map in different coordinates — `VIC20/gtk3_pos.vkm` states the
relationship outright:

    # to convert from C64 to VIC20:
    # change rows 7 -> 0, 0 -> 7
    # change columns 7 -> 3, 3 -> 7

Applying that permutation and diffing the two files (VICE 3.x, GTK3, US layout)
gives:

| | |
|---|---|
| Host keysyms in each map | 151 / 151 |
| Present in one but not the other | 0 |
| Agree under the permutation | 150 |
| Differ | 1 |

The lone difference is cosmetic: `>` sits at matrix position `5 4` in both, but
carries shiftflag `1` on the C64 ("combined with shift") and `8` on the VIC-20
("can be shifted or not"). The cartridge sends the physical `.` key and physical
SHIFT as separate events, so both yield `>` regardless. The RESTORE entries
(`Page_Up` / `F12` / `Prior`) and all twenty joyport keypad entries are identical.

Both emulators therefore consume the same host keys and route them to the
same-labelled machine keys. `keymap.h` is built as the inverse of the C64
positional map, which makes it equally the inverse of the VIC-20 one.

Two caveats:

- This was established by comparing the shipped keymap files, not by a hardware
  session on `xvic`. The mapping is confirmed; end-to-end behaviour is not.
- **The VIC-20 has only one control port.** Point the cartridge's port-2 mapping
  (the keypad digits, via the Numpad device) at it; the port-1 keyset has nothing
  to connect to.

## Software
`Software/`

Host-side test software. `key2usbtest.prg` runs inside VICE and shows live
joystick state for both ports plus the last keystrokes received, so you can
verify a cartridge and your VICE configuration in one place. Build with
`make` (requires `petcat`, which ships with VICE) or use the prebuilt `.prg`.
See [Software/README.md](Software/README.md).

## CAD
`CAD/`

3D models and render images for the KEY2USB board.

## Production
`Production/`

JLCPCB-ready fabrication files, BOM, and component positions for PCB fabrication.

## Schematics
`Schematics/`

PDF schematic for the KEY2USB board.

## Libraries
`Libraries/`

Custom KiCad symbol and footprint libraries, including the C64 expansion port edge connector footprint and the USB Type B connector footprint.

## Bill of Materials

| Reference | Qty | Value | Description | Digikey |
|-----------|-----|-------|-------------|---------|
| C1, C2, C3, C4 | 4 | 100nF | Ceramic disc capacitor — IC bypass | [478-5732-ND](https://www.digikey.com/en/products/filter?keywords=478-5732-ND) |
| C5, C6 | 2 | 20pF | Ceramic disc capacitor — crystal load | [478-7724-ND](https://www.digikey.com/en/products/filter?keywords=478-7724-ND) |
| D1, D2 | 2 | 1N5227B | 3.6V Zener diode, DO-35 — USB line clamp | [1N5227B-ND](https://www.digikey.com/en/products/filter?keywords=1N5227B-ND) |
| J1 | 1 | MODE | 3-pin 2.54mm header + jumper cap — mode select, factory-set to C64 | [S1121EC-03-ND](https://www.digikey.com/en/products/filter?keywords=S1121EC-03-ND) |
| J2 | 1 | C64 EXP PORT | C64 expansion port edge connector (44-pin, 3.96mm pitch) | |
| J3 | 1 | USB | USB Type B connector, through-hole (UJ2-BH-BL1-TH) | [102-5886-ND](https://www.digikey.com/en/products/filter?keywords=102-5886-ND) |
| R1, R2 | 2 | 68Ω | Resistor, 1/4W — USB D+ / D− series | [S68CACT-ND](https://www.digikey.com/en/products/filter?keywords=S68CACT-ND) |
| R3 | 1 | 1.5kΩ | Resistor, 1/4W — USB D− pull-up to +5V | [S1.5KCACT-ND](https://www.digikey.com/en/products/filter?keywords=S1.5KCACT-ND) |
| U1 | 1 | 28C64 | 8K×8 EEPROM, DIP-28 — holds C64 and C128 firmware banks | [AT28C64B-15PU-ND](https://www.digikey.com/en/products/filter?keywords=AT28C64B-15PU-ND) |
| U2 | 1 | 74LS32 | Quad 2-input OR gate, DIP-14 — generates write strobe | [296-1658-5-ND](https://www.digikey.com/en/products/filter?keywords=296-1658-5-ND) |
| U3 | 1 | 74LS273 | 8-bit D flip-flop register, DIP-20 — key-event latch | [296-1657-5-ND](https://www.digikey.com/en/products/filter?keywords=296-1657-5-ND) |
| U4 | 1 | 74LS74 | Dual D flip-flop, DIP-14 — RDY handshake flag | [296-1668-5-ND](https://www.digikey.com/en/products/filter?keywords=296-1668-5-ND) |
| U5 | 1 | ATmega328P-PU | 8-bit AVR MCU, DIP-28 — V-USB and HID firmware | [ATMEGA328-PU-ND](https://www.digikey.com/en/products/filter?keywords=ATMEGA328-PU-ND) |
| Y1 | 1 | 16 MHz | Crystal, through-hole — ATmega328P clock | [3155-16M20P2/49US-ND](https://www.digikey.com/en/products/filter?keywords=3155-16M20P2/49US-ND) |

## Purchase

KEY2USB is available as a kit on Tindie for those who would rather not order
boards from a fab and source parts themselves.

<a href="https://www.tindie.com/products/acwrightdesign/key2usb-commodore-64-keyboard-to-usb-kit/?ref=offsite_badges&utm_source=sellers_acwrightdesign&utm_medium=badges&utm_campaign=badge_medium"><img src="https://static.tindie.com/badges/tindie-mediums.png" alt="I sell on Tindie" width="150" height="78"></a>

## License

Hardware designs are released under the [CERN Open Hardware Licence Version 2 – Permissive](https://ohwr.org/cern_ohl_p_v2.txt).
