// =============================================================================
//  key2usbmon - watch a KEY2USB cartridge's USB HID reports directly (macOS)
// =============================================================================
//  Reads the raw 8-byte boot-keyboard reports from the cartridge through IOKit
//  and decodes them back to the C64 keys that produced them. No emulator is
//  involved, so it answers "is the hardware link right?" on its own.
//
//  It tries to SEIZE the device so that macOS itself does not act on the
//  cartridge's keystrokes (no stray Shift-clicks or Escapes) while it runs.
//  macOS only lets root seize a keyboard, so run it with sudo for that;
//  without sudo it still monitors, and macOS sees the keystrokes too.
//
//  usage: [sudo] key2usbmon [--check] [--joy] [--c128] [--all] [--no-seize]
//
//      (no options)  monitor: one line per change, plus stuck-key warnings
//      --all         also print the identical reports a host's HID idle rate
//                    asks for (macOS: every 24 ms)
//      --check       checklist: press and release every C64 key (and RESTORE)
//                    until all are ticked off - a quick per-unit QA pass
//      --joy         with --check, also require all ten joystick contacts
//      --c128        name keys as the cartridge's C128 bank sends them (mode
//                    jumper = C128): x128 host keys, plus the keypad, ESC, TAB,
//                    ALT, HELP, LINE FEED, NO SCROLL, cursor pad, CAPS LOCK and
//                    40/80 DISPLAY. With --check: 89 keys.
//      --no-seize    do not try to seize; macOS sees the keystrokes as well
//
//  Needs Input Monitoring permission for the terminal app that runs it
//  (System Settings -> Privacy & Security -> Input Monitoring).
//
//  Build: make key2usbmon   (swiftc, from the Xcode Command Line Tools)

import Foundation
import IOKit
import IOKit.hid

let vendorID = 0x16C0               // obdev shared VID
let productID = 0x27DB              // obdev shared "USB keyboard" PID
let productName = "KEY2USB"         // the shared PID is told apart by name
let stuckSeconds = 10.0

