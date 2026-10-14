import ApplicationServices
import Foundation
// usage: axa <pid> <description-substring> [attr|all]  — print attributes of the first element whose AXDescription contains the text
let a = CommandLine.arguments
guard a.count >= 3, let pid = Int32(a[1]) else { exit(64) }
let needle = a[2]; let want = a.count > 3 ? a[3] : "all"
func attr(_ e: AXUIElement, _ n: String) -> CFTypeRef? { var v: CFTypeRef?; AXUIElementCopyAttributeValue(e, n as CFString, &v); return v }
func find(_ e: AXUIElement, _ depth: Int) -> AXUIElement? {
    if let d = attr(e, kAXDescriptionAttribute) as? String, d.contains(needle) { return e }
    if depth > 12 { return nil }
    if let kids = attr(e, kAXChildrenAttribute) as? [AXUIElement] { for k in kids { if let f = find(k, depth + 1) { return f } } }
    return nil
}
let app = AXUIElementCreateApplication(pid)
guard let wins = attr(app, kAXWindowsAttribute) as? [AXUIElement] else { print("no windows"); exit(1) }
for w in wins {
    if let e = find(w, 0) {
        if want == "press" { let r = AXUIElementPerformAction(e, kAXPressAction as CFString); print("AXPress → \(r.rawValue)"); exit(0) }
        var names: CFArray?; AXUIElementCopyAttributeNames(e, &names)
        for n in (names as? [String] ?? []) where want == "all" || n == want {
            if ["AXParent", "AXWindow", "AXTopLevelUIElement", "AXChildren", "AXFrame", "AXPosition", "AXSize"].contains(n) { continue }
            if let v = attr(e, n) { print("\(n) = \(v)") }
        }
        var acts: CFArray?; AXUIElementCopyActionNames(e, &acts); print("actions = \((acts as? [String] ?? []).joined(separator: ", "))")
        exit(0)
    }
}
print("NOT FOUND")
