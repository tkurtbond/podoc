.SH 1
A heading
that is
quite long
and would
wrap if
headings
were wrapped
at all
.LP
Averyveryveryverylongwordthatisdefinitelywiderthanthecolumnwidth
and more
words after
it.
.PP
See
https://example.com/a/very/long/path/that/goes/on/and/on/forever/index.html
here.
.PP
日本語の文章はとても長くて、行の幅を超えてしまうかもしれません。これは試験です。한국어
문장도
있습니다.
.IP \(bu 3
a list item
with enough
words in it
that it will
need to wrap
onto a
second line
.RS 3
.IP \(bu 3
nested item
also with
enough words
in it that
it will need
to wrap
around
.RE
.IP " 1." 4
ordered item
with enough
words in it
that it will
need to wrap
onto another
line and 2.
here, and
also 1.
there, and -
dash + plus
* star >
quote words
words.
.QS
.LP
A block
quote with
enough words
in it that
it will need
to wrap onto
a second
line.
> nested
quote with
words in it
that will
need to wrap
again and
again and
again.
.QE
.IP "\f[B]Term with words\f[R]" 3
Definition
with enough
words in it
that it will
need to wrap
onto a
second line.
.RS 3
.RE
.LP
Text with a
note.\**
.FS
The note has
enough words
in it that
it will need
to wrap onto
a second
line too.
.FE
More text
after the
note so that
the line
wraps
somewhere.
.PP
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
lw(35.0n) lw(35.0n).
T{
a
T}	T{
b
T}
_
T{
.nr LL 35.0n
some long
text in a
pipe table
cell that is
long
T}	T{
.nr LL 35.0n
another long
cell text
here that is
long too
T}
.TE
.nr LL \n[LLold]
.ad
.LP
Line with a
hard
.br
break and
\f[I]emphasis
that is long
enough to
wrap across
lines
here\f[R]
and
\f[CR]code that is long enough to wrap\f[R].
.IP
.nf
\f[C]
code block that is very long and should never be wrapped by anything at all whatsoever ok
\f[]
.fi
.LP
& é A # \ *
x, and a
lone - or +
or > or 1.
or 1) that
must not
begin a
line.
.PP
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
lw(44.2n) lw(25.8n).
T{
.nr LL 44.2n
r1 bis
T}	T{
.nr LL 25.8n
a
T}
T{
.nr LL 44.2n
T}	T{
.nr LL 25.8n
b
T}
T{
.nr LL 44.2n
r2
T}	T{
.nr LL 25.8n
c
T}
.TE
.nr LL \n[LLold]
.ad
.LP
A link with
attributes.
