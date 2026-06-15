# Expressions, statements, and constants (ES, Con)

Consult this file when uncertain about: initialization, `const`/`constexpr`, `auto`, scope,
casts, narrowing, `nullptr`, magic constants, slicing, `std::move` placement, loops
(`for`/range-`for`/`while`), `switch` fallthrough, or signed/unsigned arithmetic and subscripts.

## Contents
**Constants & immutability (Con)**
- Con.1 Make objects immutable by default
- Con.2 Make member functions `const` by default
- Con.3 Pass pointers/references to `const` by default
- Con.4 / ES.25 `const` for values fixed after construction
- Con.5 `constexpr` for compile-time values

**Expressions & statements (ES)**
- ES.5 / ES.6 Keep scopes small
- ES.10 One declaration per line
- ES.11 Use `auto` to avoid redundant type names
- ES.20 Always initialize an object
- ES.21 / ES.22 Don't declare before you have a value
- ES.23 Prefer `{}` initialization
- ES.26 Don't reuse a variable for two purposes
- ES.40 / ES.41 Avoid complicated expressions; parenthesize when unsure
- ES.45 Avoid magic constants
- ES.46 Avoid narrowing conversions
- ES.47 Use `nullptr`, not `0`/`NULL`
- ES.48 / ES.49 Avoid casts; use named casts
- ES.50 Don't cast away `const`
- ES.56 Write `std::move` only when moving to another scope
- ES.63 Don't slice
- ES.71 Prefer range-`for`
- ES.78 Don't rely on implicit `switch` fallthrough
- ES.100–ES.107 Signed/unsigned arithmetic and subscripts

---

## Constants and immutability

### Con.1 — By default, make objects immutable
**Why:** Immutable objects are easier to reason about, can't change unexpectedly, and can't have
data races. Make something non-`const` only when you must change it.

```cpp
for (const int i : c) cout << i << '\n';   // GOOD: just reading
for (int i : c) cout << i << '\n';         // BAD: mutable but only read
```
Exception: a local that is returned by value and is cheaper to move than copy should *not* be
`const` (the `const` would force a copy). Don't enforce this on by-value parameters.

### Con.2 — By default, make member functions `const`
**Why:** A `const` member function states it won't change observable state — better intent, more
compiler checks, and it can be called on `const` objects. (`mutable` members or pointed-to data may
still change for caching; `const` is not transitive.)

```cpp
class Point { int x, y; public: int getx() { return x; } };   // BAD: should be const
void f(const Point& pt) { int x = pt.getx(); }                // ERROR: getx not const
```

### Con.3 — By default, pass pointers and references to `const`
**Why:** So a callee can't unexpectedly change the caller's object. A plain `T*`/`T&` must be
assumed to modify — and may start doing so later without forcing recompilation.

```cpp
void f(char* p);        // assume f modifies *p
void g(const char* p);  // g does not modify *p
```

### Con.4 / ES.25 — Use `const` for values that don't change after construction
**Why:** A non-`const` variable must be assumed to be modified somewhere, so it's harder to reason
about. Declaring it `const`/`constexpr` documents and enforces immutability.

```cpp
int x = 7;          // reader must assume x changes in the loop below
const int y = 9;    // clearly fixed
```

### Con.5 — Use `constexpr` for values computable at compile time
**Why:** Better performance, compile-time checking, guaranteed compile-time evaluation, and no
race conditions.

```cpp
double    x = f(2);  // possible run-time evaluation
constexpr double z = f(2);  // error unless f(2) is a constant expression
```

---

## Expressions and statements

### ES.5 / ES.6 — Keep scopes small; declare loop names in the `for`-header
**Why:** Small scopes reduce the chance of confusion, accidental reuse, and resources held too
long. Declaring an index/condition variable in the `for`-statement limits its lifetime to the loop.

### ES.10 — Declare one name per declaration
**Why:** Multi-name declarations (especially with pointers/references) are error-prone and read
poorly (`int* p, q;` — `q` is an `int`, not a pointer).

### ES.11 — Use `auto` to avoid redundant repetition of type names
**Why:** Less typing, fewer mismatches, and it tracks the initializer's type automatically.

```cpp
auto p = make_unique<Foo>(7);   // no need to repeat unique_ptr<Foo>
```

### ES.20 — Always initialize an object
**Why:** Avoids used-before-set bugs and their undefined behavior, and improves readability and
refactoring. Assignment is not initialization — between declaration and the assignment, the object
can be read with a garbage value.

```cpp
void use() { int i; /* ... */ i = 7; }   // BAD: i uninitialized; can be read in the gap
void use() { int i = 7; string s; }      // GOOD (string is default-initialized)
```
Don't fake it with an "uninitialized" sentinel value — that just hides the used-before-set from
tools and adds invalid states.

### ES.21 / ES.22 — Don't introduce a variable before you need it / until you can initialize it
**Why:** Declaring early widens scope and tends to produce default-construct-then-assign. Declare at
the point where you have the value to initialize with.

### ES.23 — Prefer the `{}`-initializer syntax
**Why:** `{}` works uniformly, and unlike `()`/`=` it rejects narrowing conversions at compile
time, catching silent precision loss.

```cpp
int x {7.9};   // error: narrowing caught
int y = 7.9;   // silently becomes 7
```

### ES.26 — Don't use a variable for two unrelated purposes
**Why:** Reusing one variable for different meanings confuses readers and defeats type/lifetime
reasoning.

