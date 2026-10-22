KEY2USB — Host Test Software
============================

Two tools, for two questions:

| Tool | Runs on | Answers |
|------|---------|---------|
| `key2usbmon` | macOS, no emulator | Is the cartridge itself sending the right USB reports? |
| `key2usbtest.prg` | inside VICE (`x64sc`) | Is VICE configured to understand them? |
| `key2usbtest128.prg` | inside VICE (`x128`, C128 mode) | The same, for the cartridge's C128 mode |

Start with `key2usbmon` when anything looks wrong: it takes VICE out of the
picture.

key2usbmon (macOS)
------------------
A native command-line tool (Swift + IOKit) that opens the cartridge's USB HID
interface directly and prints every report it sends, decoded back to the C64
keys that produced it.

    make key2usbmon     # build (needs swiftc: xcode-select --install)
    make mon            # build + monitor
    make check          # build + press-every-key checklist

The first run asks for **Input Monitoring** permission for your terminal app
(System Settings → Privacy & Security → Input Monitoring). Grant it, quit and
reopen the terminal, and run again.

**Run it with `sudo` to seize the device** (`sudo ./key2usbmon`): macOS then
ignores the cartridge's keystrokes, so testing cannot Shift-click or Escape
your desktop. macOS only lets root seize a keyboard; without `sudo` it still
monitors, says `not seized`, and the keystrokes reach whatever app has focus —
so focus something harmless, like an empty TextEdit window.

### Monitor (default)

    key2usbmon - waiting for KEY2USB (USB 16c0:27db)... Ctrl-C to quit
    connected: acwright KEY2USB, bcdDevice 1.20 (v1.2+ controller firmware: SYNC + RESTORE)
    device seized: macOS ignores its keystrokes while key2usbmon runs

        time      gap      modifiers .. key slots         change
      (host HID idle rate: the state is re-sent every ~24 ms; identical reports are hidden, --all shows them)
       2.114s            20 00 00 00 00 00 00 00   +RIGHT SHIFT   held: RIGHT SHIFT
       2.130s +   16 ms  20 00 04 00 00 00 00 00   +A   held: A, RIGHT SHIFT

- **bcdDevice** is the controller firmware version: `1.20` is v1.2.0; `0.01`
  is v1.1 or earlier.
- The 8 hex bytes are the raw boot-keyboard report: modifier bits, a reserved
  byte, then six key slots.
- **change** names the C64 keys that went down (`+`) or up (`-`).
- macOS sets a 24 ms HID idle rate, so the device re-sends its unchanged state
  every 24 ms. Those identical reports are hidden; `--all` prints every report,
  including the deliberate second copy v1.2 firmware sends after each change.
- A key held for 10 seconds prints a **`! ... held for 10 s - stuck?`**
  warning. LEFT SHIFT held that long usually means SHIFT LOCK is down: it is
  wired in parallel with LEFT SHIFT and the cartridge cannot tell them apart.
- **Ctrl-C** prints a summary, including anything still held.

Things worth watching for: a key that stays in `held:` after you let go; reports
arriving when nobody is touching the C64; the device disconnecting and
reconnecting (the controller has reset).

### Checklist (`--check`)

Lists all 65 keys (the 64 matrix keys plus RESTORE) and ticks each one off once
it has been seen pressed **and** released, finishing with
`ALL 65 KEYS PASS`. Add `--joy` to require the ten joystick contacts as well.
A quick per-unit test before a cartridge ships.

### C128 mode (`--c128`)

With the cartridge's mode jumper on C128, the controller sends `x128`'s host keys
(see the top-level README). Add `--c128` so key2usbmon names keys accordingly:
the keypad as the C128 keypad, F5 as HELP, F9 as ESC and so on.
`--c128 --check` covers all 89 keys: the 64 matrix keys, RESTORE, the 22 extra
keys and the CAPS LOCK / 40/80 latches. In native mode the main CRSR keys share
host keys with the cursor pad's → and ↓, so each of those two lines is ticked by
either key.

The key names come from a copy of `Firmware/Controller/src/keymap.h` kept in
`key2usbmon.swift`; if you retarget the keymap, update that table too (unknown
usages still show as `HID 0xNN`).

key2usbtest.prg (inside VICE)
-----------------------------
A small BASIC program that verifies a KEY2USB cartridge end to end. It runs
**inside VICE on the host PC**, not on the Commodore — the C64/C128 is busy
being a keyboard. It displays what VICE actually received: live joystick state
for both ports, and the last key plus a short history.

Use it to answer "is VICE configured correctly?" without guessing.

Build
-----
Requires `petcat`, which ships with [VICE](https://vice-emu.sourceforge.io/).

    make key2usbtest.prg    # build
    make run                # build, then launch it in x64sc
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

key2usbtest128.prg (inside x128)
--------------------------------
The C128-mode counterpart, in BASIC 7.0, for a cartridge with its mode jumper
on C128. `key2usbtest.prg` cannot run there: it is a C64 BASIC 2 program saved
for `$0801`, while C128 BASIC programs start at `$1C01`.

    make key2usbtest128.prg     # build (petcat -w70)
    make run128                 # build, then launch it in x128

Or drag the prebuilt `key2usbtest128.prg` onto a running `x128` in C128 mode.

    key2usb test 128

    key:  kp 8         65
    mods: shift alt caps
    40/80: up   (40 col)

    joy2: -
    joy1: -

    typed: hello key2usb       66

- **key**: the key the C128 KERNAL sees held, named from its own matrix code
  (`PEEK(212)`; `-` and 88 = none). These codes are the cartridge's keyIDs, so
  every C128 key is named exactly, including the keypad, HELP, ESC, ALT,
  LINE FEED, NO SCROLL and the cursor pad. SHIFT, C=, CTRL and ALT never appear
  here; they are modifiers.
- **mods**: the KERNAL's modifier flags (`PEEK(211)`): SHIFT, C=, CTRL, ALT, and
  CAPS LOCK (latched).
- **40/80**: the 40/80 DISPLAY key (`PEEK(54533)` bit 7). It only changes the
  screen at reset, as on the real machine.
- **joy2 / joy1**: BASIC 7's `JOY()`: direction and fire.
- **typed**: the last 20 characters, plus the code of the last one. C128 BASIC
  expands F1-F8 and HELP into their key strings (`GRAPHIC`, `DLOAD"` …), so those
  show as text here; the **key** line shows the key itself.

The keypad and the port-2 joystick share host keys in C128 mode, so choose one:
for **joy2** to read the stick, set **Settings → Joystick → Joystick Port #2 →
Numpad** (or *Keypad*) and tick **Allow keyset joysticks** (until then the stick
just types keypad digits); to type on the keypad, set **Joystick Port #2 → None**. NO SCROLL pauses the
display (that is what it does in C128 mode); press it again to resume.

