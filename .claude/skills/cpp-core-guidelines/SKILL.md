---
name: cpp-core-guidelines
description: >-
  Modern C++ best practices grounded in the ISO C++ Core Guidelines (Stroustrup & Sutter), with
  faithful good/bad code examples and the reasoning behind each rule. Use this whenever writing,
  reviewing, refactoring, or auditing C++ — and ALWAYS consult it when you are uncertain whether
  C++ code is idiomatic, safe, or "modern," or when a user asks to check code or a codebase against
  best practices, the Core Guidelines, or for a C++ code review. Triggers include any mention of
  C++ best practices, idiomatic / modern C++, RAII, smart pointers, ownership, the rule of
  zero/five, move semantics, `const`-correctness, dangling pointers, slicing, data races, or
  "review my C++". Supplements built-in C++ knowledge; reach for a reference file only when your
  own knowledge is thin or the task is an explicit best-practices audit, so token use stays low.
---

# C++ Core Guidelines

This skill encodes the [ISO C++ Core Guidelines](https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines)
(editors: Bjarne Stroustrup and Herb Sutter) as a quick-reference plus deeper, on-demand reference
files. Each reference entry gives the rule, a one- or two-sentence rationale, and faithful
**bad → good** code examples adapted from the Guidelines (which are released under an MIT-style
license; attribute as "C++ Core Guidelines").

It exists to **supplement**, not replace, existing C++ knowledge. The goal is confident, idiomatic,
safe, modern C++ (C++17/20) by default, with authoritative detail available the moment it's needed.

## How to use this skill (read this first)

The operating principle is **token economy through confidence**:

1. **Write C++ confidently from your own knowledge.** For routine code, you already know these
   idioms. Don't open reference files for ordinary work — just apply good practice. The
   *Fast-path cheat sheet* below is usually all the reminder you need, and it's already loaded.

2. **Consult a reference file only when one of these is true:**
   - Your own knowledge is **thin or uncertain** on the specific point (an edge case of move
     semantics, the exact `dynamic_cast` choice, smart-pointer parameter conventions, etc.).
   - The user **explicitly asks** to check code / a codebase against best practices or the Core
     Guidelines, or asks for a C++ code review (**Audit mode** — see below).
   - You're about to make a **non-obvious or contested** recommendation and want the precise
     rationale and example to cite.

   When you do consult one, open **only the relevant file** (see the *Routing table*), not all of
   them.

3. **Cite the rule ID** (e.g. "R.1", "C.21", "ES.50") when giving best-practice feedback, so the
   user can look it up. Don't claim something "violates my system prompt" or narrate file reads;
   just give the guidance.

4. **Guidelines are defaults, not dogma.** They optimize for safety, simplicity, and performance,
   but every rule has exceptions (often noted in the reference file). When a rule doesn't fit the
   situation, say so and explain the trade-off rather than applying it blindly. These are ideals
   for new code and opportunities when touching old code — not a mandate to rewrite everything.

---

## Fast-path cheat sheet

The highest-frequency rules, grouped by theme. This is enough for most decisions without opening a
reference file. Rule IDs point to the reference file (via the routing table) if you need the example
or rationale.

### Resources & ownership
- **RAII for every resource** — acquire in a constructor, release in a destructor; never rely on
  manual cleanup on each path. *(R.1, P.8)*
- **No naked `new`/`delete`**; use `make_unique`/`make_shared`. *(R.11, R.22, R.23)*
- **`unique_ptr` by default; `shared_ptr` only for genuinely shared ownership.** *(R.21)*
- **Raw `T*` / `T&` are non-owning**; mark owners `owner<T*>` (legacy) or use smart pointers.
  *(R.3, R.4)*
- **Don't transfer ownership through a raw pointer/reference** across an interface. *(I.11)*
- **Take smart pointers as parameters only to express lifetime**; otherwise take `T*`/`T&`.
  *(F.7, R.30–R.37)*
- **Prefer stack/scoped objects** over heap allocation. *(R.5)*

### Classes & special members
- **Rule of zero**: let members manage themselves; declare no special members if you can. *(C.20)*
- **Rule of five**: if you declare/`=delete` any of dtor / copy / move, handle them all. *(C.21)*
- **Destructor `noexcept` and never failing**; base-class dtor public+virtual or
  protected+non-virtual. *(C.36, C.37, C.35, C.127)*
