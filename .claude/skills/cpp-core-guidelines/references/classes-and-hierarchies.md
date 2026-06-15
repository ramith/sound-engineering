# Classes and class hierarchies (C)

Consult this file when uncertain about: `struct` vs `class`, the rule of zero/five, constructors,
destructors, copy/move semantics, `explicit`, member init order, comparison/`swap`/`hash`,
concrete types vs hierarchies, interfaces, `virtual`/`override`/`final`, slicing, `dynamic_cast`,
getters/setters, or `protected` data.

## Contents
- C.2 / C.8 `class` vs `struct`
- C.9 Minimize member exposure
- C.10 Prefer concrete types over hierarchies
- C.12 No `const`/reference members in copyable types
- C.13 Declare members in dependency order
- C.20 Rule of zero
- C.21 Rule of five
- C.22 Keep default operations consistent
- C.30 / C.31 / C.33 Destructors and owned resources
- C.35 / C.127 Base-class destructors
- C.36 / C.37 Destructors must not fail; make them `noexcept`
- C.41 / C.42 Constructors build fully-valid objects
- C.46 Single-argument constructors `explicit`
- C.47 Init in member-declaration order
- C.48 Prefer default member initializers
- C.49 Prefer initialization to assignment
- C.50 Factory function for "virtual behavior" during init
- C.62 / C.65 Self-assignment safety
- C.66 Move operations `noexcept`
- C.67 Polymorphic classes suppress public copy/move
- C.80 / C.81 `=default` / `=delete`
- C.82 No virtual calls in ctor/dtor
- C.83–C.86 `swap`, `==`, `hash`
- C.90 Use ctors/assignment, not `memset`/`memcpy`
- C.121 / I.25 Interfaces are pure abstract
- C.128 Exactly one of `virtual`/`override`/`final`
- C.131 Avoid trivial getters/setters
- C.132 No gratuitous `virtual`
- C.133 / C.134 Avoid `protected` data; uniform access level
- C.145 / C.146 Access polymorphic objects via pointer/reference; `dynamic_cast`

---

### C.2 / C.8 — `class` if there is an invariant; `struct` if members vary independently
**Why:** `class` signals "there is an invariant maintained by member functions"; `struct` signals
"a bunch of independent values". Using `class` whenever any member is non-public (C.8) keeps the
hidden parts obviously hidden.

```cpp
struct Pair {       // members vary independently -> struct
    string name;
    int volume;
};

class Date {        // has an invariant (valid date) -> class
public:
    Date(int yy, Month mm, char dd);  // validates and establishes the invariant
private:
    int y; Month m; char d;
};
```

---

### C.9 — Minimize exposure of members
**Why:** Encapsulation lets you change representation later and confines who can break an
invariant. If anyone can mutate the data, you can't find or trust the code that does.

---

### C.10 — Prefer concrete types over class hierarchies
**Why:** A concrete type is simpler, smaller, faster, stack-allocatable, and easier to reason
about. Pay for a hierarchy (indirection, allocation, virtual dispatch) only when you actually need
runtime polymorphism.

```cpp
class Point1 { int x, y; /* no virtuals */ };   // value type: stack, copy freely
// vs a hierarchy you must manipulate through pointers/clone() — only if you need polymorphism
```

---

### C.12 — Don't make data members `const` or references in a copyable/movable type
**Why:** `const` and reference members make a class copy-constructible but not copy-*assignable*
for subtle reasons, crippling its use. If a member must refer to something, use a pointer
(`gsl::not_null` if non-null).

```cpp
// BAD: "only-sort-of-copyable"
class bad { const int i; string& s; };
```

---

