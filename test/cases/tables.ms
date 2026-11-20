.PP
A pipe table
.na
.TS
delim(@@) tab(	);
l c r l.
T{
Left
T}	T{
Center
T}	T{
Right
T}	T{
Default
T}
_
T{
\f[CR]a|b\f[R]
T}	T{
$x|y$
T}	T{
|
T}	T{
c
T}
T{
short
T}	T{
T}	T{
T}	T{
T}
.TE
.ad
.PP
A simple table.
.na
.TS
delim(@@) tab(	);
r l c l.
T{
Right
T}	T{
Left
T}	T{
Center
T}	T{
Default
T}
_
T{
12
T}	T{
12
T}	T{
12
T}	T{
12
T}
T{
123
T}	T{
123
T}	T{
123
T}	T{
123
T}
.TE
.ad
.PP
.na
.TS
delim(@@) tab(	);
r l c c.
T{
12
T}	T{
12
T}	T{
12
T}	T{
12
T}
T{
123
T}	T{
123
T}	T{
123
T}	T{
123
T}
.TE
.ad
.PP
Here\(cqs the caption. It, too, may span multiple lines.
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
cw(11.7n) lw(7.8n) rw(15.6n) lw(25.3n).
T{
Centered Header
T}	T{
Default Aligned
T}	T{
Right Aligned
T}	T{
Left Aligned
T}
_
T{
.nr LL 11.7n
First
T}	T{
.nr LL 7.8n
row
T}	T{
.nr LL 15.6n
12.0
T}	T{
.nr LL 25.3n
Example of a row that spans multiple lines.
T}
T{
.nr LL 11.7n
Second
T}	T{
.nr LL 7.8n
row
T}	T{
.nr LL 15.6n
5.0
T}	T{
.nr LL 25.3n
Here\(cqs another one.
Note the blank line between rows.
T}
.TE
.nr LL \n[LLold]
.ad
.PP
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
lw(23.3n) lw(46.7n).
T{
a very long first column header that goes on
T}	T{
and the second one, which is also long
T}
_
T{
.nr LL 23.3n
x
T}	T{
.nr LL 46.7n
y
T}
.TE
.nr LL \n[LLold]
.ad