// ---- HID usage -> C64 key label (inverse of Controller/src/keymap.h) ---------
// Keep in sync with keymap.h; an unknown usage is shown as "HID 0xNN".
let matrixKeys: [(UInt8, String)] = [
    (0x2A, "INST/DEL"), (0x28, "RETURN"), (0x4F, "CRSR L/R"), (0x40, "F7"),
    (0x3A, "F1"), (0x3C, "F3"), (0x3E, "F5"), (0x51, "CRSR U/D"),
    (0x20, "3"), (0x1A, "W"), (0x04, "A"), (0x21, "4"),
    (0x1D, "Z"), (0x16, "S"), (0x08, "E"),
    (0x22, "5"), (0x15, "R"), (0x07, "D"), (0x23, "6"),
    (0x06, "C"), (0x09, "F"), (0x17, "T"), (0x1B, "X"),
    (0x24, "7"), (0x1C, "Y"), (0x0A, "G"), (0x25, "8"),
    (0x05, "B"), (0x0B, "H"), (0x18, "U"), (0x19, "V"),
    (0x26, "9"), (0x0C, "I"), (0x0D, "J"), (0x27, "0"),
    (0x10, "M"), (0x0E, "K"), (0x12, "O"), (0x11, "N"),
    (0x2D, "+"), (0x13, "P"), (0x0F, "L"), (0x2E, "-"),
    (0x37, "."), (0x33, ":"), (0x2F, "@"), (0x36, ","),
    (0x4D, "£"), (0x30, "*"), (0x34, ";"), (0x4A, "CLR/HOME"),
    (0x4E, "="), (0x31, "↑"), (0x38, "/"),
    (0x1E, "1"), (0x35, "←"), (0x2B, "CTRL"), (0x1F, "2"),
    (0x2C, "SPACE"), (0x14, "Q"), (0x29, "RUN/STOP"),
    (0x4B, "RESTORE"),
]
let joystickKeys: [(UInt8, String)] = [
    (0x60, "JOY2 UP"), (0x5A, "JOY2 DOWN"), (0x5C, "JOY2 LEFT"),
    (0x5E, "JOY2 RIGHT"), (0x62, "JOY2 FIRE"),
    (0x56, "JOY1 UP"), (0x57, "JOY1 DOWN"), (0x54, "JOY1 LEFT"),
    (0x55, "JOY1 RIGHT"), (0x58, "JOY1 FIRE"),
]
// Modifier byte bits the cartridge uses (C= -> Left Ctrl, the two SHIFTs).
let modifierKeys: [(UInt8, String)] = [
    (0, "C="), (1, "LEFT SHIFT"), (5, "RIGHT SHIFT"),
]
// --c128: the cartridge's C128 bank (jumper = C128) makes the controller use
// x128's host keys instead (keymap128 in keymap.h). These override the names
// above. In native mode x128 has no host key for the main CRSR keys, so they
// share Right/Down with the cursor pad and cannot be told apart here.
let c128Mode = CommandLine.arguments.contains("--c128")
let c128Keys: [(UInt8, String)] = [
    (0x3A, "F1"), (0x3B, "F3"), (0x3C, "F5"), (0x3D, "F7"),
    (0x3E, "HELP"), (0x3F, "LINE FEED"), (0x40, "40/80"), (0x41, "NO SCROLL"),
    (0x42, "ESC"), (0x43, "TAB"), (0x44, "ALT"), (0x45, "CAPS LOCK"),
    (0x4F, "CRSR L/R|PAD →"), (0x51, "CRSR U/D|PAD ↓"), (0x50, "PAD ←"), (0x52, "PAD ↑"),
    (0x59, "KP 1"), (0x5A, "KP 2"), (0x5B, "KP 3"), (0x5C, "KP 4"), (0x5D, "KP 5"),
    (0x5E, "KP 6"), (0x5F, "KP 7"), (0x60, "KP 8"), (0x61, "KP 9"), (0x62, "KP 0"),
    (0x63, "KP ."), (0x56, "KP +"), (0x57, "KP -"), (0x58, "KP ENTER"),
]
let usageNames: [UInt8: String] = c128Mode
    ? Dictionary(matrixKeys + c128Keys, uniquingKeysWith: { _, c128 in c128 })
    : Dictionary(uniqueKeysWithValues: matrixKeys + joystickKeys)

func labels(of report: [UInt8]) -> Set<String> {
    var held = Set<String>()
    for bit in 0..<8 where report[0] & (1 << bit) != 0 {
        held.insert(modifierKeys.first { $0.0 == bit }?.1 ?? "MOD bit\(bit)")
    }
    for usage in report[2..<8] where usage != 0 {
        held.insert(usageNames[usage] ?? String(format: "HID 0x%02X", usage))
    }
    return held
}

// ---- options -------------------------------------------------------------------
let args = Set(CommandLine.arguments.dropFirst())
let known: Set<String> = ["--check", "--joy", "--c128", "--all", "--no-seize", "-h", "--help"]
if !args.isSubset(of: known) || args.contains("-h") || args.contains("--help") {
    print("usage: [sudo] key2usbmon [--check] [--joy] [--c128] [--all] [--no-seize]")
    exit(args.isSubset(of: known) ? 0 : 2)
}
let checkMode = args.contains("--check")
let showAll = args.contains("--all")
let seize = !args.contains("--no-seize")
var checklist: [String] = []
for (usage, _) in matrixKeys + (c128Mode ? c128Keys : []) {
    if let name = usageNames[usage], !checklist.contains(name) { checklist.append(name) }
}
checklist += modifierKeys.map { $0.1 }
if args.contains("--joy") {
    if c128Mode {
        print("note: --joy is ignored with --c128 - the sticks share the keypad's host keys there")
    } else {
        checklist += joystickKeys.map { $0.1 }
    }
}

setvbuf(stdout, nil, _IOLBF, 0)