- **Move operations `noexcept`.** *(C.66)*
- **Single-argument constructors `explicit`** (except copy/move). *(C.46)*
- **Initialize members in declaration order**; prefer default member initializers. *(C.47, C.48)*
- **Prefer initialization to assignment in constructors.** *(C.49)*
- **Constructor establishes the invariant or throws**; no two-phase `init()`. *(C.41, C.42)*
- **Polymorphic class → suppress public copy/move** (avoid slicing); deep-copy via virtual
  `clone()`. *(C.67, C.130)*
- **Don't call virtual functions in constructors/destructors.** *(C.82)*
- **No `protected` data; uniform access level for non-`const` members.** *(C.133, C.134)*
- **Prefer concrete types over class hierarchies** unless you need polymorphism. *(C.10)*

### Functions, interfaces & parameter passing
- **In** params: by value if cheap (≈≤2–3 words), else `const&`. *(F.16)*
- **In-out**: `T&`. **Sink**: `X&&` + `std::move`. **Forward**: `TP&&` + `std::forward`. *(F.17, F.18, F.19)*
- **Prefer return values to out-parameters**; return a **named struct** for multiple outputs.
  *(F.20, F.21)*
- **Never return a pointer/reference to a local**; don't `return std::move(local)`; don't return
  `const T`; don't return `T&&`. *(F.43, F.48, F.49, F.45)*
- **Strong, precise types in interfaces** — no `void*`, bare-`int`-soup, or multiple `bool`s.
  *(I.4)*
- **Don't pass an array as a single pointer** — use `span` (or a container). *(I.13)*
- **`not_null<T>`** for pointers that must not be null. *(I.12)*
- **Use exceptions to signal failure** of a required task. *(I.10)*
- **Keep functions short and single-purpose**; keep argument count low (< 4). *(F.2, F.3, I.23)*
- **`noexcept`** on functions that must not throw (dtors, swaps, moves, low-level). *(F.6)*
- **Lambdas: capture by reference if used locally, by value if it escapes**; never `[=]` to grab
  members. *(F.52, F.53, F.54)*

### Expressions, statements, constants
- **Always initialize.** Prefer `{}` initialization (rejects narrowing). *(ES.20, ES.23)*
- **`const` by default** (objects, member functions, pointer/reference parameters);
  **`constexpr`** for compile-time values. *(Con.1, Con.2, Con.3, Con.5, ES.25)*
- **Avoid casts; if needed use a named cast**; never cast away `const`. *(ES.48, ES.49, ES.50)*
- **Avoid narrowing conversions** (`gsl::narrow[_cast]` if intended). *(ES.46)*
- **`nullptr`, not `0`/`NULL`.** *(ES.47)*
- **No magic constants** — name them or eliminate them. *(ES.45)*
- **Don't slice**; access polymorphic objects via pointer/reference. *(ES.63, C.145)*
- **Prefer range-`for`**; mark intentional `switch` fallthrough with `[[fallthrough]]`. *(ES.71, ES.78)*
- **Don't mix signed/unsigned; use signed for arithmetic, `gsl::index` for subscripts.** *(ES.100, ES.102, ES.107)*
- **`std::move` only to move to another scope** (not on plain returns). *(ES.56)*

### Error handling
- **RAII to prevent leaks; never throw while directly owning a raw resource.** *(E.6, E.13)*
- **Throw by value, catch by `const&`**; use **user-defined exception types**. *(E.15, E.14)*
- **Destructors / `swap` / deallocation / exception-copy must never fail.** *(E.16)*
- **Minimize explicit `try`/`catch`**; catch only where you can handle/add info. *(E.17, E.18)*
- **No dynamic exception specifications** — use `noexcept`. *(E.30)*

### Concurrency & performance
- **Avoid data races**; protect shared mutable data, or make it immutable / unshared. *(CP.2, CP.3)*
- **RAII locks — never plain `lock()`/`unlock()`**; name your lock guards; `scoped_lock` for
  multiple mutexes. *(CP.20, CP.44, CP.21)*
- **`volatile` is not for synchronization** — use `std::atomic`/`mutex`. *(CP.8)*
- **Prefer `jthread`; don't `detach()`**; think in tasks, not threads. *(CP.25, CP.26, CP.4)*
- **Don't optimize without reason/measurement**; simple, high-level code is often faster.
  *(Per.1, Per.2, Per.6, Per.4)*
