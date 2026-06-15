# Error handling (E)

Error handling pervades a whole program, so it must be designed early and applied consistently.
The strategy is built around invariants and RAII: a constructor establishes an invariant (throwing
if it can't), member functions assume it, and RAII guarantees cleanup on every path including the
exceptional one.

Consult this file when uncertain about: when to throw, what to throw, how to catch, `noexcept`,
leak-safety under exceptions, cleanup without a resource handle, or exception-free environments.

## Contents
- E.2 Throw to signal a task can't be done
- E.3 Exceptions for error handling only
- E.4 / E.5 Design around invariants; constructors establish them
- E.6 Use RAII to prevent leaks
- E.12 `noexcept` when a throw can't/shouldn't escape
- E.13 Never throw while the direct owner of an object
- E.14 Use purpose-designed user-defined exception types
- E.15 Throw by value, catch by reference
- E.16 Destructors/deallocation/`swap`/exception-copy must never fail
- E.17 / E.18 Don't catch everything everywhere; minimize `try`/`catch`
- E.19 Use a `final_action` (scope guard) when no resource handle fits
- E.25–E.28 Exception-free environments
- E.30 / E.31 No exception specifications; order `catch` clauses

---

### E.2 — Throw an exception to signal that a function can't perform its assigned task
**Why:** An error means the function can't achieve its advertised purpose (including establishing
its postconditions). Throwing makes that impossible to ignore. (A *status* that the caller is
expected to handle — like "server refused the connection" — is not necessarily an error; return it
as a value to be checked.)

### E.3 — Use exceptions for error handling only
**Why:** Exceptions are for errors, not normal control flow. Using them for ordinary flow makes
code hard to follow and slow on the exceptional path.

### E.4 / E.5 — Design your error handling around invariants; let constructors establish them
**Why:** An invariant is the logical condition member functions rely on. If a class has an
invariant, a constructor must establish it (and throw if it can't), so the rest of the class can
assume a valid object. (See C.40–C.42.)

### E.6 — Use RAII to prevent leaks
**Why:** Manual cleanup before each `throw`/`return` is error-prone; an exception in the middle
skips it. RAII releases automatically on every path.

```cpp
void f1(const char* name) {
    FILE* input = fopen(name, "r");
    // ...
    if (something) return;   // BAD: leaks the file handle
    fclose(input);
}
```
```cpp
void f2(const char* name) {
    ifstream input {name};   // GOOD: closed automatically on every path
    // ...
    if (something) return;
}
```

### E.12 — Use `noexcept` when a throw out of a function is impossible or unacceptable
**Why:** It documents and enforces "this can't fail", helps the optimizer, and speeds the exit
after failure. Use it when the body genuinely can't throw, or when you'd rather crash than continue
(e.g. you treat allocation failure as fatal).

```cpp
double compute(double d) noexcept { return log(sqrt(d <= 0 ? 1 : d)); }  // composed of non-throwing ops
```

### E.13 — Never throw while being the direct owner of an object
**Why:** If you hold a resource directly (a raw `new`'d pointer, an unwrapped handle) and throw
before releasing it, it leaks. Own resources through handles so the throw can't leak them.

```cpp
void leak(int x) {
    auto p = new int{7};
    if (x < 0) throw Get_me_out_of_here{};   // BAD: *p leaks
    delete p;
}
```
```cpp
void no_leak(int x) {
    auto p = make_unique<int>(7);
    if (x < 0) throw Get_me_out_of_here{};   // GOOD: *p is freed during unwinding
}
```

### E.14 — Use purpose-designed user-defined types as exceptions (not built-in types)
**Why:** A user-defined type carries meaningful information and won't clash with someone else's
`throw 7`. Deriving from `std::exception`/`std::runtime_error` lets handlers catch specifically or
generically.

```cpp
throw 7;                    // BAD
throw "something bad";      // BAD
throw std::exception{};     // BAD: no info
```
```cpp
class MyException : public std::runtime_error {
public:
    MyException(const string& msg) : std::runtime_error{msg} {}
};
throw MyException{"something bad"};       // GOOD
throw std::invalid_argument("i is odd"); // GOOD when no extra info is needed
```

### E.15 — Throw by value, catch exceptions from a hierarchy by reference
**Why:** Catching a polymorphic exception by value slices it; throwing a raw pointer leaks. Throw a
value and catch by `const&`.

```cpp
throw new widget{};         // BAD: throw by raw pointer
catch (base_class e) {}     // BAD: slices
```
```cpp
catch (const base_class& e) { /* ... */ }   // GOOD
```
To rethrow, use bare `throw;` (not `throw e;`, which copies/slices).

### E.16 — Destructors, deallocation, `swap`, and exception-type copy/move must never fail
**Why:** These run during cleanup and error propagation; a program cannot be made reliable if they
throw or fail to do their job. (See C.36/C.37, C.84/C.85, C.66.) If a release truly can't happen,
treat it as a fatal design error.

```cpp
~Connection() { if (cannot_disconnect()) throw I_give_up{}; }   // BAD: throwing destructor
```

### E.17 / E.18 — Don't try to catch every exception in every function; minimize explicit `try`/`catch`
**Why:** Catching everywhere is verbose and obscures the normal flow. Catch only where you can
actually handle (or add information to) the error, and let RAII handle cleanup so most functions
need no `try`/`catch` at all.

### E.19 — Use a `final_action`/scope-guard object when no suitable resource handle exists
**Why:** For one-off cleanup of something without its own RAII type, a scope guard runs the action
on scope exit — more reliable than manual cleanup before each exit.

```cpp
void f(const string& name) {
    ifstream ifs {name};
    auto act = finally([&]{ cout << "done\n"; });   // runs on every exit path
    // ...
}
```

### E.25–E.28 — If you can't use exceptions
**Why:** In exception-free environments (e.g. hard-real-time), keep the same discipline by other
means: simulate RAII for cleanup (E.25), fail fast where continuing is worse (E.26), use error
codes *systematically* (E.27), and avoid global-state error reporting like `errno` (E.28).

### E.30 / E.31 — Don't use exception specifications; order `catch` clauses correctly
**Why:** Dynamic exception specifications (`throw(...)`) are removed/deprecated and were never
useful — use `noexcept` instead (E.30). Put more-derived exception handlers before their bases, or
the base handler shadows them (E.31).
