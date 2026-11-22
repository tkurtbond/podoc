---
code-style: proportional
---

An Oberon module:

``` oberon
MODULE Stack;
  (* A bounded stack of integers. *)

  CONST
    Max = 100;              (* capacity *)
    Overflow = 1;           (* HALT code: too many pushes *)

  VAR
    top: INTEGER;           (* items in use *)
    items: ARRAY Max OF INTEGER;

  PROCEDURE Push*(x: INTEGER);
  BEGIN
    IF top = Max THEN
      HALT(Overflow)        (* it's full *)
    END;
    items[top] := x;        (* store it *)
    INC(top)                (* and count it *)
  END Push;

BEGIN
  top := 0                  (* empty at first *)
END Stack.
```

A C header and function:

``` c
#define MAXNAME   32        /* longest name */
#define WWWWWWWWWWWW  64    /* deliberately wide */
#define DEPTH     8         /* nesting */

struct entry {
    int     kind;           /* what it is */
    char   *name;           /* its name */
    long    value;          /* its value */
};

int classify(struct entry *e)
{
    switch (e->kind) {
    case 0:  return 'a';    /* plain */
    case 1:  return '"';    /* quoted */
    default: return -1;     /* none -- unknown */
    }
}
```