- **Move work to compile time; minimize allocations; favor compact, predictable data layout.**
  *(Per.11, Per.14, Per.16–19)*

### Overarching principles
- **Express intent in code, not comments** — use named types/algorithms. *(P.1, P.3)*
- **Prefer the standard library** to hand-rolled code. *(P.13, ES.1)*
- **Prefer compile-time / static type safety** over run-time checks. *(P.4, P.5)*
- **Encapsulate messy/unsafe constructs** behind clean interfaces. *(P.11)*

---

## Routing table — when you need detail, open the matching file

Open the **single** reference file whose topic matches, then return to the task.

| If the question/code is about…                                                              | Read `references/…`                          |
|---------------------------------------------------------------------------------------------|----------------------------------------------|
| Ownership, RAII, smart pointers (incl. parameters), `new`/`delete`/`malloc`, leaks          | `resource-management.md`                     |
| `class` vs `struct`, special members, ctors/dtors, copy/move, `explicit`, hierarchies, slicing, `virtual`/`override`/`final`, `dynamic_cast`, getters/setters, `protected` data, `swap`/`==`/`hash` | `classes-and-hierarchies.md`                 |
| Parameter passing, returning values, `noexcept`, lambdas, interface design, strong typing, `not_null`/`span`/`zstring`, argument count | `functions-and-interfaces.md`                |
| Initialization, `const`/`constexpr`, `auto`, scope, casts, narrowing, `nullptr`, magic constants, `std::move` placement, loops, `switch`, signed/unsigned | `expressions-statements-and-constants.md`    |
| Exceptions, error strategy, leak-safety under exceptions, cleanup, exception-free code      | `error-handling.md`                          |
| Data races, locks, threads, `volatile`, optimization decisions, data layout                 | `concurrency-and-performance.md`             |
| High-level design principles, or templates / concepts / metaprogramming                     | `philosophy-and-templates.md`                |

If a task spans two areas (e.g. a class that owns a resource), it's fine to read two files — but
default to the one that's most central to the actual uncertainty.

---

## Audit mode (checking code or a codebase against best practices)

When the user asks you to review C++, check it against best practices/the Core Guidelines, or hand
you a file/repo to audit, switch into a systematic pass:

1. **Read the relevant reference file(s)** for the categories the code touches (ownership, classes,
   functions, expressions, error handling, concurrency). This is the case where loading references
   is expected — accuracy matters more than token economy here.
2. **Scan for the high-signal issues** first; these are the most common and most serious:
   - Resource leaks / manual `new`/`delete` / unclear ownership / raw owning pointers *(R.x, P.8)*
   - Missing or inconsistent special members (rule of zero/five), throwing dtors/moves *(C.20, C.21, C.36, C.66)*
   - Slicing, value-passing of polymorphic types, non-virtual base destructors *(ES.63, C.67, C.35)*
   - Parameter passing and ownership across interfaces; out-params that should be returns *(F.7, F.16–F.21, I.11)*
   - Uninitialized variables, C-style casts, casting away `const`, narrowing, `0`/`NULL` *(ES.20, ES.48, ES.50, ES.46, ES.47)*
   - Missing `const`-correctness *(Con.1–Con.3)*
   - Data races and manual `lock()`/`unlock()` *(CP.2, CP.20)*
3. **Report findings as**: location → the issue → the rule ID → a concrete suggested fix (ideally a
   short corrected snippet). Group by severity (correctness/safety first, then style/clarity).
4. **Don't flag everything mechanically.** Note exceptions where a "violation" is actually
   justified, and keep the signal-to-noise ratio high. Prioritize bugs and safety over cosmetics.
5. If the codebase can't be fully converted at once, frame fixes as **gradual adoption** — the
   Guidelines are explicitly designed to be introduced incrementally.

---

## Reference file format

Every reference file opens with a short scope note and a contents list, then has one entry per rule:

```
### <RuleID> — <short title>
**Why:** <one or two sentences of rationale>

// BAD: <what's wrong and the consequence>
<faithful bad example>

// GOOD: <the idiomatic fix>
<faithful good example>
```

Files larger than a screen include a table of contents at the top so you can jump to the rule you
need without reading the whole file.
