.LP
An Oberon module:
.IP
.nf
\f[B]MODULE\f[R] Stack;
  \f[I](* A bounded stack of integers. *)\f[R]

  \f[B]CONST\f[R]
    Max = 100;              \f[I](* capacity *)\f[R]
    Overflow = 1;           \f[I](* HALT code: too many pushes *)\f[R]

  \f[B]VAR\f[R]
    top: INTEGER;           \f[I](* items in use *)\f[R]
    items: \f[B]ARRAY\f[R] Max \f[B]OF\f[R] INTEGER;

  \f[B]PROCEDURE\f[R] Push*(x: INTEGER);
  \f[B]BEGIN\f[R]
    \f[B]IF\f[R] top = Max \f[B]THEN\f[R]
      HALT(Overflow)        \f[I](* it\(aqs full *)\f[R]
    \f[B]END\f[R];
    items[top] := x;        \f[I](* store it *)\f[R]
    INC(top)                \f[I](* and count it *)\f[R]
  \f[B]END\f[R] Push;

\f[B]BEGIN\f[R]
  top := 0                  \f[I](* empty at first *)\f[R]
\f[B]END\f[R] Stack.
.fi
.LP
A C header and function:
.IP
.nf
#define MAXNAME   32        \f[I]/* longest name */\f[R]
#define WWWWWWWWWWWW  64    \f[I]/* deliberately wide */\f[R]
#define DEPTH     8         \f[I]/* nesting */\f[R]

\f[B]struct\f[R] entry {
    \f[B]int\f[R]     kind;           \f[I]/* what it is */\f[R]
    \f[B]char\f[R]   *name;           \f[I]/* its name */\f[R]
    \f[B]long\f[R]    value;          \f[I]/* its value */\f[R]
};

\f[B]int\f[R] classify(\f[B]struct\f[R] entry *e)
{
    \f[B]switch\f[R] (e->kind) {
    \f[B]case\f[R] 0:  \f[B]return\f[R] \(aqa\(aq;    \f[I]/* plain */\f[R]
    \f[B]case\f[R] 1:  \f[B]return\f[R] \(aq\(dq\(aq;    \f[I]/* quoted */\f[R]
    \f[B]default\f[R]: \f[B]return\f[R] -1;     \f[I]/* none -- unknown */\f[R]
    }
}
.fi
