.LP
An Oberon module:
.IP
.nf
.if !r PdCodeCol .nr PdCodeCol 0.5m
.if !r PdCodeGap .nr PdCodeGap 1m
.nr PdG1 28*\n[PdCodeCol]
.nr PdG1 \n[PdG1]>?(\w'\&\h'|4u*\n[PdCodeCol]u'Max = 100;'u+\n[PdCodeGap]u)
.nr PdG1 \n[PdG1]>?(\w'\&\h'|4u*\n[PdCodeCol]u'Overflow = 1;'u+\n[PdCodeGap]u)
.nr PdG2 28*\n[PdCodeCol]
.nr PdG2 \n[PdG2]>?(\w'\&\h'|4u*\n[PdCodeCol]u'top: INTEGER;'u+\n[PdCodeGap]u)
.nr PdG3 28*\n[PdCodeCol]
.nr PdG3 \n[PdG3]>?(\w'\&\h'|6u*\n[PdCodeCol]u'HALT(Overflow)'u+\n[PdCodeGap]u)
.nr PdG4 28*\n[PdCodeCol]
.nr PdG4 \n[PdG4]>?(\w'\&\h'|4u*\n[PdCodeCol]u'items[top] := x;'u+\n[PdCodeGap]u)
.nr PdG4 \n[PdG4]>?(\w'\&\h'|4u*\n[PdCodeCol]u'INC(top)'u+\n[PdCodeGap]u)
.nr PdG5 28*\n[PdCodeCol]
.nr PdG5 \n[PdG5]>?(\w'\&\h'|2u*\n[PdCodeCol]u'top := 0'u+\n[PdCodeGap]u)
\f[B]MODULE\f[R] Stack;
\h'|2u*\n[PdCodeCol]u'\f[I](* A bounded stack of integers. *)\f[R]

\h'|2u*\n[PdCodeCol]u'\f[B]CONST\f[R]
\h'|4u*\n[PdCodeCol]u'Max = 100;\h'|\n[PdG1]u'\f[I](* capacity *)\f[R]
\h'|4u*\n[PdCodeCol]u'Overflow = 1;\h'|\n[PdG1]u'\f[I](* HALT code: too many pushes *)\f[R]

\h'|2u*\n[PdCodeCol]u'\f[B]VAR\f[R]
\h'|4u*\n[PdCodeCol]u'top: INTEGER;\h'|\n[PdG2]u'\f[I](* items in use *)\f[R]
\h'|4u*\n[PdCodeCol]u'items: \f[B]ARRAY\f[R] Max \f[B]OF\f[R] INTEGER;

