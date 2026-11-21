Simple tables.

=====  =====  ======
   Inputs     Output
------------  ------
  A      B    A or B
=====  =====  ======
False  False  False
True   False  True
False  True   True
True   True   True
=====  =====  ======

=====  =====
col 1  col 2
=====  =====
1      Second column of row 1.
2      Second column of row 2.
       Second line of paragraph.
3      - Second column of row 3.

       - Second item in bullet
         list (row 3, column 2).
\      Row 4; column 1 will be empty.
=====  =====

Headless:

=====  =====  =====
a      b      c
d      *e*    f
=====  =====  =====

Header only rows:

===  ===
h1   h2
h3   h4
===  ===
x    y
===  ===

After.

One column:

=====
a
b
=====

Blank line in body:

===  ===
a    b

c    d
===  ===

Spans mismatch:

=====  =====
a      b
----
c      d
=====  =====

Wide 中文 chars:

====  ====
中文  x
ab    y
====  ====

Footer not followed by blank:

===  ===
a    b
===  ===
text

Last line long:

===  ===
a    b and more text past the border
===  ===

Tabs	in:

===  ===
a	   b
===  ===

=====  =====
a      b
=====  =====
