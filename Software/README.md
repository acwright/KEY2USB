KEY2USB — Host Test Software
============================

`key2usbtest.prg` is a small BASIC program that verifies a KEY2USB cartridge
end to end. It runs **inside VICE on the host PC**, not on the Commodore — the
C64/C128 is busy being a keyboard. It displays what VICE actually received:
live joystick state for both ports, and the last key plus a short history.

Use it to answer "is the cartridge working, and is VICE configured correctly?"
without guessing.

Build
-----
Requires `petcat`, which ships with [VICE](https://vice-emu.sourceforge.io/).

    make            # -> key2usbtest.prg
    make run        # build, then launch it in x64sc
    make clean

Or load the prebuilt `key2usbtest.prg` directly: drag it onto a running VICE
window, use **File → Autostart disk/tape image…**, or `x64sc key2usbtest.prg`.

Reading the display
-------------------
    key2usb test

    joy2: . . . . .   7F
    joy1: . . . . .   FF

    key:  a   065
    typed: hello

- **joy2 / joy1** — one slot per contact: `U D L R F`. A dot means open, the
  letter means closed. The two hex digits are the raw CIA register byte
  (`$DC00` for port 2, `$DC01` for port 1).
- **key** — the last key VICE received, as a character plus its PETSCII code.
- **typed** — the last 20 characters, so you can type a phrase and check it.

Expected raw values for port 1, one bit dropping per direction: `FE` up,
`FD` down, `FB` left, `F7` right, `EF` fire.

**Ignore the joy2 raw byte while keys are being pressed.** `$DC00` is the
keyboard column-drive register, so it reflects KERNAL matrix scanning, not just
joystick state — it will show nonsense like `60` mid-keystroke. That is an
artifact of the shared register on the *emulated* machine, not a fault.

Why it pokes the screen instead of printing
-------------------------------------------
Every live field is written straight to screen RAM and keys are never echoed
with `PRINT`. This is deliberate, and it is the difference between a usable
test and a misleading one.

A joystick held in port 1 grounds a keyboard matrix row, which phantom-presses
all 8 keys in that row — and those rows contain **RETURN, INST/DEL, CLR/HOME
and CRSR**. A `PRINT`/`GET` display receives those as real control characters,
so the screen scrolls, homes and deletes underneath the readout. An earlier
version of this program did exactly that and reported impossible values (a
`PEEK` result of 967, which cannot exceed 255), which cost real debugging time
chasing a phantom firmware bug. Poking fixed screen positions is immune.

VICE setup
----------
See [VICE Setup](../README.md#vice-setup) in the top-level README — the
keyboard mapping and joystick keyset configuration both matter, and the wrong
keyboard mapping makes a perfectly working cartridge look broken.