\h'|2u*\n[PdCodeCol]u'\f[B]PROCEDURE\f[R] Push*(x: INTEGER);
\h'|2u*\n[PdCodeCol]u'\f[B]BEGIN\f[R]
\h'|4u*\n[PdCodeCol]u'\f[B]IF\f[R] top = Max \f[B]THEN\f[R]
\h'|6u*\n[PdCodeCol]u'HALT(Overflow)\h'|\n[PdG3]u'\f[I](* it\(aqs full *)\f[R]
\h'|4u*\n[PdCodeCol]u'\f[B]END\f[R];
\h'|4u*\n[PdCodeCol]u'items[top] := x;\h'|\n[PdG4]u'\f[I](* store it *)\f[R]
\h'|4u*\n[PdCodeCol]u'INC(top)\h'|\n[PdG4]u'\f[I](* and count it *)\f[R]
\h'|2u*\n[PdCodeCol]u'\f[B]END\f[R] Push;

\f[B]BEGIN\f[R]
\h'|2u*\n[PdCodeCol]u'top := 0\h'|\n[PdG5]u'\f[I](* empty at first *)\f[R]
\f[B]END\f[R] Stack.
.fi
.LP
A C header and function:
.IP
.nf
.if !r PdCodeCol .nr PdCodeCol 0.5m
.if !r PdCodeGap .nr PdCodeGap 1m
.nr PdG1 11*\n[PdCodeCol]
.nr PdG1 \n[PdG1]>?(\w'\&\h'|4u*\n[PdCodeCol]u'\f[B]char\f[R]'u+\n[PdCodeGap]u)
.nr PdG2 12*\n[PdCodeCol]
.nr PdG2 \n[PdG2]>?(\w'\&\h'|4u*\n[PdCodeCol]u'\f[B]int\f[R]'u+\n[PdCodeGap]u)
.nr PdG3 12*\n[PdCodeCol]
.nr PdG3 \n[PdG3]>?(\w'\&\h'|4u*\n[PdCodeCol]u'\f[B]long\f[R]'u+\n[PdCodeGap]u)
.nr PdG4 13*\n[PdCodeCol]
.nr PdG4 \n[PdG4]>?(\w'\&\h'|4u*\n[PdCodeCol]u'\f[B]case\f[R] 0:'u+\n[PdCodeGap]u)
.nr PdG4 \n[PdG4]>?(\w'\&\h'|4u*\n[PdCodeCol]u'\f[B]case\f[R] 1:'u+\n[PdCodeGap]u)
.nr PdG5 18*\n[PdCodeCol]
.nr PdG5 \n[PdG5]>?(\w'\&#define MAXNAME'u+\n[PdCodeGap]u)
.nr PdG6 18*\n[PdCodeCol]
.nr PdG6 \n[PdG6]>?(\w'\&#define DEPTH'u+\n[PdCodeGap]u)
.nr PdG7 22*\n[PdCodeCol]
.nr PdG7 \n[PdG7]>?(\w'\&#define WWWWWWWWWWWW'u+\n[PdCodeGap]u)
.nr PdG8 28*\n[PdCodeCol]
.nr PdG8 \n[PdG8]>?(\w'\&#define MAXNAME\h'|\n[PdG5]u'32'u+\n[PdCodeGap]u)
.nr PdG8 \n[PdG8]>?(\w'\&#define WWWWWWWWWWWW\h'|\n[PdG7]u'64'u+\n[PdCodeGap]u)
.nr PdG8 \n[PdG8]>?(\w'\&#define DEPTH\h'|\n[PdG6]u'8'u+\n[PdCodeGap]u)
.nr PdG9 28*\n[PdCodeCol]
.nr PdG9 \n[PdG9]>?(\w'\&\h'|4u*\n[PdCodeCol]u'\f[B]int\f[R]\h'|\n[PdG2]u'kind;'u+\n[PdCodeGap]u)
.nr PdG9 \n[PdG9]>?(\w'\&\h'|4u*\n[PdCodeCol]u'\f[B]char\f[R]\h'|\n[PdG1]u'*name;'u+\n[PdCodeGap]u)
.nr PdG9 \n[PdG9]>?(\w'\&\h'|4u*\n[PdCodeCol]u'\f[B]long\f[R]\h'|\n[PdG3]u'value;'u+\n[PdCodeGap]u)
.nr PdG10 28*\n[PdCodeCol]
.nr PdG10 \n[PdG10]>?(\w'\&\h'|4u*\n[PdCodeCol]u'\f[B]case\f[R] 0:\h'|\n[PdG4]u'\f[B]return\f[R] \(aqa\(aq;'u+\n[PdCodeGap]u)
.nr PdG10 \n[PdG10]>?(\w'\&\h'|4u*\n[PdCodeCol]u'\f[B]case\f[R] 1:\h'|\n[PdG4]u'\f[B]return\f[R] \(aq\(dq\(aq;'u+\n[PdCodeGap]u)
.nr PdG10 \n[PdG10]>?(\w'\&\h'|4u*\n[PdCodeCol]u'\f[B]default\f[R]: \f[B]return\f[R] -1;'u+\n[PdCodeGap]u)
#define MAXNAME\h'|\n[PdG5]u'32\h'|\n[PdG8]u'\f[I]/* longest name */\f[R]
#define WWWWWWWWWWWW\h'|\n[PdG7]u'64\h'|\n[PdG8]u'\f[I]/* deliberately wide */\f[R]
#define DEPTH\h'|\n[PdG6]u'8\h'|\n[PdG8]u'\f[I]/* nesting */\f[R]

\f[B]struct\f[R] entry {
\h'|4u*\n[PdCodeCol]u'\f[B]int\f[R]\h'|\n[PdG2]u'kind;\h'|\n[PdG9]u'\f[I]/* what it is */\f[R]
\h'|4u*\n[PdCodeCol]u'\f[B]char\f[R]\h'|\n[PdG1]u'*name;\h'|\n[PdG9]u'\f[I]/* its name */\f[R]
\h'|4u*\n[PdCodeCol]u'\f[B]long\f[R]\h'|\n[PdG3]u'value;\h'|\n[PdG9]u'\f[I]/* its value */\f[R]
};

\f[B]int\f[R] classify(\f[B]struct\f[R] entry *e)
{
\h'|4u*\n[PdCodeCol]u'\f[B]switch\f[R] (e->kind) {
\h'|4u*\n[PdCodeCol]u'\f[B]case\f[R] 0:\h'|\n[PdG4]u'\f[B]return\f[R] \(aqa\(aq;\h'|\n[PdG10]u'\f[I]/* plain */\f[R]
\h'|4u*\n[PdCodeCol]u'\f[B]case\f[R] 1:\h'|\n[PdG4]u'\f[B]return\f[R] \(aq\(dq\(aq;\h'|\n[PdG10]u'\f[I]/* quoted */\f[R]
\h'|4u*\n[PdCodeCol]u'\f[B]default\f[R]: \f[B]return\f[R] -1;\h'|\n[PdG10]u'\f[I]/* none -- unknown */\f[R]
\h'|4u*\n[PdCodeCol]u'}
}
.fi
