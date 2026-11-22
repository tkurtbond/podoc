.LP
An Oberon module:
.IP
.nf
.if !r PdCodeCol .nr PdCodeCol 0.5m
.if !r PdCodeGap .nr PdCodeGap 1m
\f[B]MODULE\f[R] Stack;
\h'|2u*\n[PdCodeCol]u'\f[I](* A bounded stack of integers. *)\f[R]

\h'|2u*\n[PdCodeCol]u'\f[B]CONST\f[R]
\h'|4u*\n[PdCodeCol]u'Max = 100;\h'(28u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'\f[I](* capacity *)\f[R]
\h'|4u*\n[PdCodeCol]u'Overflow = 1;\h'(28u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'\f[I](* HALT code: too many pushes *)\f[R]

\h'|2u*\n[PdCodeCol]u'\f[B]VAR\f[R]
\h'|4u*\n[PdCodeCol]u'top: INTEGER;\h'(28u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'\f[I](* items in use *)\f[R]
\h'|4u*\n[PdCodeCol]u'items: \f[B]ARRAY\f[R] Max \f[B]OF\f[R] INTEGER;

\h'|2u*\n[PdCodeCol]u'\f[B]PROCEDURE\f[R] Push*(x: INTEGER);
\h'|2u*\n[PdCodeCol]u'\f[B]BEGIN\f[R]
\h'|4u*\n[PdCodeCol]u'\f[B]IF\f[R] top = Max \f[B]THEN\f[R]
\h'|6u*\n[PdCodeCol]u'HALT(Overflow)\h'(28u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'\f[I](* it\(aqs full *)\f[R]
\h'|4u*\n[PdCodeCol]u'\f[B]END\f[R];
\h'|4u*\n[PdCodeCol]u'items[top] := x;\h'(28u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'\f[I](* store it *)\f[R]
\h'|4u*\n[PdCodeCol]u'INC(top)\h'(28u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'\f[I](* and count it *)\f[R]
\h'|2u*\n[PdCodeCol]u'\f[B]END\f[R] Push;

\f[B]BEGIN\f[R]
\h'|2u*\n[PdCodeCol]u'top := 0\h'(28u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'\f[I](* empty at first *)\f[R]
\f[B]END\f[R] Stack.
.fi
.LP
A C header and function:
.IP
.nf
.if !r PdCodeCol .nr PdCodeCol 0.5m
.if !r PdCodeGap .nr PdCodeGap 1m
#define MAXNAME\h'(18u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'32\h'(28u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'\f[I]/* longest name */\f[R]
#define WWWWWWWWWWWW\h'(22u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'64\h'(28u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'\f[I]/* deliberately wide */\f[R]
#define DEPTH\h'(18u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'8\h'(28u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'\f[I]/* nesting */\f[R]

\f[B]struct\f[R] entry {
\h'|4u*\n[PdCodeCol]u'\f[B]int\f[R]\h'(12u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'kind;\h'(28u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'\f[I]/* what it is */\f[R]
\h'|4u*\n[PdCodeCol]u'\f[B]char\f[R]\h'(11u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'*name;\h'(28u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'\f[I]/* its name */\f[R]
\h'|4u*\n[PdCodeCol]u'\f[B]long\f[R]\h'(12u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'value;\h'(28u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'\f[I]/* its value */\f[R]
};

\f[B]int\f[R] classify(\f[B]struct\f[R] entry *e)
{
\h'|4u*\n[PdCodeCol]u'\f[B]switch\f[R] (e->kind) {
\h'|4u*\n[PdCodeCol]u'\f[B]case\f[R] 0:\h'(13u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'\f[B]return\f[R] \(aqa\(aq;\h'(28u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'\f[I]/* plain */\f[R]
\h'|4u*\n[PdCodeCol]u'\f[B]case\f[R] 1:\h'(13u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'\f[B]return\f[R] \(aq\(dq\(aq;\h'(28u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'\f[I]/* quoted */\f[R]
\h'|4u*\n[PdCodeCol]u'\f[B]default\f[R]: \f[B]return\f[R] -1;\h'(28u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'\f[I]/* none -- unknown */\f[R]
\h'|4u*\n[PdCodeCol]u'}
}
.fi