### ES.40 / ES.41 — Avoid complicated expressions; parenthesize when unsure of precedence
**Why:** Dense expressions hide bugs (and order-of-evaluation surprises). Explicit parentheses make
intent unambiguous and protect against precedence mistakes.

### ES.45 — Avoid "magic constants"; use symbolic constants
**Why:** Unnamed literals embedded in code are easy to miss and hard to understand. Name them
(`constexpr`) — or better, eliminate them with a range-based loop.

```cpp
for (int m = 1; m <= 12; ++m) ...                 // BAD: what is 12?
constexpr int first_month = 1, last_month = 12;   // better
for (auto m : month) ...                          // best: no constant exposed
```

### ES.46 — Avoid lossy (narrowing/truncating) arithmetic conversions
**Why:** Narrowing silently destroys information. If narrowing is intended, say so with
`gsl::narrow_cast` (asserted) or `gsl::narrow` (throws on loss).

```cpp
double d = 7.9;
int i = d;                       // BAD: silently 7
i = gsl::narrow_cast<int>(d);    // OK: "I asked for it" (becomes 7)
i = gsl::narrow<int>(d);         // OK: throws narrowing_error on loss
```

### ES.47 — Use `nullptr` rather than `0` or `NULL`
**Why:** `nullptr` can't be confused with an `int` and has a precise type, so overload resolution
and type deduction do the right thing.

```cpp
void f(int); void f(char*);
f(0);        // calls f(int)
f(nullptr);  // calls f(char*)
```

### ES.48 / ES.49 — Avoid casts; if you must, use a named cast
**Why:** Casts disable the type system, cause undefined behavior, and break optimizations; heavy
cast use usually signals a design problem. A C-style cast silently does *any* conversion — a named
cast (`static_cast`, `const_cast`, `reinterpret_cast`, `dynamic_cast`, `gsl::narrow[_cast]`) is
specific and lets the compiler catch mistakes.

```cpp
double d = 2;
auto p = (long*)&d;   // BAD: C-style cast — undefined behavior, no protection
```
```cpp
D* pd = dynamic_cast<D*>(pb);   // GOOD: checked, intent explicit
// for lossless conversions, brace init also documents intent and rejects narrowing:
double dd { some_float };
```

### ES.50 — Don't cast away `const`
**Why:** It makes a lie of `const`; if the object is truly `const`, modifying it is undefined
behavior. To share logic between `const` and non-`const` accessors, factor it into a `const`-
deducing template helper instead of `const_cast`.

```cpp
void f(const int& x) { const_cast<int&>(x) = 42; }   // BAD: UB if x is really const
```
```cpp
class Foo {                                          // GOOD: no const_cast
public:
          Bar& get_bar()       { return get_bar_impl(*this); }
    const Bar& get_bar() const { return get_bar_impl(*this); }
private:
    Bar my_bar;
    template<class T> static auto& get_bar_impl(T& t) { /* deduces const */ }
};
```

### ES.56 — Write `std::move()` only when you need to move to another scope
**Why:** Most moves happen automatically (returns, passing rvalues). An explicit `std::move` on a
return of a local *blocks* copy elision; needless `std::move` adds noise and can pessimize.

```cpp
return std::move(local);   // BAD (see F.48): blocks NRVO
sink(std::move(owned));    // GOOD: deliberately hand ownership onward
```

### ES.63 — Don't slice
**Why:** Copying only the base part of a derived object via assignment/initialization loses the
derived state and is almost always a bug. The first defense is to design the base so it can't be
sliced (suppress copy — C.67). If slicing is truly intended, make it an explicit named operation.

```cpp
Circle c { {0,0}, 42 };
Shape s {c};   // BAD: copies only the Shape part of Circle — center/radius lost
```

### ES.71 — Prefer a range-`for` to a plain `for` when there's a choice
**Why:** Range-`for` is clearer, can't get the bounds or index arithmetic wrong, and reads as
"for each element".

```cpp
for (gsl::index i = 0; i < v.size(); ++i) use(v[i]);   // more error-prone
for (auto& x : v) use(x);                              // GOOD
```

### ES.78 — Don't rely on implicit fallthrough in `switch`
**Why:** A missing `break` is a classic bug. End every non-empty case with `break`/`return`, and
mark deliberate fallthrough with `[[fallthrough]];`.

```cpp
switch (n) {
case 1: do_one(); [[fallthrough]];   // intentional, marked
case 2: do_two(); break;
default: break;
}
```

### ES.100–ES.107 — Signed/unsigned arithmetic and subscripts
**Why:** Mixing signed and unsigned yields wrong results because the signed value converts to a
huge unsigned one (ES.100). Use signed types for arithmetic (ES.102) — `x - y` should go negative
when `y > x`, not wrap. Use unsigned only for bit manipulation/modular arithmetic (ES.101). Don't
use `unsigned` merely to assert non-negativity (ES.106) — it just hides bugs. For subscripts
(where the standard library uses unsigned but arrays use signed), prefer `gsl::index` (ES.107).

```cpp
int x = -3; unsigned y = 7;
cout << x - y;   // BAD: unsigned result, e.g. 4294967286
```
```cpp
gsl::index i = 0;             // GOOD: signed-ish index type, no mixed-sign surprises
for (i = 0; i < v.size(); ++i) ...
```
