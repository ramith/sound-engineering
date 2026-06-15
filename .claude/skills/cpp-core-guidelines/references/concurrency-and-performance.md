# Concurrency and performance (CP, Per)

Consult this file when uncertain about: data races, locks, threads (`thread`/`jthread`/detach),
`volatile`, passing data between threads, or performance/optimization decisions and data layout.

## Contents
**Concurrency (CP)**
- CP.1 Assume multi-threaded use
- CP.2 Avoid data races
- CP.3 Minimize sharing of writable data
- CP.4 Think in tasks, not threads
- CP.8 Don't use `volatile` for synchronization
- CP.20 Use RAII, never plain `lock()`/`unlock()`
- CP.21 Use `scoped_lock` for multiple mutexes
- CP.22 Never call unknown code while holding a lock
- CP.23 / CP.24 Joining vs global threads
- CP.25 / CP.26 Prefer `jthread`; don't `detach()`
- CP.31 Pass small data between threads by value
- CP.32 Share ownership across unrelated threads with `shared_ptr`
- CP.42 Don't `wait` without a condition
- CP.44 Name your `lock_guard`s
- CP.50 Define a `mutex` with the data it guards

**Performance (Per)**
- Per.1 / Per.2 / Per.3 Don't optimize without reason / prematurely / non-critical code
- Per.4 / Per.5 Complicated / low-level isn't necessarily faster
- Per.6 No performance claims without measurement
- Per.7 Design to enable optimization
- Per.11 Move computation to compile time
- Per.14 / Per.15 Minimize allocations; none on a critical branch
- Per.16 / Per.17 / Per.18 / Per.19 Compact, predictable data layout

---

## Concurrency

### CP.1 — Assume your code will run as part of a multi-threaded program
**Why:** Library and reusable code may be used concurrently even if today it isn't. Designing for
that avoids surprises later. (`const` and immutable data are your friends here.)

### CP.2 — Avoid data races
**Why:** A data race (two threads access the same object concurrently, at least one writing,
without synchronization) is undefined behavior — anything can happen. Protect shared mutable data
with a mutex, make it immutable, or don't share it.

### CP.3 — Minimize explicit sharing of writable data
**Why:** The less writable state is shared, the fewer opportunities for races and the simpler the
reasoning. Prefer message passing and immutable data over shared mutable state.

### CP.4 — Think in terms of tasks, rather than threads
**Why:** A *task* is a unit of work with clear inputs/outputs; a *thread* is a low-level mechanism.
Reasoning in tasks (e.g. `async`, futures) reduces the bookkeeping and the chance of sharing bugs.

### CP.8 — Don't try to use `volatile` for synchronization
**Why:** `volatile` does not provide atomicity or inter-thread ordering — it's for memory-mapped
hardware and `setjmp`, not threading. Using it for synchronization is a common mistake that leaves
the race in place. Use `std::atomic` or a `mutex`.

```cpp
volatile int free_slots = max_slots;   // BAD: still a data race; no atomicity/ordering
std::atomic<int> free_slots = max_slots;  // GOOD
```

### CP.20 — Use RAII, never plain `lock()`/`unlock()`
**Why:** Manual unlock will eventually be skipped by an early `return`, a `throw`, or a forgotten
path, leaving the mutex locked (deadlock). A lock guard releases on every path.

```cpp
void do_stuff() { mtx.lock(); /* ... */ mtx.unlock(); }   // BAD: unlock easily skipped
```
```cpp
void do_stuff() { unique_lock<mutex> lck {mtx}; /* ... */ }  // GOOD: always released
```

### CP.21 — Use `std::scoped_lock` (or `std::lock`) to acquire multiple mutexes
**Why:** Locking several mutexes in different orders in different threads deadlocks. `scoped_lock`
acquires them together with a deadlock-avoidance algorithm.

```cpp
// thread 1: lock_guard lck1(m1); lock_guard lck2(m2);
// thread 2: lock_guard lck2(m2); lock_guard lck1(m1);   // BAD: opposite order -> deadlock
std::scoped_lock lck(m1, m2);   // GOOD: acquires both safely
```

