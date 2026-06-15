# Functions and interfaces (F, I)

Consult this file when uncertain about: parameter passing (in / in-out / sink / forward),
returning values vs out-parameters, returning references/pointers safely, `noexcept`, lambdas,
interface design, strong typing, `not_null`, `span`/`zstring`, ownership transfer across
interfaces, or argument count.

## Contents
**Interfaces (I)**
- I.1 Make interfaces explicit
- I.2 / I.3 Avoid non-`const` globals and singletons
- I.4 Make interfaces precisely and strongly typed
- I.5–I.8 State pre/postconditions (`Expects`/`Ensures`)
- I.10 Exceptions to signal failure
- I.11 Never transfer ownership by raw pointer/reference
- I.12 `not_null` for non-null pointers
- I.13 Don't pass an array as a single pointer
- I.23 Keep argument count low
- I.24 Avoid swappable adjacent parameters
- I.25 Empty abstract classes as interfaces
- I.27 Pimpl for stable ABI

**Functions (F)**
- F.2 / F.3 Single responsibility; short
- F.4 `constexpr` if usable at compile time
- F.6 `noexcept` if it must not throw
- F.7 Take `T*`/`T&`, not smart pointers, for general use
- F.16 "in" parameters
- F.17 "in-out" parameters
- F.18 "sink" parameters
- F.19 "forward" parameters
- F.20 Prefer return values to out-parameters
- F.21 Return a struct for multiple outputs
- F.42 / F.43 Return `T*` for position; never return ptr/ref to a local
- F.45 Don't return `T&&`
- F.46 `int main()`
- F.48 Don't `return std::move(local)`
- F.49 Don't return `const T`
- F.51 Prefer default arguments over overloading
- F.52 / F.53 Lambda capture: by reference locally, by value non-locally
- F.54 Don't use `[=]` to capture members
- F.55 Don't use `va_arg`
- F.56 Avoid unnecessary condition nesting

---

## Interfaces

### I.1 — Make interfaces explicit
**Why:** Hidden dependencies (global call-mode flags, `errno`) are easy to overlook and hard to
test. All inputs and outputs should flow through the function signature.

```cpp
// BAD: behavior depends on an invisible global; two identical calls can differ
int round(double d) { return (round_up) ? ceil(d) : d; }
```

### I.2 / I.3 — Avoid non-`const` global variables and singletons
**Why:** Mutable globals hide dependencies, allow unpredictable change, and create data races; a
singleton is just a complicated global in disguise. Pass state explicitly. (The Meyers
function-local `static` for initialize-on-first-use is the narrow accepted exception.)

### I.4 — Make interfaces precisely and strongly typed
**Why:** Types are the best documentation, are checked at compile time, and enable optimization.
`void*`, bare `int`s, and multiple `bool`s leave callers guessing and let wrong values through.

```cpp
draw_rectangle(100, 200, 100, 500);          // BAD: which numbers are what? what units?
set_settings(true, false, 42);               // BAD: meaningless at the call site
```
```cpp
void draw_rectangle(Point top_left, Size hw);   // GOOD: meaning + units in the types
void blink_led(milliseconds t);                 // GOOD: unit is explicit
blink_led(1500ms);
```

### I.5 / I.6 / I.7 / I.8 — State preconditions and postconditions
**Why:** Argument constraints and result guarantees that aren't stated are easily violated. Prefer
`Expects()`/`Ensures()` over comments or ad-hoc `if`s so they're distinguishable and tool-checkable.

```cpp
int area(int h, int w) {
    Expects(h > 0 && w > 0);   // precondition
    auto res = h * w;
    Ensures(res > 0);          // postcondition (catches overflow)
    return res;
}
```

### I.10 — Use exceptions to signal failure to perform a required task
**Why:** Error codes can be (and are) ignored, leaving the program in an undefined state.
Exceptions can't be silently dropped. ("Performance" is not a valid reason to avoid them.)

```cpp
int printf(const char* ...);                 // BAD: returns negative on failure, easily ignored
explicit thread(F&& f, Args&&... args);      // GOOD: throws system_error if it can't start
```

### I.11 — Never transfer ownership by a raw pointer (`T*`) or reference (`T&`)
**Why:** If it's unclear whether caller or callee owns the object, you get leaks or premature
destruction. Return by value (move) when possible; use `unique_ptr`/`shared_ptr` to transfer
ownership; mark `owner<T*>` only for legacy/ABI constraints.

```cpp
X* compute(args) { X* res = new X{}; /* ... */ return res; }   // BAD: who deletes it?
```
```cpp
vector<double> compute(args) { vector<double> res(10000); /* ... */ return res; } // GOOD: by value
```

### I.12 — Declare a pointer that must not be null as `not_null`
**Why:** States intent in the type, lets tools find missing null checks, and removes redundant
runtime checks.

```cpp
int length(const char* p);            // must assume p can be nullptr
int length(not_null<const char*> p);  // caller guarantees non-null; no check needed inside
```