// ---- monitor state ---------------------------------------------------------------
final class Monitor {
    var previous = [UInt8](repeating: 0, count: 8)
    var start = Date()
    var lastReport: Date?
    var lastPrinted: Date?
    var reports = 0
    var repeats = 0
    var idleGaps: [Double] = []          // ms between identical reports
    var idleReported = false
    var mostAtOnce = 0
    var heldSince: [String: Date] = [:]
    var stuckWarned = Set<String>()
    var pressed = Set<String>()          // --check: seen going down
    var passed = Set<String>()           // --check: seen down AND back up
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

    func report(_ bytes: [UInt8]) {
        let now = Date()
        var r = bytes + [UInt8](repeating: 0, count: max(0, 8 - bytes.count))
        r = Array(r.prefix(8))
        reports += 1
        let isRepeat = r == previous
        if isRepeat, let last = lastReport {
            repeats += 1
            idleGaps.append(now.timeIntervalSince(last) * 1000)
            if !idleReported && idleGaps.count == 20 && !checkMode {
                idleReported = true
                let sorted = idleGaps.sorted()
                print(String(format: "  (host HID idle rate: the state is re-sent every ~%.0f ms; "
                             + "identical reports are hidden, --all shows them)", sorted[sorted.count / 2]))
            }
        }
        lastReport = now

        let before = labels(of: previous), after = labels(of: r)
        let down = after.subtracting(before).sorted(), up = before.subtracting(after).sorted()
        mostAtOnce = max(mostAtOnce, after.count)
        for k in down { heldSince[k] = now }
        for k in up { heldSince[k] = nil; stuckWarned.remove(k) }
        previous = r
        if isRepeat && !showAll { return }
        let gap = lastPrinted.map { String(format: "+%5.0f ms", now.timeIntervalSince($0) * 1000) } ?? "         "
        lastPrinted = now

        if checkMode {
            pressed.formUnion(down)
            let newlyPassed = Set(up).intersection(pressed).subtracting(passed)
            passed.formUnion(newlyPassed)
            for k in newlyPassed.intersection(checklist).sorted() {
                let left = checklist.filter { !passed.contains($0) }
                print("  ✓ \(k.padding(toLength: 15, withPad: " ", startingAt: 0)) \(checklist.count - left.count)/\(checklist.count)")
                if left.isEmpty {
                    print("\nALL \(checklist.count) KEYS PASS (each seen pressed and released)")
                    summary(); exit(0)
                }
            }
            for k in Set(down).subtracting(checklist) where !joystickKeys.contains(where: { $0.1 == k }) {
                print("  ? unexpected: \(k)")
            }
            return
        }

        let hex = r.map { String(format: "%02X", $0) }.joined(separator: " ")
        var change = (down.map { "+\($0)" } + up.map { "-\($0)" }).joined(separator: " ")
        if isRepeat { change = "(repeat)" }
        let held = after.isEmpty ? "" : "   held: " + after.sorted().joined(separator: ", ")
        print(String(format: "%8.3fs %@  %@   %@%@", now.timeIntervalSince(start),
                     gap, hex, change, held))
    }

    func checkStuck() {
        let now = Date()
        for (k, t) in heldSince where now.timeIntervalSince(t) >= stuckSeconds && !stuckWarned.contains(k) {
            stuckWarned.insert(k)
            let hint = k == "LEFT SHIFT" ? " (SHIFT LOCK engaged reads as LEFT SHIFT)" : ""
            print("  ! \(k) held for \(Int(stuckSeconds)) s - stuck?\(hint)")
        }
    }

    func remaining() {
        let left = checklist.filter { !passed.contains($0) }
        print("  remaining (\(left.count)): " + left.joined(separator: "  "))
    }

    func summary() {
        print(String(format: "\n%d reports in %.1f s (%d identical repeats), at most %d keys held at once",
                     reports, Date().timeIntervalSince(start), repeats, mostAtOnce))
        let held = labels(of: previous)
        if !held.isEmpty { print("still held at exit: " + held.sorted().joined(separator: ", ")) }
        if checkMode { remaining() }
    }
}
let monitor = Monitor()

