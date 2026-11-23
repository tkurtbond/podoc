.PP
Sample grid table.
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
lw(15.6n) lw(15.6n) lw(20.4n).
T{
.LP
Fruit
T}	T{
.PP
Price
T}	T{
.PP
Advantages
T}
_
T{
.nr LL 15.6n
.PP
Bananas
T}	T{
.nr LL 15.6n
.PP
$1.34
T}	T{
.nr LL 20.4n
.IP \(bu 3
built-in wrapper
.IP \(bu 3
bright color
T}
T{
.nr LL 15.6n
.LP
Oranges
T}	T{
.nr LL 15.6n
.PP
$2.10
T}	T{
.nr LL 20.4n
.IP \(bu 3
cures scurvy
.IP \(bu 3
tasty
T}
.TE
.nr LL \n[LLold]
.ad
.PP
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
rw(15.6n) lw(15.6n) cw(20.4n).
T{
Right
T}	T{
Left
T}	T{
Centered
T}
_
T{
.nr LL 15.6n
Bananas
T}	T{
.nr LL 15.6n
$1.34
T}	T{
.nr LL 20.4n
built-in wrapper
T}
.TE
.nr LL \n[LLold]
.ad
.PP
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
rw(15.6n) lw(15.6n) cw(20.4n).
T{
.nr LL 15.6n
Right
T}	T{
.nr LL 15.6n
Left
T}	T{
.nr LL 20.4n
Centered
T}
.TE
.nr LL \n[LLold]
.ad
.PP
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
lw(13.6n) lw(7.8n) lw(10.7n).
T{
Property
T}	T{
T}	T{
Earth
T}
_
T{
.nr LL 13.6n
Temperature 1961-1990
T}	T{
.nr LL 7.8n
min
T}	T{
.nr LL 10.7n
-89.2 °C
T}
T{
.nr LL 13.6n
T}	T{
.nr LL 7.8n
mean
T}	T{
.nr LL 10.7n
14 °C
T}
T{
.nr LL 13.6n
T}	T{
.nr LL 7.8n
max
T}	T{
.nr LL 10.7n
56.7 °C
T}
.TE
.nr LL \n[LLold]
.ad
.PP
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
lw(13.6n) lw(7.8n) lw(10.7n).
T{
head
T}	T{
b
T}	T{
c
T}
_
T{
.nr LL 13.6n
body
T}	T{
.nr LL 7.8n
x
T}	T{
.nr LL 10.7n
y
T}
T{
.nr LL 13.6n
foot
T}	T{
.nr LL 7.8n
z
T}	T{
.nr LL 10.7n
w
T}
.TE
.nr LL \n[LLold]
.ad
.PP
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
lw(3.9n) lw(3.9n).
T{
.nr LL 3.9n
a
T}	T{
.nr LL 3.9n
b
T}
.TE
.nr LL \n[LLold]
.ad
.PP
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
lw(3.9n) lw(3.9n).
T{
.nr LL 3.9n
1
T}	T{
.nr LL 3.9n
2
T}
.TE
.nr LL \n[LLold]
.ad
.PP
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
lw(6.8n) lw(6.8n).
T{
.nr LL 6.8n
日本
T}	T{
.nr LL 6.8n
x
T}
.TE
.nr LL \n[LLold]
.ad
.SH 2
Grid Tables
.PP
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
lw(18.5n) lw(11.7n) lw(12.6n).
T{
col 1
T}	T{
col 2
T}	T{
col 3
T}
_
T{
.nr LL 18.5n
r1 a r1 bis
T}	T{
.nr LL 11.7n
b b 2
T}	T{
.nr LL 12.6n
c c 2
T}
T{
.nr LL 18.5n
r2 d
T}	T{
.nr LL 11.7n
e
T}	T{
.nr LL 12.6n
f
T}
.TE
.nr LL \n[LLold]
.ad
.LP
Headless
.PP
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
lw(18.5n) lw(11.7n) lw(12.6n).
T{
.nr LL 18.5n
r1 a r1 bis
T}	T{
.nr LL 11.7n
b b 2
T}	T{
.nr LL 12.6n
c c 2
T}
T{
.nr LL 18.5n
r2 d
T}	T{
.nr LL 11.7n
e
T}	T{
.nr LL 12.6n
f
T}
.TE
.nr LL \n[LLold]
.ad
.LP
With alignments
.PP
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
rw(18.5n) lw(11.7n) cw(12.6n).
T{
col 1
T}	T{
col 2
T}	T{
col 3
T}
_
T{
.nr LL 18.5n
r1 a r1 bis
T}	T{
.nr LL 11.7n
b b 2
T}	T{
.nr LL 12.6n
c c 2
T}
T{
.nr LL 18.5n
r2 d
T}	T{
.nr LL 11.7n
e
T}	T{
.nr LL 12.6n
f
T}
.TE
.nr LL \n[LLold]
.ad
.LP
Headless with alignments
.PP
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
rw(18.5n) lw(11.7n) cw(12.6n).
T{
.nr LL 18.5n
r1 a r1 bis
T}	T{
.nr LL 11.7n
b b 2
T}	T{
.nr LL 12.6n
c c 2
T}
T{
.nr LL 18.5n
r2 d
T}	T{
.nr LL 11.7n
e
T}	T{
.nr LL 12.6n
f
T}
.TE
.nr LL \n[LLold]
.ad
.LP
Spaces at ends of lines
.PP
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
lw(18.5n) lw(11.7n) lw(12.6n).
T{
.nr LL 18.5n
r1 a r1 bis
T}	T{
.nr LL 11.7n
b b 2
T}	T{
.nr LL 12.6n
c c 2
T}
T{
.nr LL 18.5n
r2 d
T}	T{
.nr LL 11.7n
e
T}	T{
.nr LL 12.6n
f
T}
.TE
.nr LL \n[LLold]
.ad
.LP
Multiple blocks in a cell
.PP
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
lw(18.5n) lw(11.7n) lw(12.6n).
T{
.nr LL 18.5n
.SH 1
col 1
.LP
col 1
T}	T{
.nr LL 11.7n
.SH 1
col 2
.LP
col 2
T}	T{
.nr LL 12.6n
.SH 1
col 3
.LP
col 3
T}
T{
.nr LL 18.5n
.PP
r1 a
.PP
r1 bis
T}	T{
.nr LL 11.7n
.IP \(bu 3
b
.IP \(bu 3
b 2
.IP \(bu 3
b 2
T}	T{
.nr LL 12.6n
.LP
c c 2 c 2
T}
.TE
.nr LL \n[LLold]
.ad
.LP
East Asian characters have double width
.PP
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
lw(2.9n) lw(4.9n).
T{
.nr LL 2.9n
魚
T}	T{
.nr LL 4.9n
fish
T}
.TE
.nr LL \n[LLold]
.ad
.LP
Zero-width space in German
.PP
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
lw(7.8n) lw(7.8n).
T{
.nr LL 7.8n
German
T}	T{
.nr LL 7.8n
English
T}
T{
.nr LL 7.8n
Auf‌lage
T}	T{
.nr LL 7.8n
edition
T}
.TE
.nr LL \n[LLold]
.ad
.LP
Zero-width non-joiner in Persian
.PP
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
lw(7.8n) lw(9.7n).
T{
.nr LL 7.8n
می‌خواهم
T}	T{
.nr LL 9.7n
I want to
T}
.TE
.nr LL \n[LLold]
.ad
.LP
Empty cells
.PP
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
lw(3.9n) lw(3.9n).
T{
.nr LL 3.9n
T}	T{
.nr LL 3.9n
T}
.TE
.nr LL \n[LLold]
.ad
.LP
Table with cells spanning multiple rows or columns:
.PP
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
lw(13.6n) lw(7.8n) lw(10.7n).
T{
Property
T}	T{
T}	T{
Earth
T}
_
T{
.nr LL 13.6n
Temperature 1961-1990
T}	T{
.nr LL 7.8n
min
T}	T{
.nr LL 10.7n
-89.2 °C
T}
T{
.nr LL 13.6n
T}	T{
.nr LL 7.8n
mean
T}	T{
.nr LL 10.7n
14 °C
T}
T{
.nr LL 13.6n
T}	T{
.nr LL 7.8n
min
T}	T{
.nr LL 10.7n
56.7 °C
T}
.TE
.nr LL \n[LLold]
.ad
.LP
Table with complex header:
.PP
.na
.nr LLold \n[LL]
.TS
delim(@@) tab(	);
lw(21.4n) lw(7.8n) lw(7.8n) lw(7.8n).
T{
Location
T}	T{
Temperature 1961-1990 in degree Celsius
T}	T{
T}	T{
T}
_
T{
.nr LL 21.4n
T}	T{
.nr LL 7.8n
min
T}	T{
.nr LL 7.8n
mean
T}	T{
.nr LL 7.8n
max
T}
T{
.nr LL 21.4n
Antarctica
T}	T{
.nr LL 7.8n
-89.2
T}	T{
.nr LL 7.8n
N/A
T}	T{
.nr LL 7.8n
19.8
T}
T{
.nr LL 21.4n
Earth
T}	T{
.nr LL 7.8n
-89.2
T}	T{
.nr LL 7.8n
14
T}	T{
.nr LL 7.8n
56.7
T}
.TE
.nr LL \n[LLold]
.ad