### I.13 — Do not pass an array as a single pointer
**Why:** `(pointer, size)` interfaces and bare array-to-pointer decay lose the length, inviting
out-of-bounds access. Pass a `span` (or container) that carries the size; use `zstring` for
C-strings.

```cpp
void draw(Shape* p, int n);   // BAD: array decays to pointer; size by convention only
```
```cpp
void draw2(span<Circle>);     // GOOD: size travels with the data; element type checked
```

### I.23 — Keep the number of function arguments low
**Why:** Many parameters confuse and usually signal a missing abstraction or a function doing more
than one job. Bundle related arguments into a type. Aim for fewer than four.

```cpp
void f(int* some_ints, int len);   // BAD: C-style, unsafe, two correlated params
void f(span<int> some_ints);       // GOOD: one safe, bounds-checked argument
```

### I.24 — Avoid adjacent parameters callable in either order with different meaning
**Why:** Two adjacent same-type parameters are easily swapped silently. Differentiate them (e.g.
`const` on the "from" side), or pass a `span`, or name fields in a struct.

```cpp
void copy_n(T* p, T* q, int n);          // BAD: easy to reverse from/to
void copy_n(const T* p, T* q, int n);    // better: "from" is const
void copy_n(span<const T> p, span<T> q); // best
```

### I.25 — Prefer empty abstract classes as interfaces
**Why:** Interfaces without state are more stable than base classes that carry data. (See C.121.)

### I.27 — For a stable library ABI, consider the Pimpl idiom
**Why:** Private members participate in layout and overload resolution, so changing them forces
recompilation of all users. A pointer-to-implementation isolates them behind a stable interface.

```cpp
// widget.h
class widget {
    class impl;
    std::unique_ptr<impl> pimpl;
public:
    void draw();
    widget(int);
    ~widget();
    widget(widget&&) noexcept;
    widget& operator=(widget&&) noexcept;
};
```

---

## Functions

### F.2 / F.3 — One logical operation per function; keep functions short
**Why:** A function doing one thing is easier to understand, test, and reuse; large functions hide
logical errors and widen variable scopes. "Doesn't fit on a screen" is a practical "too large".

```cpp
// BAD: reads, writes, formats, handles errors, hard-codes int and streams — unreusable
void read_and_print() { int x; cin >> x; cout << x << "\n"; }
```
```cpp
// GOOD: separable, parameterized
int read(istream& is) { int x; is >> x; return x; }
void print(ostream& os, int x) { os << x << "\n"; }
```

### F.4 — Declare `constexpr` if a function might be evaluated at compile time
**Why:** `constexpr` lets the compiler evaluate it in constant expressions. (It permits, not
requires, compile-time evaluation; don't make everything `constexpr` — most work belongs at
run time, and APIs tied to runtime configuration must not be `constexpr`.)

### F.6 — Declare `noexcept` if your function must not throw
**Why:** Tells optimizers there are no exceptional exit paths, and makes the post-failure exit
fast. Destructors, swaps, moves, and default constructors should never throw. Don't sprinkle
`noexcept` everywhere — most functions can throw (via `new`, library calls); `noexcept` is most
valuable on low-level, frequently used functions and where you'd rather `terminate` than handle the
failure.

### F.7 — For general use, take `T*` or `T&`, not smart pointers
**Why:** A smart-pointer parameter forces callers to use *that* ownership scheme and (for
`shared_ptr` by value) pays atomic cost — even though the function only *uses* the object. Take a
smart pointer only when the function participates in lifetime. (See R.30–R.37.)

```cpp
void f(shared_ptr<widget>& w) { use(*w); }   // BAD: lifetime never used; stack widgets rejected
void f(widget& w) { use(w); }                // GOOD: accepts any widget
```

### F.16 — "in" parameters: pass cheaply-copied types by value, others by `const&`
**Why:** Both signal "won't modify" and accept rvalues. Small objects (≈2–3 words) are faster by
value (no indirection); larger objects are cheaper by `const&`.

```cpp
void f1(const string& s);  // OK: reference to const, always cheap
void f2(string s);         // bad: potentially expensive copy
void f3(int x);            // OK: unbeatable
void f4(const int& x);     // bad: pointless indirection for an int
```

### F.17 — "in-out" parameters: pass by reference to non-`const`
**Why:** A non-`const` reference makes it clear the function modifies the object the caller owns.

```cpp
void update(Record& r);    // r is read and written
```

### F.18 — "will-move-from" (sink) parameters: pass by `X&&` and `std::move` the parameter
**Why:** `X&&` binds to rvalues and requires an explicit `std::move` at the call site for lvalues,
documenting and enforcing the transfer.

```cpp
void sink(vector<int>&& v) { store_somewhere(std::move(v)); }
```
Exception: move-only, cheap-to-move types like `unique_ptr` may be taken by value for simplicity.