// ---- permission ----------------------------------------------------------------------
if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
    IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    print("""
    key2usbmon needs Input Monitoring permission to read a keyboard.
    Allow your terminal app in System Settings -> Privacy & Security ->
    Input Monitoring, then quit and reopen the terminal and run this again.
    """)
    exit(1)
}

// ---- IOKit callbacks -------------------------------------------------------------------
let reportCallback: IOHIDReportCallback = { _, result, _, _, _, report, length in
    guard result == kIOReturnSuccess else { return }
    monitor.report(Array(UnsafeBufferPointer(start: report, count: length)))
}

let matchCallback: IOHIDDeviceCallback = { _, _, _, device in
    let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "?"
    guard name == productName else {
        print("ignoring \(name) (shares the obdev keyboard PID)")
        return
    }
    let maker = IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString) as? String ?? "?"
    let bcd = IOHIDDeviceGetProperty(device, kIOHIDVersionNumberKey as CFString) as? Int ?? 0
    let version = String(format: "%x.%02x", bcd >> 8, bcd & 0xFF)
    let firmware = bcd >= 0x0130 ? "v1.3+ controller firmware: SYNC, RESTORE, C128 mappings"
        : bcd >= 0x0120 ? "v1.2 controller firmware: SYNC + RESTORE"
        : "v1.1.x or earlier controller firmware"
    print("connected: \(maker) \(name), bcdDevice \(version) (\(firmware))")

    var seized = false
    var status = kIOReturnNotOpen
    if seize {
        status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        seized = status == kIOReturnSuccess
        if !seized {
            let why = status == kIOReturnNotPrivileged ? "macOS only lets root seize a keyboard; run with sudo"
                                                      : String(format: "0x%08x", UInt32(bitPattern: status))
            print("not seized (\(why)) - macOS also acts on the keystrokes")
        }
    }
    if !seized { status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
    guard status == kIOReturnSuccess else {
        print("could not open the device (0x\(String(UInt32(bitPattern: status), radix: 16)))")
        return
    }
    if seized { print("device seized: macOS ignores its keystrokes while key2usbmon runs") }
    monitor.previous = [UInt8](repeating: 0, count: 8)
    monitor.heldSince = [:]
    IOHIDDeviceRegisterInputReportCallback(device, monitor.buffer, 64, reportCallback, nil)
    if checkMode {
        print("\nPress and release every key below (SHIFT LOCK counts as LEFT SHIFT).")
        monitor.remaining()
        print("")
    } else {
        print("\n    time      gap      modifiers .. key slots         change")
    }
}

let removalCallback: IOHIDDeviceCallback = { _, _, _, device in
    let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "?"
    guard name == productName else { return }
    print("disconnected: \(name)")
    let held = labels(of: monitor.previous)
    if !held.isEmpty { print("  (was holding: \(held.sorted().joined(separator: ", ")))") }
}

// ---- run -------------------------------------------------------------------------------------
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: vendorID,
                                        kIOHIDProductIDKey: productID] as CFDictionary)
IOHIDManagerRegisterDeviceMatchingCallback(manager, matchCallback, nil)
IOHIDManagerRegisterDeviceRemovalCallback(manager, removalCallback, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

print("key2usbmon - waiting for \(productName) (USB \(String(format: "%04x:%04x", vendorID, productID)))... Ctrl-C to quit")

let stuckTimer = DispatchSource.makeTimerSource(queue: .main)
stuckTimer.schedule(deadline: .now() + 1, repeating: 1)
stuckTimer.setEventHandler { if !checkMode { monitor.checkStuck() } }
stuckTimer.resume()

signal(SIGINT, SIG_IGN)
let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigint.setEventHandler { monitor.summary(); exit(0) }
sigint.resume()

CFRunLoopRun()
