// The view model's fire-and-forget work, counted (test seam).
//
// A view model's commands are `Task {}`s nobody awaits: a start, a stop, a device read. A test that
// needs "everything the view model set going has finished" had nothing to wait on and yielded fifty
// times, hoping. Each such task is spawned through the tracker, which counts it in and out; a test
// waits until `isIdle`. Main actor only, so the count is plain state.

import Foundation

@MainActor
final class WorkTracker {
    /// Tasks spawned and not yet finished.
    private var inFlight = 0

    /// Nothing the view model spawned is still running.
    var isIdle: Bool {
        inFlight == 0
    }

    /// Run `body` as a task on the main actor — the same task a bare `Task { … }` would be — counted
    /// until it finishes.
    @discardableResult
    func spawn(_ body: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        inFlight += 1
        return Task { [self] in
            defer { inFlight -= 1 }
            await body()
        }
    }

    /// Run `body` detached at `priority` — as a bare `Task.detached` would — counted until it finishes.
    func spawnDetached(priority: TaskPriority, _ body: @escaping @Sendable () async -> Void) {
        inFlight += 1
        Task.detached(priority: priority) { [self] in
            await body()
            await finishDetached()
        }
    }

    private func finishDetached() {
        inFlight -= 1
    }
}
