import AppKit

final class DS: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { 10 }
    func tableView(_ t: NSTableView, objectValueFor c: NSTableColumn?, row: Int) -> Any? { "r\(row)" }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory); app.finishLaunching()
final class KW: NSWindow { override var isKeyWindow: Bool { true }; override var canBecomeKey: Bool { true }; override var isMainWindow: Bool { true } }
final class TV: NSTableView { override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true } }
let win = KW(contentRect: NSRect(x: -5000, y: -5000, width: 300, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
let table = TV(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
let col = NSTableColumn(identifier: .init("c")); col.width = 280
table.addTableColumn(col)
let ds = DS()
table.dataSource = ds; table.delegate = ds
table.allowsMultipleSelection = true
table.rowHeight = 20; table.intercellSpacing = NSSize(width: 0, height: 0)
table.headerView = nil
win.contentView = table
table.reloadData()
table.layoutSubtreeIfNeeded()
win.makeFirstResponder(table); win.orderFrontRegardless()

func sel() -> String { table.selectedRowIndexes.map { "\($0)" }.joined(separator: ",") }

func click(_ row: Int, _ flags: NSEvent.ModifierFlags = []) {
    let r = table.rect(ofRow: row)
    let p = table.convert(NSPoint(x: r.midX, y: r.midY), to: nil)
    let up = NSEvent.mouseEvent(with: .leftMouseUp, location: p, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
    app.postEvent(up, atStart: false)
    let down = NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    table.mouseDown(with: down)
}

func key(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags = []) {
    let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: win.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    table.keyDown(with: e)
}
let down = String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
let upA = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
func shDown() { key(125, down, [.shift, .numericPad, .function]) }
func shUp() { key(126, upA, [.shift, .numericPad, .function]) }
func plainDown() { key(125, down, [.numericPad, .function]) }

func reset() { table.deselectAll(nil); click(0); table.deselectAll(nil) }

print("T1 click 1, cmd-click 4, shift-click 7:")
reset(); click(1); click(4, .command); click(7, .shift); print("  ", sel())
print("T2 click 1, cmd-click 4, shift-click 2 (above new anchor):")
reset(); click(1); click(4, .command); click(2, .shift); print("  ", sel())
print("T3 click 2, shift-click 6, shift-click 4 (shrink):")
reset(); click(2); click(6, .shift); click(4, .shift); print("  ", sel())
print("T4 click 1, cmd-click 4, cmd-click 4 (deselect), shift-click 7:")
reset(); click(1); click(4, .command); click(4, .command); print("   after deselect:", sel()); click(7, .shift); print("  ", sel())
print("T5 click 3, shift-down x2, shift-up x4:")
reset(); click(3); shDown(); print("   ", sel()); shDown(); print("   ", sel()); shUp(); shUp(); print("   ", sel()); shUp(); shUp(); print("   ", sel())
print("T6 click 1, cmd-click 5, shift-down:")
reset(); click(1); click(5, .command); shDown(); print("  ", sel())
print("T7 click 1, cmd-click 5, plain down:")
reset(); click(1); click(5, .command); plainDown(); print("  ", sel())
print("T8 click 2, cmd-click 6, shift-click 8, shift-click 0:")
reset(); click(2); click(6, .command); click(8, .shift); print("   ", sel()); click(0, .shift); print("  ", sel())
print("T9 selectAll then shift-down (after click 3):")
reset(); click(3); table.selectAll(nil); shDown(); print("  ", sel())
print("T10 click 5, cmd-click 5 (deselect only), shift-click 8:")
reset(); click(5); click(5, .command); print("   after:", sel()); click(8, .shift); print("  ", sel())
print("T11 click 1, cmd-click 4, shift+cmd-click 7:")
reset(); click(1); click(4, .command); click(7, [.shift, .command]); print("  ", sel())
