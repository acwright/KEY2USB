/* =============================================================================
 *  keymap.h - KEY2USB keyID -> USB HID usage table
 * =============================================================================
 *  Indexed by keyID (C64 matrix code = col*8 + row). Each entry is a USB HID
 *  Usage ID (HID Usage Page 0x07, Keyboard/Keypad):
 *
 *    - 0x00            : no key mapped (event ignored)
 *    - 0x01..0xDF      : a normal key; placed in the 6-key report array
 *    - 0xE0..0xE7      : a modifier (LCtrl..RGUI); OR-ed into the modifier byte
 *                        (modifier bit = usage - 0xE0)
 *
 *  These defaults are the INVERSE of VICE's stock C64 *positional* keymap
 *  (share/vice/C64/gtk3_pos.vkm). Because the cartridge sends raw physical
 *  key positions plus the raw SHIFT/CTRL/C= state, VICE must use its
 *  Positional keymap (not Symbolic) for the round-trip to reproduce the
 *  correct C64 characters. With Positional selected these map 1:1.
 *
 *  Notable non-obvious choices (matching VICE positional):
 *    C64 CTRL  -> HID Tab        C64 C=       -> HID Left Ctrl (modifier)
 *    C64 R/S   -> HID Escape     C64 CLR/HOME -> HID Home
 *    C64 pound -> HID End        C64 =        -> HID Page Down
 *    C64 up-arrow -> HID '\'     C64 left-arrow -> HID '`'
 *
 *  Edit freely to taste (or to target a different host/emulator). RESTORE is
 *  not in the matrix (it is wired to NMI and swallowed by the ROM), so it has
 *  no entry here.
 */
#ifndef KEY2USB_KEYMAP_H
#define KEY2USB_KEYMAP_H

#include <avr/pgmspace.h>

/* Common HID usages for readability. */
#define HID_NONE      0x00
#define HID_A         0x04
#define HID_ENTER     0x28
#define HID_ESC       0x29
#define HID_BSPACE    0x2A
#define HID_TAB       0x2B
#define HID_SPACE     0x2C
#define HID_HOME      0x4A
#define HID_PGDN      0x4E
#define HID_RIGHT     0x4F
#define HID_END       0x4D
#define HID_DOWN      0x51
#define HID_LCTRL     0xE0
#define HID_LSHIFT    0xE1
#define HID_RSHIFT    0xE5

/* keyID (col*8+row) -> HID usage. 128 entries; 64..127 reserved for C128
 * extended keys, left unmapped until verified on real C128 hardware. */
static const uint8_t keymap[128] PROGMEM = {
    /*  0 INST/DEL   */ HID_BSPACE,
    /*  1 RETURN     */ HID_ENTER,
    /*  2 CRSR L/R   */ HID_RIGHT,
    /*  3 F7         */ 0x40,   /* F7 */
    /*  4 F1         */ 0x3A,   /* F1 */
    /*  5 F3         */ 0x3C,   /* F3 */
    /*  6 F5         */ 0x3E,   /* F5 */
    /*  7 CRSR U/D   */ HID_DOWN,
    /*  8 3          */ 0x20,
    /*  9 W          */ 0x1A,
    /* 10 A          */ 0x04,
    /* 11 4          */ 0x21,
    /* 12 Z          */ 0x1D,
    /* 13 S          */ 0x16,
    /* 14 E          */ 0x08,
    /* 15 LEFT SHIFT */ HID_LSHIFT,
    /* 16 5          */ 0x22,
    /* 17 R          */ 0x15,
    /* 18 D          */ 0x07,
    /* 19 6          */ 0x23,
    /* 20 C          */ 0x06,
    /* 21 F          */ 0x09,
    /* 22 T          */ 0x17,
    /* 23 X          */ 0x1B,
    /* 24 7          */ 0x24,
    /* 25 Y          */ 0x1C,
    /* 26 G          */ 0x0A,
    /* 27 8          */ 0x25,
    /* 28 B          */ 0x05,
    /* 29 H          */ 0x0B,
    /* 30 U          */ 0x18,
    /* 31 V          */ 0x19,
    /* 32 9          */ 0x26,
    /* 33 I          */ 0x0C,
    /* 34 J          */ 0x0D,
    /* 35 0          */ 0x27,
    /* 36 M          */ 0x10,
    /* 37 K          */ 0x0E,
    /* 38 O          */ 0x12,
    /* 39 N          */ 0x11,
    /* 40 +          */ 0x2D,   /* host '-'  */
    /* 41 P          */ 0x13,
    /* 42 L          */ 0x0F,
    /* 43 -          */ 0x2E,   /* host '='  */
    /* 44 .          */ 0x37,   /* host '.'  */
    /* 45 :          */ 0x33,   /* host ';'  */
    /* 46 @          */ 0x2F,   /* host '['  */
    /* 47 ,          */ 0x36,   /* host ','  */
    /* 48 POUND      */ HID_END,
    /* 49 *          */ 0x30,   /* host ']'  */
    /* 50 ;          */ 0x34,   /* host '\'' */
    /* 51 CLR/HOME   */ HID_HOME,
    /* 52 RIGHT SHIFT*/ HID_RSHIFT,
    /* 53 =          */ HID_PGDN,
    /* 54 UP ARROW   */ 0x31,   /* host '\'  */
    /* 55 /          */ 0x38,   /* host '/'  */
    /* 56 1          */ 0x1E,
    /* 57 LEFT ARROW */ 0x35,   /* host '`'  */
    /* 58 CTRL       */ HID_TAB,
    /* 59 2          */ 0x1F,
    /* 60 SPACE      */ HID_SPACE,
    /* 61 C=         */ HID_LCTRL,
    /* 62 Q          */ 0x14,
    /* 63 RUN/STOP   */ HID_ESC,
    /* 64..127 : C128 extended keys - fill after hardware verification */
    [64 ... 127] = HID_NONE,
};

#endif /* KEY2USB_KEYMAP_H */
