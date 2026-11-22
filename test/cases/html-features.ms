.SH 1
Intro
.LP
Text with a note\**
.FS
First note.
.PP
Second para of note.
.FE
and another.\**
.FS
Inline \f[I]note\f[R] here.
.FE
.SH 2
Sub link here
.IP \(bu 3
☐ todo
.IP \(bu 3
☒ done
.IP " 1." 4
one
.IP " 2." 4
two
.IP " (1)" 5
ex one
.IP " (2)" 5
ex two
.IP " 1." 4
hash
.IP " iv." 5
roman
.IP "  v." 5
roman2
.IP " A)" 4
alpha
.IP " B)" 4
beta
.SH 3
Deep
.SH 4
Unlisted
.LP
left
.LP
right
.LP
Inside div.
\" .IMAGE "fig.png" "225p" "70p"
.ce 1
A figure caption
.sp 1
.LP
[IMAGE: ] \" "inline.svg" "0p"
inline
[IMAGE: alt x] \" "a.jpg"
and
[IMAGE: ] \" "s.mp3"
and
.PDFPIC "doc.pdf"
.PP
\s-2SPAN\s0 k m \f[I]u\f[R] p plain \f[CR]x\f[R] \f[CR]y\f[R]
raw html
.LP
Line one
.br
\ \ Line two
.QS
.LP
quote
.QS
.LP
nested
.QE
.QE
.IP "\f[B]Term\f[R]" 3
Definition one
.RS 3
more
.RE
.IP "\f[B]Term 2\f[R]" 3
Def 2a
.RS 3
.RE
Def 2b
.RS 3
.RE
.HLINE
.PP
Simple table
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
Multiline
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
cw(10.7n) lw(12.6n) rw(10.7n) lw(10.7n).
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
.nr LL 10.7n
First
T}	T{
.nr LL 12.6n
row
T}	T{
.nr LL 10.7n
12.0
T}	T{
.nr LL 10.7n
Example long
T}
T{
.nr LL 10.7n
Second
T}	T{
.nr LL 12.6n
row
T}	T{
.nr LL 10.7n
5.0
T}	T{
.nr LL 10.7n
Here
T}
.TE
.nr LL \n[LLold]
.ad
.SH 1
Second
.LP
Back link a\(atb.com and mail and int.
.PP
Cite H\*<2\*>O \m[strikecolor]s\m[] \*{sup\*}
.PP
Last para with ↩ arrow and ↔.
.PP
Para\**
.FS
.IP
.nf
\f[CR]
code note
\f[]
.fi
.FE
.SH 2
Empty header
.SH 7
Not header
