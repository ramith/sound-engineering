import CoreGraphics
import Foundation
// usage: md <x1> <y1> <x2> <y2> [holdSeconds] [steps] [nokeyup]
//   a REAL drag: press at (x1,y1), move in steps to (x2,y2), hold, release.
//   x2,y2 == x1,y1 gives a press-and-hold. "nokeyup" leaves the button DOWN (pair with `md up x y`).
//   md up <x> <y>  — release the left button at a point.
let a = CommandLine.arguments
let src = CGEventSource(stateID: .hidSystemState)
func post(_ t: CGEventType, _ p: CGPoint) {
    let e = CGEvent(mouseEventSource: src, mouseType: t, mouseCursorPosition: p, mouseButton: .left)
    e?.flags = []   // explicit, never inherited
    e?.post(tap: .cghidEventTap)
}
if a.count >= 4, a[1] == "up", let x = Double(a[2]), let y = Double(a[3]) {
    post(.leftMouseUp, CGPoint(x: x, y: y)); exit(0)
}
guard a.count >= 5, let x1 = Double(a[1]), let y1 = Double(a[2]), let x2 = Double(a[3]), let y2 = Double(a[4]) else { exit(64) }
let hold = a.count > 5 ? (Double(a[5]) ?? 0.3) : 0.3
let steps = a.count > 6 ? (Int(a[6]) ?? 12) : 12
let leaveDown = a.contains("nokeyup")
let p1 = CGPoint(x: x1, y: y1)
post(.mouseMoved, p1); usleep(120_000)
post(.leftMouseDown, p1); usleep(120_000)
if x1 != x2 || y1 != y2 {
    for i in 1...steps {
        let f = Double(i) / Double(steps)
        post(.leftMouseDragged, CGPoint(x: x1 + (x2 - x1) * f, y: y1 + (y2 - y1) * f)); usleep(25_000)
    }
}
usleep(UInt32(hold * 1_000_000))
if !leaveDown { post(.leftMouseUp, CGPoint(x: x2, y: y2)) }
