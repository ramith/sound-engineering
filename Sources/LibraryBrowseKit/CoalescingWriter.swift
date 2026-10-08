// MARK: - CoalescingWriter (S10.8 E4 fix round — each playlist's newest order, written once)

/// Writes values through an async `sink`, one write at a time, keeping only the NEWEST unwritten
/// value per key: a burst of values for one key coalesces into one write of the last, and no write
/// for a key can land after a newer one. Keys take turns in the order they were submitted — a key
/// resubmitted while it is being written queues behind the others — so a busy key never starves
/// the rest. The sink owns failure: once it returns, its value is no longer unsaved.
///
/// It also answers what is still UNSAVED for a key (waiting, else being written), so a reader whose
/// read may predate that write lays the unsaved value over what it read instead of publishing the
/// stale one. `@MainActor` so a check and the publish that relies on it can't be split by a
/// suspension. Generic, so the coalescing and the turn order are unit-tested without a store.
@MainActor
public final class CoalescingWriter<Key: Hashable, Value> {
    public typealias Sink = @MainActor (Key, Value) async -> Void

    private let sink: Sink
    /// Keys with a waiting value, in turn order; each at most once.
    private var turns: [Key] = []
    private var waiting: [Key: Value] = [:]
    private var writing: (key: Key, value: Value)?
    /// The task draining `turns`; nil while idle.
    private var drainer: Task<Void, Never>?

    public init(sink: @escaping Sink) {
        self.sink = sink
    }

    /// Makes `value` the newest for `key`, replacing a waiting older one (which is then never
    /// written), and starts the writes if they are idle.
    public func submit(_ value: Value, for key: Key) {
        if waiting.updateValue(value, forKey: key) == nil {
            turns.append(key)
        }
        if drainer == nil {
            drainer = Task { await drain() }
        }
    }

    /// The newest value for `key` that isn't written yet — waiting, else being written — or nil.
    public func unsavedValue(for key: Key) -> Value? {
        if let value = waiting[key] {
            return value
        }
        return writing?.key == key ? writing?.value : nil
    }

    /// Returns once everything submitted — including values submitted while it waits — is written.
    public func flush() async {
        while let drainer {
            await drainer.value
        }
    }

    private func drain() async {
        while !turns.isEmpty {
            let key = turns.removeFirst()
            guard let value = waiting.removeValue(forKey: key) else { continue }
            writing = (key, value)
            await sink(key, value)
            writing = nil
        }
        drainer = nil
    }
}