### C.13 — If member `B` uses member `A`, declare `A` before `B`
**Why:** Members are constructed in declaration order and destroyed in reverse. If `B` depends on
`A` but is declared first, `B` touches `A` before it exists (or after it's gone) — use-before-init
or use-after-free, even though the member-initializer list looks fine.

```cpp
// BAD: b constructed before a, but b{a} uses a; ~b uses a after a destroyed
class X { struct B { string* p; B(string& a):p{&a}{} ~B(){cout<<*p;} };
          B b; string a = "..."; public: X():b{a}{} };
```
```cpp
// GOOD: declare a before b
class X { struct B { string* p; B(string& a):p{&a}{} ~B(){cout<<*p;} };
          string a = "..."; B b; public: X():b{a}{} };
```

---

### C.20 — Rule of zero: if you can avoid defining default operations, do
**Why:** Members that manage themselves (string, vector, smart pointers) give you correct copy,
move, and destruction *for free*. The cleanest class declares none of the special members.

```cpp
struct Named_map {
public:
    explicit Named_map(const string& n) : name(n) {}
    // no copy/move/dtor declared — string and map supply correct ones
private:
    string name;
    map<int, int> rep;
};
```

---

### C.21 — Rule of five: if you declare/`=delete` any copy, move, or destructor, handle them all
**Why:** Copy, move, and destruction are a matched set with interrelated semantics. Declaring one
(even `=default`/`=delete`) suppresses or deletes others, silently turning moves into copies or
making a type move-only. So once you touch one, declare them all to state intent.

```cpp
// BAD: a destructor that deletes, but default copy -> double free
struct M2 { ~M2() { delete[] rep; } pair<int,int>* rep; };
```
```cpp
// GOOD: be explicit about every special member (mind the exact signatures)
class X {
public:
    virtual ~X() = default;
    X(const X&) = default;
    X& operator=(const X&) = default;
    X(X&&) noexcept = default;
    X& operator=(X&&) noexcept = default;
};
```
Better still: follow the rule of zero so you don't have to write any of them.

---

### C.22 — Make default operations consistent
**Why:** Copy and move construction/assignment must agree with each other and with the destructor.
A deep-copy constructor paired with a shallow-copy assignment is a guaranteed bug.

```cpp
// BAD: ctor deep-copies, assignment shallow-copies — inconsistent
class Silly {
    shared_ptr<Impl> p;
public:
    Silly(const Silly& a) : p(make_shared<Impl>()) { *p = *a.p; } // deep
    Silly& operator=(const Silly& a) { p = a.p; return *this; }   // shallow
};
```

---

### C.30 / C.31 / C.33 — Destructors and owned resources
**Why:** Define a destructor only when the class needs an action beyond what its members already
do (C.30) — don't hand-clear members that clean themselves. But every resource the class *owns*
must be released by its destructor (C.31), and an owning pointer member implies you need one (C.33).

```cpp
// BAD (C.30): default destructor already does all this, better and faster
class Foo { ~Foo() { s=""; i=0; vi.clear(); } string s; int i; vector<int> vi; };
```
```cpp
// GOOD (C.31): ifstream member closes the file automatically; no dtor needed
class X { ifstream f; };
// but a raw owning handle leaks:
class X2 { FILE* f; };  // BAD: who closes f? prefer a RAII wrapper or ifstream
```

---

### C.35 / C.127 — A base-class destructor is public+virtual, or protected+non-virtual
**Why:** Deleting a derived object through a base pointer with a non-virtual base destructor is
undefined behavior (and leaks the derived parts). Make it public+virtual to allow polymorphic
deletion, or protected+non-virtual to forbid it.

```cpp
// BAD: implicit public non-virtual dtor; deleting D via B* leaks D::s
struct Base { virtual void f(); };
struct D : Base { string s{"needs cleanup"}; ~D(); };
unique_ptr<Base> p = make_unique<D>();   // ~Base() runs, not ~D()
```
```cpp
struct Base { virtual ~Base() = default; virtual void f(); };  // GOOD
```

---

### C.36 / C.37 — A destructor must not fail; make it `noexcept`
**Why:** The standard library requires non-throwing destruction, and there is no good way to
recover if a destructor throws. A destructor is implicitly `noexcept`, but a single throwing member
poisons it — so declare destructors `noexcept` to keep that guarantee explicit. If a release truly
can't happen, treat it as a fatal design error (`terminate`).

```cpp
class X { public: ~X() noexcept; };
X::~X() noexcept { if (cannot_release_a_resource) terminate(); }
```

---

### C.41 / C.42 — A constructor creates a fully-valid object; throw if it can't
**Why:** Users assume a constructed object is usable. Two-phase init (`X x; x.init();`) invites
"use before init" crashes and leaves an invalid object lying around. If construction can't produce
a valid object, throw.

```cpp
// BAD: object exists but is unusable until init(); easy to call read() too early
class X1 { FILE* f; public: X1(){} void init(); void read(); };
```
```cpp
// GOOD: constructor establishes the invariant or throws
class X2 {
    FILE* f;
public:
    X2(const string& name) : f{fopen(name.c_str(),"r")} {
        if (!f) throw runtime_error{"could not open " + name};
    }
    void read();
};
```

---

### C.46 — By default, declare single-argument constructors `explicit`
**Why:** A non-`explicit` single-arg constructor is an implicit conversion, which produces
surprises. Add `explicit` unless you genuinely want the implicit conversion (e.g. `Complex` from
`double`). Copy/move constructors are *not* made `explicit`.

```cpp
class String { public: String(int); };   // BAD
String s = 10;   // surprise: a 10-char string
```
```cpp
class String { public: explicit String(int); };  // GOOD
```

---

### C.47 — Define and initialize data members in member-declaration order
**Why:** Members are initialized in declaration order regardless of the order in the init list.
A mismatched init list reads misleadingly and can use a not-yet-initialized member.

```cpp
// BAD: initializer order suggests m2 then m1, but m1 is initialized first (from a stale x)
class Foo { int m1; int m2; public: Foo(int x):m2{x}, m1{++x}{} };
```

---

### C.48 — Prefer default member initializers to constructor member initializers for constants
**Why:** Default member initializers state the shared default once, avoid repetition across
constructors, and prevent "forgot to initialize the new member" bugs.

```cpp
// BAD: j uninitialized in one ctor; s defaults differ between ctors — bug or intent?
class X { int i; string s; int j;
public: X():i{666},s{"qqq"}{} X(int ii):i{ii}{} };
```
```cpp
// GOOD
class X2 { int i{666}; string s{"qqq"}; int j{0};
public: X2()=default; X2(int ii):i{ii}{} };
```

---

### C.49 — Prefer initialization to assignment in constructors
**Why:** Initialization in the member-init list is clearer and more efficient (no default-construct
then overwrite) and prevents use-before-set.

```cpp
class B { string s1; public: B(const char* p){ s1 = p; } };       // BAD: default + assign
class A { string s1; public: A(czstring p) : s1{p} {} };          // GOOD: direct init
```

---

### C.50 — Use a factory function if you need "virtual behavior" during initialization
**Why:** Calling a virtual from a constructor does *not* dispatch to the derived override (C.82).
If the base needs derived behavior at creation, run it after construction via a factory.

```cpp
class B {
protected:
    class Token {};
public:
    explicit B(Token) {}
    virtual void f() = 0;
    template<class T> static shared_ptr<T> create() {
        auto p = make_shared<T>(typename T::Token{});
        p->post_initialize();   // virtual dispatch now safe — object fully constructed
        return p;
    }
protected:
    virtual void post_initialize() { f(); }
};
```

---

### C.62 / C.65 — Make copy and move assignment safe for self-assignment
**Why:** If `x = x` corrupts `x`, you get surprising bugs (often leaks). Many implementations are
naturally self-safe (assign members that are themselves self-safe, or use copy-and-swap). Self-move
is rare directly but happens via `std::swap`, so guard move assignment.

```cpp
Foo& Foo::operator=(Foo&& a) noexcept {
    if (this == &a) return *this;       // guard self-move
    s = std::move(a.s); i = a.i;
    return *this;
}
```

---

### C.66 — Make move operations `noexcept`
**Why:** Throwing moves violate reasonable assumptions and prevent the library from using the move
(e.g. `vector` reallocation falls back to copying). A correct move just steals pointers — it can't
throw.

```cpp
// BAD: "move" delegates to copy, which allocates and can throw
class Vector2 { public: Vector2(Vector2&& a) noexcept { *this = a; } /* ... */ };
```
```cpp
// GOOD
class Vector {
public:
    Vector(Vector&& a) noexcept : elem{a.elem}, sz{a.sz} { a.elem=nullptr; a.sz=0; }
};
```

---

### C.67 — A polymorphic class should suppress public copy/move
**Why:** Passing a polymorphic object by value slices it (only the base part copies; polymorphic
behavior is lost). If the class has no data, `=delete` copy/move; otherwise make them `protected`.
Provide a virtual `clone()` (C.130) if you need deep copies.

```cpp
class B {  // GOOD: copying is rejected at compile time
public:
    B() = default;
    B(const B&) = delete;
    B& operator=(const B&) = delete;
    virtual char m() { return 'B'; }
};
```

---

### C.80 / C.81 — `=default` to state default semantics; `=delete` to disable
**Why:** The compiler implements the special members better than you can; write `=default` to opt
in explicitly (e.g. when a destructor forces you to declare the others). Write `=delete` to remove
an operation rather than leaving it undeclared or writing a buggy stub.

```cpp
class Tracer {           // dtor is needed, so the rest are =default
    string message;
public:
    Tracer(const string& m);
    ~Tracer();
    Tracer(const Tracer&) = default;
    Tracer& operator=(const Tracer&) = default;
    Tracer(Tracer&&) noexcept = default;
    Tracer& operator=(Tracer&&) noexcept = default;
};
```

---

### C.82 — Don't call virtual functions in constructors and destructors
**Why:** During construction/destruction the dynamic type is the class under construction, so the
call resolves to *this* class's version, not a derived override — confusing, and calling a pure
virtual this way is undefined behavior. Use a factory (C.50) for "virtual behavior during init".

```cpp
class B { public: B(){ f(); } virtual void f() = 0; };  // BAD: UB — pure virtual call
```

---

### C.83 / C.84 / C.85 — Provide a `noexcept` `swap` for value-like types
**Why:** `swap` underpins many idioms (move-around, strong-guarantee assignment) and is assumed
never to fail; the standard library breaks if a `swap` throws.

```cpp
class Foo {
public:
    void swap(Foo& rhs) noexcept { m1.swap(rhs.m1); std::swap(m2, rhs.m2); }
private:
    Bar m1; int m2;
};
inline void swap(Foo& a, Foo& b) { a.swap(b); }   // non-member for ADL
```

---

### C.86 — Make `==` symmetric and `noexcept`
**Why:** Asymmetric comparison (member `operator==` accepts conversions for the right operand only)
surprises and causes bugs. Define comparisons as non-member functions so both operands convert the
same way. (Applies to `!=`, `<`, `<=`, `>`, `>=`.)

```cpp
// BAD: member op== — left operand isn't converted like the right
class B { string name; int number; bool operator==(const B&) const; };
```
```cpp
// GOOD: free function, symmetric
bool operator==(const X& a, const X& b) noexcept { return a.name==b.name && a.number==b.number; }
```

---

### C.90 — Rely on constructors and assignment, not `memset`/`memcpy`
**Why:** The way to construct/copy an object is its constructor/assignment, which preserve
invariants. `memset`/`memcpy` on a non-trivially-copyable type is undefined behavior — it overwrites
vtables and corrupts data.

```cpp
// BAD: clobbers the vtable and the shared_ptr
void init(derived& a) { memset(&a, 0, sizeof(derived)); }
```

---

### C.121 / I.25 — A base class used as an interface should be pure abstract (no data)
**Why:** A data-free interface is far more stable: derived classes aren't forced to carry/compute
unused state, and adding data to a base forces recompilation of the whole hierarchy.

```cpp
// BAD: interface loaded with data every Shape must carry/compute
class Shape { public: Point center() const { return c; } virtual void draw() const;
              Point c; vector<Point> outline; Color col; };
```
```cpp
// GOOD: pure interface
class Shape {
public:
    virtual Point center() const = 0;
    virtual void draw() const = 0;
    virtual ~Shape() = default;
};
```

---

### C.128 — Virtual functions specify exactly one of `virtual`, `override`, or `final`
**Why:** `virtual` = "new virtual function"; `override` = "overrides a base virtual"; `final` =
"final override". Writing `override` (not bare same-signature) makes the compiler catch silent
mismatches that create accidental hides or new overloads. Writing more than one is redundant.

```cpp
// BAD: silent hiding / no override checking
struct D : B { void f1(int); void f3(double); };
```
```cpp
// GOOD: compiler verifies these really override
struct Better : B { void f1(int) override; void f3(double) override; };
```

---

### C.131 — Avoid trivial getters and setters
**Why:** A getter/setter that just reads/writes a member with no added semantics is noise — the
member might as well be public. If there's no invariant, prefer a `struct`.

```cpp
class Point { int x, y; public: int get_x() const; void set_x(int); /* ... */ }; // BAD: verbose
struct Point { int x{0}; int y{0}; };                                            // GOOD
```

---

### C.132 — Don't make a function `virtual` without reason
**Why:** Gratuitous `virtual` costs runtime and object size, opens the function to mistaken
overrides, and forces code replication in templated hierarchies.

```cpp
template<class T>
class Vector { public: virtual int size() const { return sz; } /* ... */ }; // BAD: why virtual?
```

---

### C.133 / C.134 — Avoid `protected` data; give non-`const` members the same access level
**Why:** `protected` data is effectively global to all current and future derived classes, so no
invariant can be enforced and any change to representation becomes infeasible. Mixed access for
non-`const` members means the class is confused about whether it maintains an invariant. Make data
`private` (invariant) or `public` (plain aggregate, use `struct`).

```cpp
// BAD: every derived Shape can corrupt these, forever
class Shape { protected: Color fill_color; Color edge_color; Style st; };
```

---

### C.145 / C.146 — Access polymorphic objects via pointer/reference; use `dynamic_cast` for navigation
**Why:** Copying a polymorphic object by value slices it (C.145). When hierarchy navigation is
unavoidable, `dynamic_cast` is checked at runtime; `static_cast` down a hierarchy is unchecked and
can reinterpret an object as an unrelated type.

```cpp
void use(B b) { D d; B b2 = d; }   // BAD: slices d
```
```cpp
void user(B* pb) {                 // GOOD: checked navigation
    if (D* pd = dynamic_cast<D*>(pb)) { /* use D */ } else { /* use B */ }
}
```
Prefer a virtual function to casting when you can (C.153); `dynamic_cast` to a *reference* throws on
failure (use when failure is an error, C.147), to a *pointer* returns null (use when failure is a
valid alternative, C.148).