### F.19 — "forward" parameters: pass by `TP&&` and `std::forward` exactly once
**Why:** A forwarding reference (`TP&&`, `TP` a template parameter) ignores *and* preserves const-
ness and value category, so the function can hand the argument onward unchanged.

```cpp
template<class F, class... Args>
decltype(auto) invoke(F&& f, Args&&... args) { return forward<F>(f)(forward<Args>(args)...); }
```

### F.20 — For "out" outputs, prefer return values to output parameters
**Why:** A return value is self-documenting; an `&` could be in, out, or in-out and is easily
misused. Modern move semantics make returning large objects cheap.

```cpp
void find_all(const vector<int>&, vector<const int*>& out, int x);  // BAD: out-param
vector<const int*> find_all(const vector<int>&, int x);             // GOOD: return value
```

### F.21 — To return multiple outputs, prefer returning a struct
**Why:** A named struct documents what each value means; structured bindings make it ergonomic.
`pair`/`tuple` lose the names — use them only for independent entities or variadic code.

```cpp
struct f_result { int status; string data; };
f_result f(const string& input) { /* ... */ return {status, something()}; }
auto [status, data] = f(in);   // self-documenting
```

### F.42 / F.43 — Return `T*` for a position only; never return a pointer/reference to a local
**Why:** A returned `T*`/`T&` to a local refers to a destroyed stack frame — dangling, leading to
crashes or silent corruption. Returning `T*` is fine for indicating a *position* in a structure the
caller already owns, but never transfers ownership.

```cpp
int* f() { int fx = 9; return &fx; }   // BAD: dangling pointer to a destroyed local
int& g() { int x = 7; return x; }      // BAD: same, with a reference
```

### F.45 — Don't return a `T&&`
**Why:** It's a reference to a temporary that dies at the end of the full expression — a frequent
source of bugs. Use plain `auto` return for pass-through wrappers. (`std::move`/`std::forward` are
the only sanctioned `&&` returns.)

```cpp
template<class F> auto&& wrapper(F f) { return f(); }   // BAD: returns ref to a temporary
template<class F> auto   wrapper(F f) { return f(); }   // GOOD
```

### F.46 — `int` is the return type for `main()`
**Why:** It's a language rule; `void main()` is non-portable (no explicit `return` is required,
though).

### F.48 — Don't `return std::move(local)`
**Why:** Returning a local already moves implicitly; an explicit `std::move` *prevents* copy
elision (NRVO), so it's a pessimization.

```cpp
S bad()  { S r; return std::move(r); }   // BAD: blocks NRVO
S good() { S r; return r; }              // GOOD
```

### F.49 — Don't return `const T`
**Why:** It adds no value and suppresses move semantics on the result, forcing expensive copies.

```cpp
const vector<int> fct();   // BAD: the const blocks moves from the returned value
```

### F.51 — Prefer default arguments over overloading when the choice exists
**Why:** Default arguments give one implementation (so the semantics can't drift) and avoid code
duplication. (Overloads are still needed when the parameter *types* differ.)

```cpp
void print(const string& s, format f = {});             // GOOD: one implementation
// vs two overloads that could diverge
```

### F.52 / F.53 — Capture by reference for local lambdas; by value for non-local lambdas
**Why:** Local/algorithm lambdas finish before the captured objects die, so reference capture is
efficient and correct. A lambda that escapes (returned, stored on the heap, sent to a thread) must
not hold references to locals that will be gone — capture by value.

```cpp
std::for_each(begin(s), end(s), [&msg](auto& sock){ sock.send(msg); });  // GOOD: local, by ref
```
```cpp
int local = 42;
pool.queue_work([&]{ process(local); });   // BAD: local is gone when work runs
pool.queue_work([=]{ process(local); });   // GOOD: copy outlives the scope
```

### F.54 — Don't use `[=]` default capture for `this` or class members
**Why:** Inside a member function `[=]` captures the `this` *pointer* by value, so members are
captured by reference — looking like value capture but behaving like reference capture. Be explicit
(`[i, this]`, or C++17 `[*this]` for a copy).

```cpp
auto bad  = [=]      { use(i, x); };  // BAD: looks like copy; x is via this (by ref)
auto good = [i, this]{ use(i, x); };  // GOOD: explicit
```

### F.55 — Don't use `va_arg` arguments
**Why:** C varargs assume the right types were passed/read; the language can't enforce it, so it's
fragile and unsafe. Use overloading, variadic templates, `variant`, or `initializer_list`.

```cpp
int sum(...) { /* ... va_arg(list, int) ... */ }       // BAD: assumes ints; UB otherwise
template<class... Args> auto sum(Args... a){ return (... + a); }  // GOOD: type-safe fold
```

### F.56 — Avoid unnecessary condition nesting
**Why:** Shallow nesting reads better and states intent. Use guard clauses to handle exceptional
cases and return early; merge conditions instead of nesting them.

```cpp
void foo() { if (x) { if (y) { compute(x); } } }       // BAD: deep nesting
void foo() { if (!(x && y)) return; compute(x); }      // GOOD: guard + early return
```
