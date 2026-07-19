/* =============================================================================
 *  protocol.h - KEY2USB event-byte contract (ATmega side)
 * =============================================================================
 *  Mirror of the 6502 side (Firmware/Cart/Cart.inc). One byte is latched into
 *  the 74LS273 each time the 6502 writes to $DE00; the 74LS74 raises RDY.
 *
 *      bit 7      : 1 = key pressed (make), 0 = key released (break)
 *      bits 6..0  : keyID  (C64 matrix = col*8+row, 0..63; C128 ext = 64..;
 *                           joystick port 2 = 112..116, port 1 = 120..124)
 *
 *  Pin contract (verified against Hardware/KEY2USB.kicad_sch, U5):
 *      KB0..KB5 -> PC0..PC5      KB6..KB7 -> PB0..PB1
 *      RDY      -> PD4 (input)   /CLRRDY  -> PD5 (output, active low)
 *      USB D+   -> PD2/INT0      USB D-   -> PD3
 */
#ifndef KEY2USB_PROTOCOL_H
#define KEY2USB_PROTOCOL_H

#include <avr/io.h>

#define EV_PRESSED   0x80        /* bit 7 of the event byte */
#define EV_KEYID(b)  ((b) & 0x7F)

/* Joystick keyIDs (mirror of JOY2_BASE / JOY1_BASE in Cart/Cart.inc).
 * Contacts arrive as ordinary key events; the keymap decides what they type. */
#define JOY2_UP      112
#define JOY2_DOWN    113
#define JOY2_LEFT    114
#define JOY2_RIGHT   115
#define JOY2_FIRE    116
#define JOY1_UP      120
#define JOY1_DOWN    121
#define JOY1_LEFT    122
#define JOY1_RIGHT   123
#define JOY1_FIRE    124

#define RDY_PIN      PD4
#define CLRRDY_PIN   PD5

/* Reassemble the latched key byte from the two input ports. */
static inline uint8_t key2usb_read_latch(void)
{
    return (uint8_t)((PINC & 0x3F) | ((PINB & 0x03) << 6));
}

/* True while the 74LS74 says a fresh event is waiting in the latch. */
static inline uint8_t key2usb_event_ready(void)
{
    return (PIND & (1 << RDY_PIN)) != 0;
}

/* Pulse /CLRRDY low to clear the ready flag after consuming an event. */
static inline void key2usb_clear_ready(void)
{
    PORTD &= ~(1 << CLRRDY_PIN);
    /* 74LS74 async clear needs only nanoseconds; a couple of NOPs suffice. */
    __asm__ __volatile__("nop\n\tnop\n\tnop\n\tnop");
    PORTD |= (1 << CLRRDY_PIN);
}

#endif /* KEY2USB_PROTOCOL_H */
