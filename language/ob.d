// just docs: Live Functions
/++





$(B Experimental, Subject to Change, use `-preview=dip1021` to activate)

$(H2 $(ID ownership) Ownership)

If a memory object has only one pointer to it, that pointer is the $(I owner)
of the memory object. With the single owner, it becomes straightforward to
manage the memory for the object. It also becomes trivial to synchronize access
to that memory object among multiple threads, because it can only be accessed
by the thread that controls that single pointer.


This can be generalized to a graph of memory objects interconnected by pointers,
where only a single pointer connects to that graph from elsewhere. That single
pointer becomes the $(I owner) of all the memory objects in that graph.


When the owner of the graph is no longer needed, then the graph of memory
objects it points to is no longer needed and can be safely disposed of. If the owner
itself is no longer in use (i.e. is no longer $(I live)) and the owned memory
objects are not disposed of, an error can be diagnosed.


Hence, the following errors can be statically detected:


---
int* allocate();    // allocate a memory object
void release(int*); // deallocate a memory object

@live void test()
{
    auto p = allocate();
}   // error: p is not disposed of

@live void test()
{
    auto p = allocate();
    release(p);
    release(p); // error: p was already disposed of
}

@live void test()
{
    int* p = void;
    release(p); // error, p does not have a defined value
}

@live void test()
{
    auto p = allocate();
    p = allocate(); // error: p was not disposed of
    release(p);
}

---

Functions with the `@live` attribute enable diagnosing these sorts of errors by
tracking the status of owner pointers.



$(H2 $(ID ob) Borrowing)

Tracking the ownership status of a pointer can be safely extended by adding the
capability of temporarilly $(I borrowing) ownership of a pointer from the $(I owner).
The $(I owner) can no longer use the pointer as long as the $(I borrower) is still
using the pointer value (i.e. it is $(I live)). Once the $(I borrower) is no longer
$(I live), the $(I owner) can resume using it. Only one $(I borrower) can be live
at any point.


Multiple $(I borrower) pointers can simultaneously exist if all of them are
pointers to read only (`const` or `immutable`) data, i.e. none of them can modify the memory
object(s) pointed to.


This is collectively called an $(I Ownership/Borrowing) system. It can be stated as:


<blockquote>At any point in the program, for each memory object,
there is exactly one live mutable pointer to it or all the live pointers to
it are read-only.</blockquote>


$(H2 $(ID live) `@live` attribute)

Function declarations annotated with the `@live` attribute are checked for compliance with
the Ownership/Borrowing rules. The checks are run after other semantic processing is complete.
The checking does not influence code generation.


Whether a pointer is allocated memory using the GC or some other
storage allocator is immaterial to OB, they are not distinguished and are
handled identically.


Class references are assumed to be allocated using either the GC or are allocated
on the stack as `scope` classes, and are not tracked.


If `@live` functions
call non-`@live` functions, those called functions are expected to present
an `@live` compatible interface, although it is not checked.
if non-`@live` functions call `@live` functions, arguments passed are
expected to follow `@live` conventions.


It will not detect attempts to dereference `null` pointers or possibly
`null` pointers. This is unworkable because there is no current method
of annotating a type as a non-`null` pointer.


$(H3 $(ID tracked) Tracked Pointers)

The only pointers that are tracked are those declared in the `@live` function
as `this`, function parameters or local variables. Variables from other
functions are not tracked, even `@live` ones, as the analysis of interactions
with other functions depends
entirely on that function signature, not its internals.
Parameters that are `const` are not tracked.



$(H3 $(ID state) Pointer States)

Each tracked pointer is in one of the following states:


$(DL $(DT Undefined)

$(DD The pointer is in an invalid state. Dereferencing such a pointer is
an error.)

$(DT Owner)

$(DD The owner is the sole pointer to a memory object graph.
An Owner pointer normally does not have a `scope` attribute.
If a pointer with the `scope` attribute is initialized
with an expression not derived from a tracked pointer, it is an Owner.

If an Owner pointer is assigned to another Owner pointer, the
former enters the Undefined state.

---
void consume(int* o); // o is owner

@live int* f(int* p) // p is owner
{
    writeln(*p);
    // transfer ownership to `consume`
    consume(p);
    // p is now undefined
    //writeln(*p); // error

    int* q = new int; // q is owner
    writeln(*q);
    p = q; // transfer ownership
    // q is now undefined
    //writeln(*q); // error
    writeln(*p);
    return p;
}

---
)

$(DT Borrowed)

$(DD A Borrowed pointer is one that temporarily becomes the sole live pointer
to a memory object graph. It enters that state via assignment
from an owner pointer or another borrowed pointer, and stays in that state
until its last use.

A Borrowed pointer must be `scope` and must
be a pointer to mutable.
A mutable `scope` pointer function parameter is a Borrowed pointer.

---
void consume(int* o); // o is owner
void borrow(scope int* b); // b is borrowed

@live void g(scope int* p) // p is borrowed
{
    //consume(p); // error, p is not owner
    borrow(p);

    // lend p to q
    int* q = p; // q is inferred as scope
    // &lt;-- using p here would end q's lifetime
    writeln(*q);
    // lifetime of q ends before p is used
    writeln(*p); // OK
}

---
)

$(DT Readonly)

$(DD A Readonly pointer acquires its value from an Owner or Borrowed pointer.
While the Readonly pointer is live, only Readonly pointers can
be acquired from that Owner.
A Readonly pointer must be `scope` and also
must not be a pointer to mutable.

---
@live void h(scope int* p)
{
    // acquire 2 read only pointers
    const q = p;
    const r = q;
    // &lt;-- borrowing or using p here would end q and r's lifetime

    // both q and r are live
    writeln(*q);
    writeln(*r);
    // using p ends all its read only pointer lifetimes
    writeln(*p);
    //writeln(*q); // error
}

---
)
)

$(H3 $(ID lifetime) Lifetimes)

The lifetime of a Borrowed or Readonly pointer value starts when it is
assigned a value from an Owner or another Borrowed pointer, and ends at
the last read of that value.


This is also known as $(I Non-Lexical Lifetimes).



$(H3 $(ID transition) Pointer State Transitions)

A pointer changes its state when one of these operations is done to it:


$(LIST
* storage is allocated for it (such as a local variable on the stack),
which places the pointer in the Undefined state

* initialization (treated as assignment)

* assignment - the source and target pointers change state based on what
states they are in and their types and storage classes

* passed to an `out` function parameter (changes state after the function returns),
treated the same as initialization

* passed by `ref` to a function parameter, treated as an assignment to a Borrow or a Readonly
depending on the storage class and type of the parameter

* returned from a function

* it is passed by value to a function parameter, which is
treated as an assignment to that parameter.

* it is implicitly passed by ref as a closure variable to a nested function

* the address of the pointer is taken, which is treated as assignment to whoever
receives the address

* the address of any part of the memory object graph is taken, which is
treated as assignment to whoever receives that address

* a pointer value is read from any part of the memory object graph,
which is treated as assignment to whoever receives that pointer

* merging of control flow reconciles the state of each variable based on the
states they have from each edge

)

$(H3 $(ID borrower) Borrowers can be Owners)

Borrowers are considered Owners if they are initialized from other than
a pointer.


---
@live void uhoh()
{
    scope p = malloc();  // p is considered an Owner
    scope const pc = malloc(); // pc is not considered an Owner
} // dangling pointer pc is not detected on exit


---

$(H3 $(ID exception) Exceptions)

The analysis assumes no exceptions are thrown.


---
@live void leaky()
{
    auto p = malloc();
    pitcher();  // throws exception, p leaks
    free(p);
}

---

One solution is to use `scope(exit)`:


---
@live void waterTight()
{
    auto p = malloc();
    scope(exit) free(p);
    pitcher();
}

---

or use RAII objects or call only `nothrow` functions.


$(H3 $(ID lazy) Lazy Parameters)

Lazy parameters are not considered.


$(H3 $(ID mempool) Mixing Memory Pools)

Conflation of different memory pools:


---
void* xmalloc(size_t);
void xfree(void*);

void* ymalloc(size_t);
void yfree(void*);

auto p = xmalloc(20);
yfree(p);  // should call xfree() instead

---
is not detected.


This can be mitigated by using type-specific pools:


---
U* umalloc();
void ufree(U*);

V* vmalloc();
void vfree(V*);

auto p = umalloc();
vfree(p);  // type mismatch

---

and perhaps disabling implicit conversions to `void*` in `@live` functions.


$(H3 $(ID vargs) Variadic Function Arguments)

Arguments to variadic functions (such as `printf`) are considered to be consumed.



$(H2 $(ID references) References)

$(NUMBERED_LIST
* $(LINK2 https://bartoszmilewski.com/2009/06/02/race-free-multithreading-ownership, Race-free Multithreading: Ownership)

)


importc, ImportC, windows, Windows Programming




Link_References:
	ACC = Associated C Compiler
+/
module ob.dd;