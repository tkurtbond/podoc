.SH 1
Héading with x\*{2\*} and H\*<2\*>O and S\s-2MALL\s0
.SH 2
Unnumbered \(lqquoted\(rq heading
.LP
\&.leading period and `single' \(lqdouble\(rq and \(at \(ti \(ha \(ga
and a M\s-2IXED\s0 S\s-2MALLCAPS\s0 3\s-2X\s0.
.PDFPIC "pic.pdf" "144p" "85p"
.ce 1
A caption with \f[I]emph\f[R]
.sp 1
.LP
[IMAGE: ] \" "pic.png" "0p"
.PP
.PSPIC "pic.eps" "75p"
inline.
.IP "   i." 6
one
.IP "  ii." 6
two
.IP " iii." 6
three
.IP " (a)" 5
alpha
.IP " (b)" 5
beta
.IP " 1." 4
default
.IP " 2." 4
second
.IP " 7)" 4
seven
.IP " 8)" 4
eight
.IP "\f[B]Term \f[BI]one\f[B]\f[R]" 3
Definition one.
.RS 3
Second paragraph.
.RE
.IP "\f[B]Term two\f[R]" 3
.IP
.nf
\f[C]
code def
\f[]
.fi
.RS 3
.RE
\(bu .RS 3
.IP
.nf
\f[C]
code item
\f[]
.fi
.RE
.IP \(bu 3
item
.RS 3
.LP
continued
.RE
\(bu .RS 3
.QS
.LP
quoted
.QE
.RE
.IP " 1." 4
first
.RS 4
.LP
second para
.RE
.LP
line one
.br
\ \ line two
.PP
A note.\**
.FS
Note text.
.PP
More note.
.FE
And another.\**
.FS
.IP
.nf
\f[C]
code note
\f[]
.fi
.FE
.LP
link and web and me\(atexample.com.
.IP "\f[B]Term with note\**
.FS
in a term
.FE
\f[R]" 3
def
.RS 3
.RE
.HLINE
.LP
Div para.
.PP
Caption \f[I]here\f[R].
.na
.TS
delim(@@) tab(	);
l r.
T{
A
T}	T{
B
T}
_
T{
1
T}	T{
2
T}
.TE
.ad
.PP
Multiline with widths.
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
cw(16.5n) cw(24.3n).
T{
Wide one
T}	T{
Wide two
T}
_
T{
.nr LL 16.5n
x
T}	T{
.nr LL 24.3n
y
T}
T{
.nr LL 16.5n
z
T}	T{
.nr LL 24.3n
w
T}
.TE
.nr LL \n[LLold]
.ad
.LP
Line one
.br
line two.
.PP
\f[CR]code\f[R] and \f[CR].dot\f[R] and \f[B]bold \f[BI]both\f[B]\f[R]
and \m[strikecolor]strike\m[].
