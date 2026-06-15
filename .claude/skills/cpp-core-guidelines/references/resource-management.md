# Resource management (R)

Resource safety is the single highest-leverage area of modern C++. A *resource* is anything
that must be acquired and released: memory, file handles, sockets, locks, threads. The two
goals are: never leak, and never hold longer than needed. The entity responsible for releasing
a resource is its *owner*.

Consult this file when uncertain about ownership, smart-pointer choice, smart-pointer
parameters, `new`/`delete`/`malloc`, or leak safety in the presence of exceptions.

## Contents
- R.1 RAII for all resources
- R.3 / R.4 Raw pointers and references are non-owning
- R.5 Prefer scoped (stack) objects
- R.10 Avoid `malloc`/`free`
- R.11 Avoid explicit `new`/`delete`
- R.12 Hand allocations to a manager immediately
- R.13 At most one explicit allocation per expression
- R.20 Use `unique_ptr`/`shared_ptr` for ownership
- R.21 Prefer `unique_ptr` over `shared_ptr`
- R.22 / R.23 Use `make_shared` / `make_unique`
- R.24 Break `shared_ptr` cycles with `weak_ptr`
- R.30–R.37 Smart-pointer parameter conventions

---

### R.1 — Manage resources automatically using RAII
**Why:** Constructor/destructor symmetry mirrors acquire/release pairs (`open`/`close`,
`lock`/`unlock`, `new`/`delete`). With manual release you must remember to release on *every*
path exactly once; any early `return` or thrown exception between acquire and release leaks.

```cpp
// BAD: must remember unlock + close + delete on every path; throw between them leaks
void send(X* x, string_view destination)
{
    auto port = open_port(destination);
    my_mutex.lock();
    // ...
    send(port, x);
    // ...
    my_mutex.unlock();
    close_port(port);
    delete x;
}
```
```cpp
// GOOD: each resource owned by an object; cleanup is automatic on all paths
void send(unique_ptr<X> x, string_view destination)  // x owns the X
{
    Port port{destination};             // port owns the PortHandle
    lock_guard<mutex> guard{my_mutex};  // guard owns the lock
    // ...
    send(port, x);
    // ...
}   // unlocks my_mutex and deletes the X automatically, even on exception
```
For an "ill-behaved" resource without its own RAII wrapper, wrap it in a small class (acquire in
the constructor, release in the destructor) or use a `finally`/scope-guard helper.

---

### R.3 / R.4 — A raw pointer (`T*`) or reference (`T&`) is non-owning
**Why:** Nothing in the language marks a raw pointer as an owner, and most are not. Treating
"owner" and "observer" pointers identically is how double-frees and leaks happen. Make ownership
explicit so deletion is reliable.

```cpp
// BAD: is p owning or not? Reader and tools can't tell.
template<typename T>
class X { public: T* p; T* q; /* ... */ };
```
```cpp
// GOOD: owner<T*> marks the owning pointer; plain T* is an observer.
template<typename T>
class X2 { public: gsl::owner<T*> p; T* q; /* ... */ };
```
A reference should *never* own. If a member must point to something, use a pointer (raw or smart),
not a reference.

---

### R.5 — Prefer scoped objects; don't heap-allocate unnecessarily
**Why:** A local (stack) object is cheaper, needs no explicit cleanup, and can't leak. Reach for
the free store only when you need a lifetime that outlives the scope or a size unknown at compile
time.

```cpp
// BAD: needless allocation and manual delete
void f() { Gadget* p = new Gadget{...}; use(*p); delete p; }
```
```cpp
// GOOD: a plain local
void f() { Gadget g{...}; use(g); }
```

---

### R.10 — Avoid `malloc()` and `free()`
**Why:** They don't run constructors or destructors and don't mix with `new`/`delete`. A
`malloc`'d object is a "string-sized bag of bits", not a constructed object; `delete`ing it (or
`free`ing a `new`'d object) is undefined behavior.

```cpp
// BAD
Record* p1 = static_cast<Record*>(malloc(sizeof(Record))); // *p1 not constructed
// ...
delete p1;  // UB: delete of malloc'd memory
```
Use `new`/smart pointers (or, better, containers) instead.

---

### R.11 — Avoid calling `new` and `delete` explicitly
**Why:** The result of `new` should immediately belong to a resource handle that owns the
`delete`. A naked `new` implies a naked `delete` somewhere — and if you have N `delete`s, you can
never be sure you don't need N±1. The bug is often latent and surfaces during maintenance.

```cpp
// BAD
auto* p = new Widget{7};
// ... easy to leak or double-delete ...
delete p;
```
```cpp
// GOOD
auto p = make_unique<Widget>(7);   // deletion is guaranteed
```

---

### R.12 — Give the result of an explicit allocation to a manager immediately
**Why:** Any code between the raw allocation and handing it to an owner is a leak window — an
exception (e.g. from a later allocation) escapes before ownership is established.

