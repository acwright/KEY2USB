/* =============================================================================
 *  usbconfig.h - V-USB configuration for KEY2USB (HID boot keyboard)
 * =============================================================================
 *  Based on V-USB's usbconfig-prototype.h (c) OBJECTIVE DEVELOPMENT GmbH.
 *  Hardware: ATmega328/328P @ 16 MHz, D+ on PD2/INT0, D- on PD3.
 */
#ifndef __usbconfig_h_included__
#define __usbconfig_h_included__

/* ---------------------------- Hardware Config ---------------------------- */
#define USB_CFG_IOPORTNAME      D
#define USB_CFG_DMINUS_BIT      3        /* PD3 */
#define USB_CFG_DPLUS_BIT       2        /* PD2 = INT0 (required) */
#define USB_CFG_CLOCK_KHZ       (F_CPU/1000)   /* 16000 */
#define USB_CFG_CHECK_CRC       0

/* --------------------------- Functional Range ---------------------------- */
#define USB_CFG_HAVE_INTRIN_ENDPOINT    1   /* interrupt-in endpoint 1 for HID */
#define USB_CFG_HAVE_INTRIN_ENDPOINT3   0
#define USB_CFG_EP3_NUMBER              3
#define USB_CFG_IMPLEMENT_HALT          0
#define USB_CFG_SUPPRESS_INTR_CODE      0
#define USB_CFG_INTR_POLL_INTERVAL      10  /* ms; >= 10 for low speed */
#define USB_CFG_IS_SELF_POWERED         1   /* powered from the C64, VBUS N/C */
#define USB_CFG_MAX_BUS_POWER           0   /* draws nothing from the USB bus */
#define USB_CFG_IMPLEMENT_FN_WRITE      0
#define USB_CFG_IMPLEMENT_FN_READ       0
#define USB_CFG_IMPLEMENT_FN_WRITEOUT   0
#define USB_CFG_HAVE_FLOWCONTROL        0
#define USB_CFG_DRIVER_FLASH_PAGE       0
#define USB_CFG_LONG_TRANSFERS          0
#define USB_COUNT_SOF                   0
#define USB_CFG_CHECK_DATA_TOGGLING     0
#define USB_CFG_HAVE_MEASURE_FRAME_LENGTH   0
#define USB_USE_FAST_CRC                0

/* -------------------------- Device Description --------------------------- */
/* obdev's free shared VID/PID for HID class devices. See USB-IDs-for-free.txt.
 * PID 0x27db is the shared "HID keyboard" product ID for VID 0x16c0. */
#define USB_CFG_VENDOR_ID       0xc0, 0x16      /* 0x16c0 */
#define USB_CFG_DEVICE_ID       0xdb, 0x27      /* 0x27db - shared HID keyboard */
#define USB_CFG_DEVICE_VERSION  0x01, 0x00      /* 0.01 */

#define USB_CFG_VENDOR_NAME     'a','c','w','r','i','g','h','t'
#define USB_CFG_VENDOR_NAME_LEN 8
#define USB_CFG_DEVICE_NAME     'K','E','Y','2','U','S','B'
#define USB_CFG_DEVICE_NAME_LEN 7
/* #define USB_CFG_SERIAL_NUMBER   'N','o','n','e' */
/* #define USB_CFG_SERIAL_NUMBER_LEN   0 */

#define USB_CFG_DEVICE_CLASS        0       /* deferred to interface */
#define USB_CFG_DEVICE_SUBCLASS     0
#define USB_CFG_INTERFACE_CLASS     0x03    /* HID */
#define USB_CFG_INTERFACE_SUBCLASS  0x01    /* Boot */
#define USB_CFG_INTERFACE_PROTOCOL  0x01    /* Keyboard */
/* 45-byte in-only boot keyboard report descriptor (no LED output collection;
 * the board has no indicator LEDs). Must match usbHidReportDescriptor[]. */
#define USB_CFG_HID_REPORT_DESCRIPTOR_LENGTH    45

/* ------------------- Fine Control over USB Descriptors ------------------- */
/* Let the driver build device/config/string descriptors; the HID report
 * descriptor is provided by us (usbHidReportDescriptor[] in main.c) and its
 * length is advertised via USB_CFG_HID_REPORT_DESCRIPTOR_LENGTH above. */
#define USB_CFG_DESCR_PROPS_DEVICE                  0
#define USB_CFG_DESCR_PROPS_CONFIGURATION           0
#define USB_CFG_DESCR_PROPS_STRINGS                 0
#define USB_CFG_DESCR_PROPS_STRING_0                0
#define USB_CFG_DESCR_PROPS_STRING_VENDOR           0
#define USB_CFG_DESCR_PROPS_STRING_PRODUCT          0
#define USB_CFG_DESCR_PROPS_STRING_SERIAL_NUMBER    0
#define USB_CFG_DESCR_PROPS_HID                     0
#define USB_CFG_DESCR_PROPS_HID_REPORT              0
#define USB_CFG_DESCR_PROPS_UNKNOWN                 0

/* ----------------------- Optional MCU Description ------------------------ */
/* Defaults in usbdrv.h are correct for INT0 on the ATmega328/328P. */

#endif /* __usbconfig_h_included__ */
