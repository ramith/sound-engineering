# Philosophy and templates (P, T)

The Philosophy (P) rules are the "why" behind everything else: the high-level principles that the
concrete rules implement. The Templates (T) rules cover generic programming and concepts.

Consult this file when uncertain about: overarching design principles (expressing intent, type
safety, compile-time vs run-time, encapsulation), or about templates, concepts, and template
metaprogramming.

## Contents
**Philosophy (P)**
- P.1 / P.3 Express ideas/intent directly in code
- P.2 Write in ISO Standard C++
- P.4 / P.5 / P.6 Static type safety; compile-time over run-time; checkability
- P.7 Catch run-time errors early
- P.8 Don't leak resources
- P.9 Don't waste time or space
- P.10 Prefer immutable data
- P.11 Encapsulate messy constructs
- P.13 Use support libraries (esp. the standard library)

**Templates (T)**
- T.1 / T.2 / T.3 Use templates to raise abstraction / express algorithms / express containers
- T.10 / T.11 / T.12 / T.13 Specify concepts; prefer standard concepts; shorthand notation
- T.20 / T.21 Meaningful concepts with complete operation sets
- T.40 Use function objects to pass operations to algorithms
- T.41 Require only essential properties in concepts
- T.42 Template aliases to simplify notation
- T.43 Prefer `using` to `typedef`
- T.120 Use TMP only when you really need to
- T.140 / T.143 Name reusable operations; don't write accidentally non-generic code
- T.144 Don't specialize function templates

---

## Philosophy

### P.1 / P.3 — Express ideas and intent directly in code
**Why:** Compilers and most readers don't read comments; what's in code has defined semantics and
can be checked. Say *what* should happen, not just *how*, and let well-named types/algorithms carry
the meaning.

```cpp
int index = -1;                                   // BAD: hand-rolled search, intent buried
for (int i = 0; i < v.size(); ++i)
    if (v[i] == val) { index = i; break; }
```
```cpp
auto p = find(begin(v), end(v), val);             // GOOD: intent is explicit
for (const auto& x : v) { /* read-only */ }       // GOOD: says "just iterating, read-only"
```
A `Month month() const` declaration says more than `int month()` (return type *and* immutability).

### P.2 — Write in ISO Standard C++
**Why:** Extensions have under-specified, compiler-varying semantics and hurt portability. If an
extension is necessary (system access), localize it behind an interface that can be compiled away.

### P.4 / P.5 / P.6 — Aim for static type safety; prefer compile-time checking; keep it checkable
**Why:** Errors caught by the type system or at compile time need no run-time handler and can't
slip through (P.4/P.5). What can't be checked at compile time should be checkable at run time —
don't design interfaces (like bare `pointer + count`) that make checking impossible (P.6).

```cpp
void read(int* p, int n);  int a[100];  read(a, 1000);  // BAD: off the end, uncheckable
void read(span<int> r);    int a[100];  read(a);        // GOOD: size known, checkable
```

### P.7 — Catch run-time errors early
**Why:** Late detection produces mysterious crashes and corrupted data far from the cause. Check at
the boundary (e.g. at the point of call), and prefer interfaces that let you check at all.

```cpp
void increment(int* p, int n) { for (int i=0;i<n;++i) ++p[i]; }   // BAD: can't defend itself
void increment(span<int> p)   { for (int& x : p) ++x; }           // GOOD: range checkable early
```

### P.8 — Don't leak any resources
**Why:** Even slow leaks exhaust resources over time, which matters most for long-running programs.
Use RAII (see the Resource management reference) so cleanup is automatic and exception-safe.

```cpp
FILE* input = fopen(name, "r"); if (something) return; fclose(input);  // BAD: leaks on early return
ifstream input {name}; if (something) return;                          // GOOD: RAII
```

### P.9 — Don't waste time or space
**Why:** "This is C++" — gratuitous waste (redundant copies, needless allocations, recomputing
`strlen` every loop iteration, suppressing moves) adds up across a codebase. Eliminate it by using
the right abstractions, not by hand-tuning everything.

```cpp
void lower(zstring s) { for (int i=0; i < strlen(s); ++i) s[i]=tolower(s[i]); }  // BAD: O(n^2)
```

### P.10 — Prefer immutable data to mutable data
**Why:** Constants are easier to reason about, can't change unexpectedly, enable optimization, and
can't have data races. (See the Con rules.)

