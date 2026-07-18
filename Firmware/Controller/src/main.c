/* =============================================================================
 *  KEY2USB - ATmega328/328P controller firmware
 * =============================================================================
 *  Reads C64/C128 key events from the 74LS273 latch (raised by the RDY flag),
 *  translates keyID -> USB HID usage, and reports them as a USB HID boot
 *  keyboard using V-USB (low-speed USB 1.1, software stack).
 *
 *  The two firmware halves share only the event byte; see src/protocol.h.
 */

#include <avr/io.h>
#include <avr/interrupt.h>
#include <avr/pgmspace.h>
#include <avr/wdt.h>
#include <util/delay.h>

#include "usbdrv.h"
#include "protocol.h"
#include "keymap.h"

/* --------------------------------------------------------------------------
 *  HID report descriptor: standard 8-byte boot keyboard
 *  [modifiers][reserved][keycode x6]
 * -------------------------------------------------------------------------- */
PROGMEM const char usbHidReportDescriptor[USB_CFG_HID_REPORT_DESCRIPTOR_LENGTH] = {
    0x05, 0x01,        /* Usage Page (Generic Desktop)          */
    0x09, 0x06,        /* Usage (Keyboard)                      */
    0xA1, 0x01,        /* Collection (Application)              */
    0x05, 0x07,        /*   Usage Page (Keyboard/Keypad)        */
    0x19, 0xE0,        /*   Usage Minimum (LeftControl)         */
    0x29, 0xE7,        /*   Usage Maximum (RightGUI)            */
    0x15, 0x00,        /*   Logical Minimum (0)                 */
    0x25, 0x01,        /*   Logical Maximum (1)                 */
    0x75, 0x01,        /*   Report Size (1)                     */
    0x95, 0x08,        /*   Report Count (8)                    */
    0x81, 0x02,        /*   Input (Data,Var,Abs) - modifier byte*/
    0x95, 0x01,        /*   Report Count (1)                    */
    0x75, 0x08,        /*   Report Size (8)                     */
    0x81, 0x01,        /*   Input (Const) - reserved byte       */
    0x95, 0x06,        /*   Report Count (6)                    */
    0x75, 0x08,        /*   Report Size (8)                     */
    0x15, 0x00,        /*   Logical Minimum (0)                 */
    0x25, 0x65,        /*   Logical Maximum (101)               */
    0x05, 0x07,        /*   Usage Page (Keyboard/Keypad)        */
    0x19, 0x00,        /*   Usage Minimum (0)                   */
    0x29, 0x65,        /*   Usage Maximum (101)                 */
    0x81, 0x00,        /*   Input (Data,Array) - 6 key slots    */
    0xC0               /* End Collection                        */
};

/* --------------------------------------------------------------------------
 *  Key state and report
 * -------------------------------------------------------------------------- */
static uint8_t reportBuffer[8];    /* what we transmit                        */
static uint8_t modifiers;          /* current modifier bitmap                 */
static uint8_t keys[6];            /* currently-held non-modifier HID usages  */
static uint8_t reportDirty;        /* set when the report needs (re)sending   */

static uint8_t idleRate;           /* HID idle rate, in 4 ms units (0 = off)  */

static void keyDown(uint8_t usage)
{
    uint8_t i;
    if (usage >= 0xE0 && usage <= 0xE7) {         /* modifier */
        modifiers |= (uint8_t)(1 << (usage - 0xE0));
        return;
    }
    for (i = 0; i < 6; i++)                        /* already held? */
        if (keys[i] == usage) return;
    for (i = 0; i < 6; i++)                        /* find a free slot */
        if (keys[i] == 0) { keys[i] = usage; return; }
    /* all slots full: drop (n-key rollover limit) */
}

static void keyUp(uint8_t usage)
{
    uint8_t i;
    if (usage >= 0xE0 && usage <= 0xE7) {
        modifiers &= (uint8_t)~(1 << (usage - 0xE0));
        return;
    }
    for (i = 0; i < 6; i++)
        if (keys[i] == usage) { keys[i] = 0; return; }
}

static void buildReport(void)
{
    uint8_t i;
    reportBuffer[0] = modifiers;
    reportBuffer[1] = 0;
    for (i = 0; i < 6; i++)
        reportBuffer[2 + i] = keys[i];
}

