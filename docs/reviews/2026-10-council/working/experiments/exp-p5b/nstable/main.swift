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
    var leftover = 0
    while let e = app.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.001), inMode: .default, dequeue: true) { leftover += 1; app.sendEvent(e) }
    if leftover > 0 { leftoverCount += 1 }
}
var leftoverCount = 0

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

let home = String(Character(UnicodeScalar(NSHomeFunctionKey)!))
let end = String(Character(UnicodeScalar(NSEndFunctionKey)!))
let pgdn = String(Character(UnicodeScalar(NSPageDownFunctionKey)!))
let rows = Array(0..<10)

enum Op: CustomStringConvertible {
    case click(Int), cmd(Int), shift(Int), shiftCmd(Int), down, up, shDown, shUp, all, home, end
    var description: String {
        switch self {
        case let .click(r): "click(\(r))"; case let .cmd(r): "⌘click(\(r))"; case let .shift(r): "⇧click(\(r))"
        case let .shiftCmd(r): "⇧⌘click(\(r))"
        case .down: "↓"; case .up: "↑"; case .shDown: "⇧↓"; case .shUp: "⇧↑"; case .all: "⌘A"; case .home: "Home"; case .end: "End"
        }
    }
}

func applyAppKit(_ op: Op) {
    switch op {
    case let .click(r): click(r)
    case let .cmd(r): click(r, .command)
    case let .shift(r): click(r, .shift)
    case let .shiftCmd(r): click(r, [.shift, .command])
    case .down: key(125, down, [.numericPad, .function])
    case .up: key(126, upA, [.numericPad, .function])
    case .shDown: shDown()
    case .shUp: shUp()
    case .all: table.selectAll(nil)
    case .home: key(115, home, [.function])
    case .end: key(119, end, [.function])
    }
}
func applyKit(_ op: Op, _ s: inout ListSelection<Int>) {
    switch op {
    case let .click(r): s.click(r, extend: false, toggle: false, in: rows)
    case let .cmd(r): s.click(r, extend: false, toggle: true, in: rows)
    case let .shift(r): s.click(r, extend: true, toggle: false, in: rows)
    case let .shiftCmd(r): s.click(r, extend: true, toggle: true, in: rows)
    case .down: s.move(.step(1), extend: false, in: rows)
    case .up: s.move(.step(-1), extend: false, in: rows)
    case .shDown: s.move(.step(1), extend: true, in: rows)
    case .shUp: s.move(.step(-1), extend: true, in: rows)
    case .all: s.selectAll(in: rows)
    case .home: s.move(.first, extend: false, in: rows)
    case .end: s.move(.last, extend: false, in: rows)
    }
}

var rng = SystemRandomNumberGenerator()
struct LCG: RandomNumberGenerator { var s: UInt64; mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s } }
var g = LCG(s: 42)
func randomOp(_ allowed: [Int]) -> Op {
    let r = Int.random(in: 0..<10, using: &g)
    switch allowed[Int.random(in: 0..<allowed.count, using: &g)] {
    case 0: return .click(r); case 1: return .cmd(r); case 2: return .shift(r); case 3: return .shiftCmd(r)
    case 4: return .down; case 5: return .up; case 6: return .shDown; case 7: return .shUp; case 8: return .all
    case 9: return .home; default: return .end
    }
}

func campaign(_ name: String, allowed: [Int], trials: Int, len: Int) {
    var firstDiv: [String: Int] = [:]
    var examples: [String: String] = [:]
    var diverged = 0
    for _ in 0..<trials {
        table.deselectAll(nil); click(0); table.deselectAll(nil)   // NSTableView: fresh-ish state
        // a fresh table resets its anchor only by clicking: start both with a plain click on a random row
        let start = Int.random(in: 0..<10, using: &g)
        click(start)
        var s = ListSelection<Int>(); s.click(start, extend: false, toggle: false, in: rows)
        var trace: [String] = ["click(\(start))"]
        for _ in 0..<len {
            var op = randomOp(allowed)
            // harness artifact guard: AppKit defers a click on an already-selected row to a real
            // mouse-up (drag detection) that a synthesized event can't reproduce → never click a selected row
            // (except ⌘-click, which toggles at once).
            var guardTries = 0
            while guardTries < 20 {
                switch op {
                case let .click(r), let .shift(r), let .shiftCmd(r):
                    if table.selectedRowIndexes.contains(r) { op = randomOp(allowed); guardTries += 1; continue }
                default: break
                }
                break
            }
            let preKit = s
            applyAppKit(op); applyKit(op, &s)
            var edge = false
            switch op { case .down, .up, .shDown, .shUp:
                var probe = preKit
                switch op { case .down: edge = probe.move(.step(1), extend: false, in: rows) == nil
                case .up: edge = probe.move(.step(-1), extend: false, in: rows) == nil
                case .shDown: edge = probe.move(.step(1), extend: true, in: rows) == nil
                default: edge = probe.move(.step(-1), extend: true, in: rows) == nil }
            default: break }
            trace.append(op.description)
            let ak = Set(table.selectedRowIndexes.map { $0 })
            if ak != s.ids {
                diverged += 1
                let key = (edge ? "edge:" : "") + String(describing: op).components(separatedBy: "(").first!
                firstDiv[key, default: 0] += 1
                if examples[key] == nil {
                    examples[key] = trace.joined(separator: " ") + "  → AppKit \(ak.sorted()) vs kit \(s.ids.sorted())"
                }
                break
            }
        }
    }
    print("== \(name): \(diverged)/\(trials) sequences diverge; first divergent op: \(firstDiv)")
    for (k, v) in examples.sorted(by: { $0.key < $1.key }) { print("   [\(k)] \(v)") }
}

print("probe:"); table.deselectAll(nil); click(1); click(3, .shift); click(2); print("  click on selected row in multi-sel ->", sel(), "leftover", leftoverCount)
campaign("plain click + arrows + ⇧arrows", allowed: [0, 4, 5, 6, 7], trials: 300, len: 12)
campaign("+ ⇧click", allowed: [0, 2, 4, 5, 6, 7], trials: 300, len: 12)
campaign("+ ⌘click", allowed: [0, 1, 2, 4, 5, 6, 7], trials: 300, len: 12)
campaign("+ ⌘A", allowed: [0, 2, 4, 5, 6, 7, 8], trials: 300, len: 12)
campaign("Home/End", allowed: [0, 9, 10], trials: 100, len: 6)
campaign("⇧⌘click", allowed: [0, 3], trials: 100, len: 6)
