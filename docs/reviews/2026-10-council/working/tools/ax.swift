import ApplicationServices
import Foundation
// usage: ax <pid> focus            — the focused element (role, desc, title, value, frame)
//        ax <pid> dump [depth]     — the front window's subtree
//        ax <pid> find <text>      — elements whose title/desc/value contains text (with frames)
let a = CommandLine.arguments; guard a.count >= 3, let pid = pid_t(a[1]) else { exit(64) }
let app = AXUIElementCreateApplication(pid)
func attr(_ e: AXUIElement, _ n: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(e, n as CFString, &v); return v }
func str(_ e: AXUIElement, _ n: String) -> String { if let s = attr(e, n) as? String { return s }; if let b = attr(e, n) as? Bool { return b ? "true" : "false" }; if let n2 = attr(e, n) as? NSNumber { return n2.stringValue }; return "" }
func frame(_ e: AXUIElement) -> String {
    var p = CGPoint.zero, s = CGSize.zero
    if let v = attr(e, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
    if let v = attr(e, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &s) }
    return "(\(Int(p.x)),\(Int(p.y)) \(Int(s.width))x\(Int(s.height)))"
}
func line(_ e: AXUIElement) -> String {
    var parts = [str(e, kAXRoleAttribute)]
    for (k, n) in [("d", kAXDescriptionAttribute), ("t", kAXTitleAttribute), ("v", kAXValueAttribute), ("id", "AXIdentifier")] {
        let s = str(e, n); if !s.isEmpty { parts.append("\(k)=\"\(s.prefix(70))\"") } }
    if str(e, kAXSelectedAttribute) == "true" { parts.append("SELECTED") }
    if str(e, kAXFocusedAttribute) == "true" { parts.append("FOCUSED") }
    return parts.joined(separator: " ") + " " + frame(e)
}
func kids(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
switch a[2] {
case "focus":
    if let f = attr(app, kAXFocusedUIElementAttribute) { print(line(f as! AXUIElement)) } else { print("no focus") }
case "dump", "find":
    guard let w = (attr(app, kAXWindowsAttribute) as? [AXUIElement])?.first else { print("no window"); exit(1) }
    let maxD = a[2] == "dump" ? (a.count > 3 ? Int(a[3]) ?? 8 : 8) : 40
    let needle = a[2] == "find" && a.count > 3 ? a[3].lowercased() : nil
    func walk(_ e: AXUIElement, _ d: Int) {
        let l = line(e)
        if let needle { if l.lowercased().contains(needle) { print(l) } } else { print(String(repeating: "  ", count: d) + l) }
        if d < maxD { for k in kids(e) { walk(k, d + 1) } }
    }
    walk(w, 0)
case "menus":
    // every open menu's items (context menus are app children, not window children)
    func walkM(_ e: AXUIElement, _ d: Int) {
        let r = str(e, kAXRoleAttribute)
        if r == "AXMenuItem" { let t = str(e, kAXTitleAttribute); if !t.isEmpty { print("\(t)  enabled=\(str(e, kAXEnabledAttribute)) mark=[\(str(e, kAXMenuItemMarkCharAttribute))] \(frame(e))") } }
        if d < 6 { for k in kids(e) where str(k, kAXRoleAttribute) != "AXMenuBar" { walkM(k, d + 1) } }
    }
    walkM(app, 0)
default: exit(64)
}
