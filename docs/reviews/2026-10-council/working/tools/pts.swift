import ApplicationServices
import Foundation
// usage: pts <pid> [group-description]  — "label=valueDescription" for each child of the group (default "Equalizer graph")
let a = CommandLine.arguments
guard a.count >= 2, let pid = Int32(a[1]) else { exit(64) }
let needle = a.count > 2 ? a[2] : "Equalizer graph"
func attr(_ e: AXUIElement, _ n: String) -> CFTypeRef? { var v: CFTypeRef?; AXUIElementCopyAttributeValue(e, n as CFString, &v); return v }
func find(_ e: AXUIElement, _ depth: Int) -> AXUIElement? {
    if let d = attr(e, kAXDescriptionAttribute) as? String, d.hasPrefix(needle) { return e }
    if depth > 14 { return nil }
    if let kids = attr(e, kAXChildrenAttribute) as? [AXUIElement] { for k in kids { if let f = find(k, depth + 1) { return f } } }
    return nil
}
let app = AXUIElementCreateApplication(pid)
for w in (attr(app, kAXWindowsAttribute) as? [AXUIElement] ?? []) {
    if let g = find(w, 0) {
        if let v = attr(g, kAXValueAttribute) { print("GROUP value=\(v)") }
        if let v = attr(g, "AXValueDescription") { print("GROUP valueDescription=\(v)") }
        var out: [String] = []
        for k in (attr(g, kAXChildrenAttribute) as? [AXUIElement] ?? []) {
            let d = (attr(k, kAXDescriptionAttribute) as? String) ?? "?"
            let v = (attr(k, "AXValueDescription") as? String) ?? ((attr(k, kAXValueAttribute) as? String) ?? "-")
            out.append("\(d)=\(v)")
        }
        print(out.joined(separator: " | "))
        exit(0)
    }
}
print("NOT FOUND")