/* --------------------------------------------------------------------------
 *  1 ms tick (Timer0 CTC) - drives the HID idle timer only
 * -------------------------------------------------------------------------- */
static volatile uint8_t msTick;    /* free-running millisecond counter        */

ISR(TIMER0_COMPA_vect)
{
    msTick++;
}

static void timer0Init(void)
{
    /* CTC, prescaler 64: 16 MHz / 64 / 250 = 1000 Hz */
    TCCR0A = (1 << WGM01);
    TCCR0B = (1 << CS01) | (1 << CS00);
    OCR0A  = 249;
    TIMSK0 = (1 << OCIE0A);
}

/* --------------------------------------------------------------------------
 *  V-USB control-transfer handler (HID class requests)
 * -------------------------------------------------------------------------- */
usbMsgLen_t usbFunctionSetup(uchar data[8])
{
    usbRequest_t *rq = (usbRequest_t *)data;

    if ((rq->bmRequestType & USBRQ_TYPE_MASK) == USBRQ_TYPE_CLASS) {
        switch (rq->bRequest) {
        case USBRQ_HID_GET_REPORT:            /* host wants the current state */
            buildReport();
            usbMsgPtr = (usbMsgPtr_t)reportBuffer;
            return sizeof(reportBuffer);
        case USBRQ_HID_GET_IDLE:
            usbMsgPtr = (usbMsgPtr_t)&idleRate;
            return 1;
        case USBRQ_HID_SET_IDLE:
            idleRate = rq->wValue.bytes[1];
            return 0;
        default:
            break;
        }
    }
    return 0;   /* ignore unknown requests */
}

/* --------------------------------------------------------------------------
 *  Port setup
 * -------------------------------------------------------------------------- */
static void ioInit(void)
{
    /* PC0..PC5 = latch KB0..KB5 (inputs, no pull-ups: 74LS273 drives them) */
    DDRC  &= (uint8_t)~0x3F;
    PORTC &= (uint8_t)~0x3F;
    /* PB0..PB1 = latch KB6..KB7 (inputs) */
    DDRB  &= (uint8_t)~0x03;
    PORTB &= (uint8_t)~0x03;
    /* PD4 = RDY (input, driven by 74LS74) */
    DDRD  &= (uint8_t)~(1 << RDY_PIN);
    PORTD &= (uint8_t)~(1 << RDY_PIN);
    /* PD5 = /CLRRDY (output, idle high) */
    DDRD  |= (1 << CLRRDY_PIN);
    PORTD |= (1 << CLRRDY_PIN);
}

int main(void)
{
    uint8_t lastIdle = 0;

    /* Guard against a watchdog reset loop: clear the flag and disable the WDT
     * before it can expire at its post-reset (16 ms) timeout. */
    MCUSR = 0;
    wdt_disable();

    ioInit();
    key2usb_clear_ready();          /* start with a clean latch flag */

    wdt_enable(WDTO_1S);

    /* Force a USB re-enumeration so the host always sees a fresh connect,
     * even though the 1.5k pull-up is hard-wired to +5V. V-USB drives the
     * data lines low during the "disconnect" window. */
    usbInit();
    usbDeviceDisconnect();
    for (uint8_t i = 0; i < 250; i++) {
        wdt_reset();
        _delay_ms(1);
    }
    usbDeviceConnect();

    timer0Init();
    sei();

    for (;;) {
        wdt_reset();
        usbPoll();

        /* Drain one key event per iteration (the 6502 paces its writes). */
        if (key2usb_event_ready()) {
            uint8_t ev    = key2usb_read_latch();
            key2usb_clear_ready();
            uint8_t usage = pgm_read_byte(&keymap[EV_KEYID(ev)]);
            if (usage != HID_NONE) {
                if (ev & EV_PRESSED) keyDown(usage);
                else                 keyUp(usage);
                reportDirty = 1;
            }
        }

        /* HID idle: resend the current report every idleRate*4 ms. */
        if (idleRate != 0) {
            uint8_t now = msTick;
            if ((uint8_t)(now - lastIdle) >= (uint8_t)(idleRate << 2)) {
                lastIdle = now;
                reportDirty = 1;
            }
        }

        if (reportDirty && usbInterruptIsReady()) {
            buildReport();
            usbSetInterrupt(reportBuffer, sizeof(reportBuffer));
            reportDirty = 0;
        }
    }
}
