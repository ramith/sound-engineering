import CoreGraphics
import Foundation
// usage: kh <keycode> <seconds>  — hold a key down for N seconds (explicit empty flags); `kh down <k>` / `kh up <k>` for manual control
let a = CommandLine.arguments; let src = CGEventSource(stateID: .hidSystemState)
func key(_ k: CGKeyCode, _ down: Bool) { let e = CGEvent(keyboardEventSource: src, virtualKey: k, keyDown: down); e?.flags = []; e?.post(tap: .cghidEventTap) }
if a.count == 3, a[1] == "down", let k = UInt16(a[2]) { key(k, true); exit(0) }
if a.count == 3, a[1] == "up", let k = UInt16(a[2]) { key(k, false); exit(0) }
guard a.count >= 3, let k = UInt16(a[1]), let s = Double(a[2]) else { exit(64) }
key(k, true); usleep(UInt32(s * 1_000_000)); key(k, false)