### P.11 — Encapsulate messy constructs rather than spreading them through the code
**Why:** Low-level, error-prone code (manual pointer/`realloc` loops, casts, lifetime tricks) breeds
more of the same. Hide it behind a well-specified interface (often an existing library type).

```cpp
int* p = (int*)malloc(sizeof(int)*sz); /* manual realloc loop, forgot exhaustion check */ // BAD
vector<int> v; v.reserve(100); for (int x; cin >> x;) v.push_back(x);                      // GOOD
```

### P.13 — Use support libraries as appropriate (especially the standard library)
**Why:** A well-tested, well-documented library is more likely correct and fast than what you'd
write under time pressure, and its cost is shared across many users. You need a reason *not* to use
the standard library, not a reason to use it.

```cpp
std::sort(begin(v), end(v), std::greater<>());   // more likely correct & fast than a hand-rolled sort
```

---

## Templates and generic programming

### T.1 / T.2 / T.3 — Use templates to raise abstraction, express algorithms, and express containers
**Why:** Templates give generality, reuse, and efficiency without giving up performance. Constrain
a template by the *meaningful* requirement, not the bare operations one implementation happens to
use — over-constraining (e.g. requiring just `+=`) blocks valid uses and misses generalization.

```cpp
// BAD: two near-identical algorithms over-constrained to "Incrementable" / "Simple_number"
template<typename T> requires Incrementable<T>  T sum1(vector<T>& v, T s);
template<typename T> requires Simple_number<T>  T sum2(vector<T>& v, T s);
```
```cpp
// GOOD: one algorithm constrained by a meaningful concept
template<typename T> requires Arithmetic<T>
T sum(vector<T>& v, T s) { for (auto x : v) s += x; return s; }
```

### T.10 / T.11 / T.12 / T.13 — Specify concepts for template arguments; prefer standard concepts
**Why:** Concepts make a template's requirements explicit, give better diagnostics, and document the
interface. Prefer the standard library's concepts; use the shorthand notation for simple single-type
constraints; prefer a concept name to bare `auto` for clarity.

```cpp
template<typename Iter, typename Val>
  requires input_iterator<Iter> && equality_comparable_with<iter_value_t<Iter>, Val>
Iter find(Iter first, Iter last, Val v);
```

### T.20 / T.21 — Avoid "concepts" without meaningful semantics; require a complete operation set
**Why:** A concept should capture a coherent set of operations with real semantics (e.g. a number
supports `+`, `-`, `*`, `/`, comparisons), not an arbitrary syntactic fragment. Partial sets lead to
types that satisfy the concept but don't actually work in the algorithms.

### T.40 — Use function objects to pass operations to algorithms
**Why:** Function objects/lambdas are more flexible than function pointers and inline better,
letting algorithms be parameterized cleanly on behavior.

```cpp
std::sort(v.begin(), v.end(), [](const T& a, const T& b){ return a.rank() < b.rank(); });
```

### T.41 — Require only essential properties in a template's concepts
**Why:** Extra requirements (e.g. demanding a type be printable when the algorithm doesn't print)
needlessly restrict who can use the template. Constrain to what the algorithm actually needs to do
its job.

### T.42 / T.43 — Use template aliases to simplify notation; prefer `using` to `typedef`
**Why:** Aliases hide implementation detail and shorten verbose types; `using` reads left-to-right
and, unlike `typedef`, can be templated.

```cpp
template<class T> using Vec = std::vector<T, My_alloc<T>>;   // clearer than a typedef
using Pmf = void (X::*)(int);                                // reads better than typedef
```

### T.120 — Use template metaprogramming only when you really need to
**Why:** TMP is powerful but hard to read, debug, and compile. Reach for it only when simpler tools
(overloading, `constexpr`, ordinary templates, standard type traits) won't do, and prefer existing
TMP libraries to home-grown machinery.

### T.140 / T.143 — Name reusable operations; don't write accidentally non-generic code
**Why:** If an operation is used in more than one place, naming it aids reuse and readability
(T.140). And code meant to be generic can quietly bake in a concrete type/assumption — write it so
it actually works for the full intended set of types (T.143).

### T.144 — Don't specialize function templates
**Why:** Function template *partial* specialization isn't allowed, and explicit specialization
interacts confusingly with overload resolution. Overload instead, or specialize a class template the
function delegates to.
