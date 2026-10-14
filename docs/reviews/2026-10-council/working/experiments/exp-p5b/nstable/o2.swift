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
    win.sendEvent(down)
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

print("row at 1:", table.rect(ofRow: 1), table.isFlipped)
reset(); print("after reset:", sel())
click(1); print("click1:", sel())
click(4); print("click4:", sel())
click(4, .command); print("cmd4:", sel())
click(7, .shift); print("sh7:", sel())