### CP.22 — Never call unknown code while holding a lock (e.g. a callback)
**Why:** Unknown code might try to acquire the same lock (self-deadlock) or another (ordering
deadlock), or block indefinitely. Release the lock before invoking it, or copy out what you need.

### CP.23 / CP.24 — A joining thread is a scoped container; a detached thread is a global one
**Why:** A thread that joins behaves like a stack object whose lifetime is the scope; one you
detach behaves like a global. Treat their captured data accordingly — references to locals are safe
for a joining thread but dangerous for a detached one.

### CP.25 / CP.26 — Prefer `jthread`/`gsl::joining_thread`; don't `detach()`
**Why:** A `std::thread` that is neither joined nor detached `terminate`s the program at scope exit.
Detached threads are hard to monitor or shut down cleanly. A joining thread (C++20 `std::jthread`)
joins automatically in its destructor.

```cpp
int main() { std::thread t1{f}; std::thread t2{F()}; }   // BAD: never joined -> terminate
```
```cpp
int main() { std::jthread t1{f}; std::jthread t2{F()}; } // GOOD: join on scope exit
```

### CP.31 — Pass small amounts of data between threads by value
**Why:** Copying small data avoids lifetime and race questions entirely; references/pointers shared
across threads need synchronization and outlive-the-thread guarantees.

### CP.32 — To share ownership between unrelated threads, use `shared_ptr`
**Why:** When you can't establish a clear single owner whose lifetime covers all threads, shared
ownership keeps the object alive until the last thread finishes.

### CP.42 — Don't `wait` without a condition
**Why:** A condition-variable `wait` without a predicate can wake spuriously and proceed when it
shouldn't. Always wait on a predicate.

```cpp
cv.wait(lk);                          // BAD: spurious wakeups proceed wrongly
cv.wait(lk, []{ return ready; });     // GOOD: re-checks the condition
```

### CP.44 — Name your `lock_guard`s and `unique_lock`s
**Why:** An unnamed lock guard is a temporary that is destroyed immediately, so it locks and
instantly unlocks — providing no protection.

```cpp
lock_guard<mutex>{mtx};       // BAD: temporary -> unlocks immediately
lock_guard<mutex> guard{mtx}; // GOOD
```

### CP.50 — Define a `mutex` together with the data it guards
**Why:** Keeping the mutex next to (or wrapping) the data it protects makes the association obvious
and harder to get wrong. (`synchronized_value<T>` where available.)

---

## Performance

### Per.1 / Per.2 / Per.3 — Don't optimize without reason, prematurely, or in non-critical code
**Why:** Optimization adds complexity and bugs. Optimize only where measurement shows it matters;
most code isn't on a hot path, and premature optimization wastes effort and obscures intent. Time
spent well on correctness, safety, or testing is *not* waste.

### Per.4 / Per.5 — Complicated or low-level code isn't necessarily faster
**Why:** Clever/low-level code is often *slower* (harder for the optimizer) as well as buggier.
Simple, high-level code (e.g. standard algorithms) frequently optimizes better. Measure rather than
assume.

### Per.6 — Don't make claims about performance without measurements
**Why:** Intuition about performance is unreliable across compilers, libraries, and hardware. Always
measure before asserting one approach is faster.

### Per.7 — Design to enable optimization
**Why:** Interfaces that carry enough information (sizes, value semantics, `const`, strong types)
let the compiler and you optimize later without redesign. (E.g. pass a `span`, return by value.)

### Per.11 — Move computation from run time to compile time
**Why:** Work done at compile time (`constexpr`, templates) costs nothing at run time and is checked
by the compiler.

```cpp
constexpr int table_size = compute_size();   // computed once, at compile time
```

### Per.14 / Per.15 — Minimize allocations/deallocations; never allocate on a critical branch
**Why:** Heap allocation is comparatively expensive and can introduce unpredictable latency.
Reuse buffers, prefer stack/`reserve`, and keep allocation off hot/critical paths.

### Per.16 / Per.17 / Per.18 / Per.19 — Use compact, predictably-accessed data
**Why:** Memory bandwidth and cache behavior often dominate runtime ("space is time"). Compact
structures, putting the most-used member first in a time-critical struct, and predictable
(sequential) access patterns improve cache utilization far more than micro-optimizing arithmetic.
