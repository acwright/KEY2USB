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
 *  not in the matrix (it is wired to NMI); the cartridge reports it as keyID
 *  126, mapped to Page Up - VICE's positional RESTORE key - so RUN/STOP +
 *  RESTORE works in the emulator.
 */
#ifndef KEY2USB_KEYMAP_H
#define KEY2USB_KEYMAP_H

#include <avr/pgmspace.h>

#include "protocol.h"   /* JOY2_* / JOY1_* keyIDs */

/* Common HID usages for readability. */
#define HID_NONE      0x00
#define HID_A         0x04
#define HID_ENTER     0x28
#define HID_ESC       0x29
#define HID_BSPACE    0x2A
#define HID_TAB       0x2B
#define HID_SPACE     0x2C
#define HID_HOME      0x4A
#define HID_PGUP      0x4B
#define HID_PGDN      0x4E
#define HID_RIGHT     0x4F
#define HID_LEFT      0x50
#define HID_END       0x4D
#define HID_DOWN      0x51
#define HID_UP        0x52
#define HID_F(n)      (0x3A + (n) - 1)  /* F1..F12 = 0x3A..0x45 */
#define HID_LCTRL     0xE0
#define HID_LSHIFT    0xE1
#define HID_RSHIFT    0xE5

/* Numeric keypad (note: on some hosts these depend on NumLock being on). */
#define HID_KP(n)     ((n) ? 0x59 + (n) - 1 : 0x62)  /* KP 1..9, KP 0 */
#define HID_KP_0      HID_KP(0)
#define HID_KP_2      HID_KP(2)
#define HID_KP_4      HID_KP(4)
#define HID_KP_6      HID_KP(6)
#define HID_KP_8      HID_KP(8)
#define HID_KP_DOT    0x63
/* Keypad symbols. VICE's built-in Numpad joystick device claims only KP 0-9
 * (digits = 8 directions + fire), so these never collide with it. */
#define HID_KP_SLASH  0x54
#define HID_KP_STAR   0x55
#define HID_KP_MINUS  0x56
#define HID_KP_PLUS   0x57
#define HID_KP_ENTER  0x58

/* keyID (col*8+row) -> HID usage. 128 entries. The C128-only keyIDs
 * (64..89) stay unmapped here: they are mapped in keymap128 below, and only
 * the cartridge's C128 bank sends them. */
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

    /* --- Joysticks (later designators override the HID_NONE range above) ---
     * The cartridge reports joystick contacts as ordinary key events, so the
     * host sees plain keystrokes. Point VICE at them with
     * Settings -> Joystick -> Keyset A / Keyset B.
     *
     * Both ports use usages that NO matrix key above can produce. That matters
     * for port 1: a held direction grounds a row line and phantom-presses all
     * 8 keys in that row, so mapping it to letters (W/S/A/D) made the stick
     * indistinguishable from its own crosstalk - pressing left produced
     * A, D, G, J, L, which is exactly row 2 of the matrix. F8..F12 and the
     * keypad never appear in the keyboard table, so they are unambiguous.
     */
    [JOY2_UP]    = HID_KP_8,
    [JOY2_DOWN]  = HID_KP_2,
    [JOY2_LEFT]  = HID_KP_4,
    [JOY2_RIGHT] = HID_KP_6,
    [JOY2_FIRE]  = HID_KP_0,

    [JOY1_UP]    = HID_KP_MINUS,   /* KP -     */
    [JOY1_DOWN]  = HID_KP_PLUS,    /* KP +     */
    [JOY1_LEFT]  = HID_KP_SLASH,   /* KP /     */
    [JOY1_RIGHT] = HID_KP_STAR,    /* KP *     */
    [JOY1_FIRE]  = HID_KP_ENTER,   /* KP enter */

    [KEY_RESTORE] = HID_PGUP,      /* VICE positional: Page_Up -> RESTORE */
};

/* ---------------------------------------------------------------------------
 *  C128 mode (the cartridge's C128 bank announces itself with SYNC128)
 *
 *  Overrides of keymap[] that apply only in C128 mode: the inverse of VICE's
 *  stock x128 positional keymap (share/vice/C128/gtk3_pos.vkm). Everything
 *  not listed here maps exactly as in keymap[] above.
 *
 *  Two C128 keys need more than a table entry; main.c handles them:
 *    - CRSR L/R and CRSR U/D: x128 has no host key for these in native mode;
 *      the host arrows drive the separate cursor pad instead, and SHIFT on the
 *      pad does not reverse direction (KERNAL tables at $FA80). So they are
 *      sent as host Right / Down, or Left / Up while a SHIFT is held.
 *    - CAPS LOCK and 40/80 DISPLAY latch mechanically, while x128 toggles them
 *      on each host key press. So each change of the latch is sent as a tap.
 * ------------------------------------------------------------------------- */
static const uint8_t keymap128[][2] PROGMEM = {
    /* x128 moves the top-row function keys to host F1-F4 */
    {  4, HID_F(1) },     /* F1 */
    {  5, HID_F(2) },     /* F3 */
    {  6, HID_F(3) },     /* F5 */
    {  3, HID_F(4) },     /* F7 */
    /* K0 */
    { 64, HID_F(5) },     /* HELP */
    { 65, HID_KP(8) },
    { 66, HID_KP(5) },
    { 67, HID_F(10) },    /* TAB */
    { 68, HID_KP(2) },
    { 69, HID_KP(4) },
    { 70, HID_KP(7) },
    { 71, HID_KP(1) },
    /* K1 */
    { 72, HID_F(9) },     /* ESC */
    { 73, HID_KP_MINUS }, /* KP + : the key in the host KP - position */
    { 74, HID_KP_PLUS },  /* KP - : the key in the host KP + position */
    { 75, HID_F(6) },     /* LINE FEED */
    { 76, HID_KP_ENTER },
    { 77, HID_KP(6) },
    { 78, HID_KP(9) },
    { 79, HID_KP(3) },
    /* K2 */
    { 80, HID_F(11) },    /* ALT */
    { 81, HID_KP(0) },
    { 82, HID_KP_DOT },
    { 83, HID_UP },       /* cursor pad */
    { 84, HID_DOWN },
    { 85, HID_LEFT },
    { 86, HID_RIGHT },
    { 87, HID_F(8) },     /* NO SCROLL */
    /* latches outside the matrix, sent as taps */
    { KEY_CAPS, HID_F(12) },   /* x128: "F12 -4 1" CAPS (ASCII/DIN) */
    { KEY_4080, HID_F(7) },    /* x128: "F7 -4 0"  40/80 DISPLAY */
};

/* Note: in C128 mode the keypad and the joystick ports share host keys
 * (port 2 = keypad digits, port 1 = KP - + / * ENTER), as they must: x128
 * uses the whole keypad for the C128 keypad. Enable VICE's Numpad joystick or
 * a keypad keyset only when not typing on the C128 keypad. */

/* Why port 1 is on keypad symbols rather than function keys:
 * F12 never reached VICE as a key (verified on hardware 2026-07-19, F8-F11
 * fine). The cause: VICE's positional keymap binds F12 to RESTORE
 * (gtk3_pos.vkm: "F12 -3 0"), so VICE consumes it as the RESTORE line rather
 * than as a joystick keyset key.
 *
 * Keypad DIGITS are not an option: VICE's Numpad joystick device (the port-2
 * setting) claims KP 7/9/1/3 for diagonals and KP 0/5 for fire, so digits
 * would cross-trigger between the two ports. The symbols are untouched by it.
 * They also sit sensibly on the keypad: / left of *, and - above +. */

#endif /* KEY2USB_KEYMAP_H */