```cpp
// BAD: if `buf` allocation throws, the FILE* leaks
void func(const string& name)
{
    FILE* f = fopen(name.c_str(), "r");
    vector<char> buf(1024);
    auto _ = finally([f]{ fclose(f); });
    // ...
}
```
```cpp
// GOOD: ifstream owns the handle from the first line
void func(const string& name)
{
    ifstream f{name};
    vector<char> buf(1024);
    // ...
}
```

---

### R.13 — Perform at most one explicit resource allocation in a single expression
**Why:** Argument subexpressions can be evaluated and interleaved in an unspecified order. Two
`new`s in one call can both allocate before either constructor runs; if one constructor throws,
the other allocation leaks.

```cpp
// BAD: potential leak if reordered/interleaved
fun(shared_ptr<Widget>(new Widget(a, b)), shared_ptr<Widget>(new Widget(c, d)));
```
```cpp
// BEST: factory functions leave no unmanaged window
fun(make_shared<Widget>(a, b), make_shared<Widget>(c, d));
```

---

### R.20 — Use `unique_ptr` or `shared_ptr` to represent ownership
**Why:** They prevent leaks by guaranteeing deletion, even under exceptions. A raw owning pointer
does not.

```cpp
void f()
{
    X* p1 { new X };             // BAD: p1 leaks
    auto p2 = make_unique<X>();  // GOOD: unique ownership
    auto p3 = make_shared<X>();  // GOOD: shared ownership
}
```

---

### R.21 — Prefer `unique_ptr` over `shared_ptr` unless you need to share
**Why:** `unique_ptr` is simpler and more predictable (you know exactly when destruction happens)
and faster (no atomic reference count). Use `shared_ptr` only when ownership is genuinely shared.

```cpp
// BAD: refcount never exceeds 1 — the atomics are pure overhead
void f() { shared_ptr<Base> b = make_shared<Derived>(); use_locally(b); }
```
```cpp
// GOOD
void f() { unique_ptr<Base> b = make_unique<Derived>(); use_locally(b); }
```

---

### R.22 / R.23 — Use `make_shared()` / `make_unique()`
**Why:** They name the type once (less repetition), are exception-safe inside complex expressions,
and `make_shared` can fuse the control-block and object into one allocation.

```cpp
shared_ptr<X> p1 { new X{2} }; // BAD
auto p = make_shared<X>(2);    // GOOD

unique_ptr<Foo> q1 {new Foo{7}}; // BAD: repeats Foo
auto q = make_unique<Foo>(7);    // GOOD
```

---

### R.24 — Use `std::weak_ptr` to break cycles of `shared_ptr`s
**Why:** Reference-counted cycles never reach zero, so the objects are never freed. Make one
direction of the cycle a non-owning `weak_ptr` and `lock()` it when you need access.

```cpp
class foo { std::shared_ptr<bar> forward_; /* ... */ };
class bar {
    std::weak_ptr<foo> back_;                       // breaks the cycle
public:
    void do_something() {
        if (auto p = back_.lock()) { /* use *p */ }  // safe access
    }
};
```

---

### R.30–R.37 — Smart-pointer parameter conventions
**Why:** A function should take a smart pointer *only* when it participates in lifetime. Otherwise
it over-constrains callers (only that smart-pointer type works) and, for `shared_ptr` by value,
silently pays atomic-refcount cost. The parameter type should state the lifetime contract:

| Parameter                       | Meaning                                                            |
|---------------------------------|--------------------------------------------------------------------|
| `widget*` / `widget&`           | Function only *uses* the widget; no lifetime claim (default).      |
| `unique_ptr<widget>`            | Function *takes ownership* (sink).                                 |
| `unique_ptr<widget>&`           | Function may *reseat* the caller's pointer.                        |
| `shared_ptr<widget>`            | Function *shares ownership* (retains a count).                     |
| `shared_ptr<widget>&`           | Function may *reseat* the shared pointer.                          |
| `const shared_ptr<widget>&`     | Function *might* retain a count.                                   |

```cpp
// BAD: takes shared_ptr but never touches the ownership — pure pessimization + over-constraint
void f(shared_ptr<widget>& w) { use(*w); }
```
```cpp
// GOOD: it only uses the widget, so take a reference
void f(widget& w) { use(w); }
```

### R.37 — Don't pass a pointer/reference obtained from an *aliased* smart pointer
**Why:** The #1 cause of dangling references in shared-ownership code. If a callee resets/reassigns
the original `shared_ptr` (e.g. a global), the object you handed down by raw pointer can be
destroyed mid-call. Take a local copy first to pin the refcount for the duration of the call tree.

```cpp
shared_ptr<widget> g_p = ...;
void my_code() {
    f(*g_p);       // BAD: f() or a callee might reset g_p and destroy the widget
}
```
```cpp
void my_code() {
    auto pin = g_p;  // one increment pins the object for this whole call tree
    f(*pin);         // GOOD
}
```
