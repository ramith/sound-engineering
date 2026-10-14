import Foundation
import LibraryScan
import Testing

// P5a panel — UNCOMMITTED model-based random test of FolderWalkSchedule (N30): the header's rules
// as invariants, checked after every step of 50 000 random operation sequences, plus liveness
// (no request is ever lost) at a drain.

@Suite("P5a FolderWalkSchedule model check")
struct P5aWalkScheduleModelTests {
    @Test("SCHED-1: safety + liveness over random operation sequences")
    func randomModelCheck() {
        var generator = SeededGenerator(seed: 0xF01D)
        var violations: [String] = []
        for run in 0 ..< 50000 where violations.count < 5 {
            var schedule = FolderWalkSchedule()
            var running: [Int64: FolderWalk] = [:]
            var owedAdd: Set<Int64> = []
            var owedAny: Set<Int64> = []
            var removing: Set<Int64> = []
            var stopped = false
            var log: [String] = []

            func apply(_ starts: [FolderWalkSchedule.Start], _ step: String) {
                for start in starts {
                    if running[start.folderID] != nil {
                        violations.append("run \(run): two walks of \(start.folderID) — \(log + [step])")
                    }
                    if start.walk == .add, running.values.contains(.add) {
                        violations.append("run \(run): two adds — \(log + [step])")
                    }
                    if removing.contains(start.folderID) || stopped {
                        violations.append("run \(run): started \(start.folderID) while removing/stopped — \(log + [step])")
                    }
                    running[start.folderID] = start.walk
                    owedAny.remove(start.folderID)
                    if start.walk == .add {
                        owedAdd.remove(start.folderID)
                    }
                }
            }

            for _ in 0 ..< Int.random(in: 1 ... 40, using: &generator) {
                let folder = Int64.random(in: 1 ... 3, using: &generator)
                switch Int.random(in: 0 ... 9, using: &generator) {
                case 0 ... 2:
                    let walk: FolderWalk = Bool.random(using: &generator) ? .add : .reconcile
                    let step = "request(\(walk), \(folder))"
                    if !stopped, !removing.contains(folder) {
                        owedAny.insert(folder)
                        if walk == .add {
                            owedAdd.insert(folder)
                        }
                    }
                    apply(schedule.request(walk, of: folder), step)
                    log.append(step)
                case 3:
                    let step = "catchUp(\(folder))"
                    let wasIdle = running[folder] == nil
                    let starts = schedule.requestCatchUp(of: folder)
                    if wasIdle, !stopped, !removing.contains(folder), starts.isEmpty, !owedAny.contains(folder) {
                        violations.append("run \(run): idle catch-up started nothing and nothing waits — \(log + [step])")
                    }
                    apply(starts, step)
                    log.append(step)
                case 4 ... 6:
                    guard let (id, _) = running.randomElement(using: &generator) else { continue }
                    let cancelled = Int.random(in: 0 ... 3, using: &generator) == 0
                    let step = "finish(\(id), cancelled: \(cancelled))"
                    running[id] = nil
                    if cancelled, !stopped, !removing.contains(id) {
                        owedAny.insert(id) // a cancelled walk is owed a reconcile
                    }
                    apply(schedule.finish(id, cancelled: cancelled), step)
                    log.append(step)
                case 7:
                    let step = "beginRemoving(\(folder))"
                    schedule.beginRemoving(folder)
                    removing.insert(folder)
                    owedAny.remove(folder)
                    owedAdd.remove(folder)
                    log.append(step)
                case 8:
                    let step = "endRemoving(\(folder))"
                    schedule.endRemoving(folder)
                    removing.remove(folder)
                    log.append(step)
                default:
                    if Int.random(in: 0 ... 5, using: &generator) == 0 {
                        schedule.stop()
                        stopped = true
                        owedAny.removeAll()
                        owedAdd.removeAll()
                        log.append("stop")
                    }
                }
            }
            // Drain: finish every walk (not cancelled) until nothing runs. Every owed request must
            // have started by then — none may be stuck behind a walk that never comes.
            var guardSteps = 0
            while let (id, _) = running.first, guardSteps < 100 {
                guardSteps += 1
                running[id] = nil
                apply(schedule.finish(id, cancelled: false), "drain finish(\(id))")
            }
            if !owedAny.isEmpty || !owedAdd.isEmpty {
                violations.append("run \(run): requests never started: any=\(owedAny) add=\(owedAdd) — \(log)")
            }
        }
        print("P5A SCHED-1 violations=\(violations.count) \(violations.first ?? "")")
        #expect(violations.isEmpty)
    }
}
