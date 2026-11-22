# vgrind: how BSD's program formatter highlights code

Research for podoc, 2026-11-22. This looks at what vgrind does when
it highlights code, and what that means for the small highlighting
design in docs/research/syntax-highlighting-small.md.

Sources:

- vgrind 5.7, the user's stored copy of Debian's package:
  `/usr/local/sw/src/doctools/vgrind/vgrind_5.7.orig.tar.gz` and
  `vgrind_5.7-17.diff.gz`. These are the 4.4BSD sources.
- NetBSD 11.0's vgrind, on artos.
- FreeBSD 15.1 (alerik) and OpenBSD 7.9 (jherek), checked for it.

**How it was tested.**

- I built `vfontedpr` from the patched sources in
  `/usr/local/sw/tmp`, with `gcc -std=gnu89 -fcommon`, and removed it
  afterwards. The code is K&R C, and it does not link without
  `-fcommon`.
- I ran it on a small Oberon module (with the `m2` definition) and a
  small C file.
- I rendered the output with `tmac.vgrind` and groff 1.25.0
  `-Tpdf`, and looked at the pages.

Everything marked *seen* came from those runs.

## 1. Summary

- **vgrind already sets code the way the small design's
  "proportional" style would.**
  - Code is in the text font (Times-Roman).
  - Reserved words are in bold.
  - Comments are in italic.
  - Line breaks are kept.
  - Tabs go to absolute positions, so tab-aligned columns line up
    even in a proportional font.
- **It is a troff preprocessor driven by a database.** Each language
  is a `vgrindefs` entry in termcap format, with:
  - comment and string delimiters, written as small regular
    expressions;
  - a case flag;
  - a keyword list.

  This is the same split the small design proposes: a generic scanner
  and per-language data.
- **Its languages and lists are from the 1980s.**
  - It has C, C++, Pascal, Modula-2 and sh, among others, but no Ada
    and no Oberon.
  - The C list predates ANSI C, and the C++ list has `overload`.
  - The Modula-2 entry uses Pascal's comment and case rules, which
    are wrong for Modula-2 (*seen*).
- **Its scanner is simple, and it shows.**
  - Comments do not nest.
  - `{` and `}` are bold everywhere, inside strings too.
  - C's `//` is not a comment.
  - sh keywords are bolded wherever they appear, builtins among them.
- **It cannot be used from podoc.**
  - It writes a whole troff page layout of its own.
  - Its embedding mode, by its own manual, does not work with `-ms`.
  - It has no mom or ConTeXt form.
  - Of the systems podoc supports, only NetBSD still ships it.
- **What to take from it:**
  - the precedent for the proportional style;
  - the tab trick, which could also be used for runs of spaces. An
    experiment (§8) shows it works for ms, mom and, with three
    macros, ConTeXt; the recommended form measures each group of
    lines;
  - a language-description database whose keyword list is exactly a
    user-supplied reserved-word list.

## 2. What vgrind is

vgrind appeared in 3.0BSD; its `vgrindefs` format came in 4.2BSD
(manual pages). It has six parts:

| Part | Lines | Role |
|---|---|---|
| `vgrind` | 143 | a csh script: options, then `vfontedpr` piped to troff |
| `vfontedpr.c` | 703 | the formatter: reads code, writes troff |
| `regexp.c` | 582 | vgrind's own word-based regular expressions |
| `vgrindefs.c` | 326 | a termcap-style reader for the database |
| `tmac.vgrind` | 68 | macros: page header and footer, fonts, comment mode |
| `vgrindefs.src` | 146 | the language database |

**Licence:**
- The code is © 1980 and the database © 1987 by the Regents of the
  University of California.
- Both carry the four-clause BSD licence. The University withdrew
  its advertising clause in 1999, which leaves it in effect the
  three-clause licence podoc uses.
- None of the code is needed for the small design, so the licence
  matters only if `vgrindefs` data were copied.

## 3. What it writes

`vfontedpr` turns each line into troff, in no-fill mode with the font
at 1 (roman). From the Oberon test (*seen*):

```
\*(+KPROCEDURE\*(-K P(x: INTEGER): INTEGER;
\h'|11n'\*(+KVAR\*(-K s: \*(+KARRAY\*(-K 8 \*(+KOF\*(-K CHAR;
\h'|11n's := "IF THEN"; (\fI*\fP\c\c
'+C
 nested (\fI*\fP comment \fI*\fP)\c
'-C
 \*(+KBEGIN\*(-K \fI*\fP)
```

- **Reserved words:** `\*(+K` ... `\*(-K`, which are `\f3` and `\fP`
  (bold, then back) outside comments. `tmac.vgrind` also sets
  `.bd B 3`, a slight overstrike that makes the bold heavier.
- **Comments:** the macros `'+C` and `'-C` switch to font 2 (italic),
  and empty `+K` and `-K` inside them, so a word in a comment is not
  bold.
- **Strings and character literals:** copied plain. The keyword check
  is skipped inside them (`"IF THEN"` stays roman, *seen*).
- **Characters:**
  - `\` becomes `\e`;
  - `-` becomes a minus;
  - `_` becomes a lowered minus;
  - `.` becomes `\&.`;
  - `*` and `/` are set in italic;
  - `{` and `}` are always set in bold, by the character routine,
    whatever the context.
- **Tabs:** each run of tabs becomes `\h'|Nn'`, an absolute position
  from the start of the line. N is 10 ens for each 8-column tab stop,
  plus 1. Text that starts after a tab therefore starts at the same
  place on every line, whatever the proportional widths before it.
  Spaces are left as spaces. vgrind's own manual says "The use of
  spaces to align source code fails miserably; if you plan to vgrind
  your program you should use tabs."
- **Indentation is wide, and fixed** (*seen*).
  - The width is hard-coded in `vfontedpr.c`, lines 559–560:

    ```c
    i = tabs(cur_start, start) - margin / 8;
    printf("\\h'|%dn'", i * 10 + 1 - margin % 8);
    ```

  - Tab stops are every 8 columns, and each becomes 10 ens. At
    vgrind's 9-point default, an en is 4.5 points, so each tab moves
    the text about 45 points, roughly 0.6 inch. Code indented one
    tab per level is therefore indented 0.6 inch per level, which
    looks very wide on the page.
  - No option changes it. `-s` sets the point size, and the en
    scales with it, so the indentation shrinks only as the text does.
    `-W` chooses an output device. `tmac.vgrind` sets only `.ps 9p`,
    `.vs 10p` and `.ss 23`.
  - The only way to change it is to edit the `10` and rebuild; `4`
    or `5` would give about two or three average Times characters
    per level. This was not tried.
- **Page layout:**
  - each page has a header with the file name in 14-point bold, and
    a footer with the file's date and "Page N of file";
  - the current procedure's name is printed in the right margin
    (`'FN`), found with the `pb` expression; neither of my tests
    produced it;
  - an index of procedures is built with `-x`.
- **Point sizes, and groff 1.25.0** (*seen*):
  - `tmac.vgrind` writes size changes as `\s14` and `\s12`: on line
    17 for the header's file name, on line 20 for the `=f` string the
    header sets at the right margin, and on line 56 in the macro that
    prints a procedure's name at the right margin.
  - Old troffs read `\s14` as 14 points.
  - groff 1.25.0 reads it as `\s1` followed by the text "4". The
    file name in the header therefore comes out at 1 point, as small
    marks, with a stray "4" before it (seen with `-Tutf8`).
  - The fix is `\s(14` and `\s(12`. With those changes in a local
    copy of `tmac.vgrind`, Debian's `vgrind` script printed the file
    name in 14-point bold at both top corners of each page.
  - NetBSD's `vgrind.tmac` was not checked for the same forms.
- **Filter mode** (`-f`): only lines between `.vS` and `.vE` in a
  troff document are formatted, the rest is passed through. The
  manual: "Filter mode does not work in documents using the -me or
  -ms macros."

The rendered pages (*seen*) are what the small design calls the
proportional style, plus italic comments: Times-Roman code,
Times-Bold reserved words, Times-Italic comments.

## 4. The language database

An entry, for C:

```
C|c:\
	:pb=^\d?*?\d?\p\d?\(\a?\)(\d|{):bb={:be=}:cb=/*:ce=*/:sb=":se=\e":lb=':\
	:le=\e':tl:\
	:kw=asm auto break case char continue default do double else enum\
	extern float for fortran goto if int long register return short\
	sizeof static struct switch typedef union unsigned void while #define\
	#else #endif #if #ifdef #ifndef #include #undef # define else endif\
	if ifdef ifndef include undef:
```

| Capability | Meaning |
|---|---|
| `pb` | a procedure's beginning, a regular expression; `\p` captures its name |
| `bb`, `be` | a block's beginning and end, for nesting levels |
| `cb`, `ce` | a comment's beginning and end |
| `ab`, `ae` | a second comment form |
| `sb`, `se` | a string's beginning and end |
| `lb`, `le` | a character literal's beginning and end |
| `tl` | procedures only at the top level |
| `oc` | one case: keywords match in either case, and are listed in lower case |
| `kw` | the keyword list |

**The expressions** are vgrind's own:
- they match words, not characters;
- `\d` is a delimiter, `\a` any string, `\p` a name, `$` the end of
  the line;
- `\e` before a delimiter means "not when escaped", which is how
  `\"` inside a C string is handled.

**The languages** in 5.7, and unchanged in NetBSD 11.0 (its file is
dated 1994): C, model, Pascal, ISP, sh, csh, LDL, Icon, Ratfor,
Modula-2, yacc and C++. Against the small design's languages:

| Language | In vgrindefs | Problems |
|---|---|---|
| C | yes | pre-ANSI list (no `const` or `volatile`, which Debian adds; has `fortran`); `//` not a comment (*seen*) |
| C++ | yes | 1980s list (`overload`; no `bool`, `template`, `namespace`, `try`) |
| Pascal | yes | ISO Pascal plus `assert`, `oct`, `hex`, `external`; no Object Pascal; no `oc`, so `BEGIN` in capitals is not bold |
| Modula-2 | yes | `{ }` comments and `oc`, both Pascal's, not Modula-2's; `(* *)` does not nest (*seen*) |
| sh | yes | builtins (`cd`, `exit`, `read`, `set`, `test`, ...) listed as keywords; no command-position rule |
| bash | no | |
| Ada | no | |
| Oberon-2 | no | the Modula-2 entry, used for Oberon here, bolds lower-case words too |

## 5. Where it is today

- **Debian** packages it (the source here is that package).
- **NetBSD 11.0** has it in the base system: `/usr/bin/vgrind`,
  `/usr/libexec/vfontedpr`, `/usr/share/misc/vgrindefs` and
  `/usr/share/tmac/vgrind.tmac`, with groff (*seen*).
- **FreeBSD 15.1 and OpenBSD 7.9** do not have it (*seen*: no
  `vgrind` on alerik or jherek).
- **Fedora** has no package installed on atla, and podoc cannot count
  on one.

## 6. What it means for podoc

### 6.1 Not as an external program

Running vgrind from podoc would fail for several reasons:

- it writes its own page layout (`'wh` traps for its header and
  footer, its own point size and spacing), which fights ms and mom;
- its filter mode, the only way to embed code in a document, is
  documented not to work with ms;
- it writes troff only, so it gives nothing for ConTeXt;
- its macros use `\s14`, which current groff (1.25.0) misreads, so
  its headers break unless `tmac.vgrind` is patched (§3);
- it is missing on FreeBSD, OpenBSD and Fedora;
- its lists and scanner are older and weaker than what the small
  design needs (§4).

### 6.2 What to borrow

1. **The proportional style has a long precedent.** vgrind has set
   code in roman with bold keywords and italic comments since 3.0BSD.
   - The style could be named after it in the documentation.
   - If the user wants italic comments too, vgrind shows the look.
     The small design's scanner already finds comments, so this costs
     little (its §9).
2. **Absolute positions for alignment.** vgrind's `\h'|Nn'` keeps
   tab-aligned columns straight in a proportional font.
   - podoc's readers expand tabs to spaces, so podoc would apply the
     same idea to spaces: any run of two or more spaces, and leading
     indentation, could become `\h'|Nn'` for its column. Columns of
     comments and declarations would then line up in the proportional
     style in ms and mom.
   - This answers the concern in syntax-highlighting-small.md §4.4.
     Tried in §8, with a guard against overlap and with measured
     positions.
   - The width of a column should not be fixed in the code, as
     vgrind's 10 ens per tab stop is (§3). podoc would make the width
     of one column a setting, in ens or a fraction of an em, so that
     indentation is not too wide.
   - ConTeXt needs its own equivalent, as TeX cannot ask for the
     current position on a line: §8.2 gives three macros that keep
     count segment by segment.
3. **A language description as data.** vgrindefs' `kw` field is
   exactly the user's reserved-word list of the small design (its
   §6).
   - podoc could read the `kw` field of a vgrindefs-style entry as one
     of its list formats.
   - Taking whole vgrindefs entries would also mean vgrind's regular
     expressions. That is more than the small design needs. Its
     comment and string forms are fixed per language in podoc's code.
4. **Mistakes to avoid**, all seen in the tests:
   - comments that do not nest (Oberon, Modula-2, FreePascal);
   - punctuation bolded regardless of context (`{ }` in strings);
   - a missing comment form (C's `//`);
   - the wrong case rule (Modula-2 marked one-case);
   - sh keywords taken out of command position.

   The small design's language records and hooks
   (syntax-highlighting-small.md §5.8) cover each of these.

## 7. Questions for the user

- **V1.** Should the proportional style also set comments in italic,
  as vgrind does? *Decided 2026-11-22: yes* (PLAN.md decision 30).
- **V2.** Should the proportional style use absolute positions
  (`\h'|Nn'`) for runs of spaces in ms and mom, to keep columns
  aligned? *The user asked for the experiment, and a way to do it in
  ConTeXt: see §8.* Settled by V4: podoc does it, in the form the
  user chooses, hybrid by default.
- **V3.** Should a user's reserved-word list be readable in
  vgrindefs format (the `kw` field) as well as podoc's own?
  *Decided 2026-11-22: no, podoc's own format only* (PLAN.md
  decision 31).
- **V4.** Which form of alignment (§8.1), and what default column
  width? The experiment suggests the *hybrid* form, with 0.5 em per
  column and a gap of 1 em.
  - *Part 2 decided 2026-11-22* (PLAN.md decision 32): the defaults
    are 0.5 em per column and a 1 em gap, and the user must be able
    to change both, through the template variables `code-column` and
    `code-gap`: plain numbers of ems, to which each template adds its
    unit, while the writer writes column numbers, not lengths (see
    decision 32 for the template lines). Not yet verified.
  - *Part 1 decided 2026-11-22* (PLAN.md decision 33): all three
    forms, and `none`, chosen with `--code-align=none|fixed|elastic|hybrid`
    or `code-align` in the metadata; the default is `hybrid`.

## 8. The alignment experiment (V2)

Done 2026-11-22, by hand, with no podoc code: a throwaway awk script
wrote ms, mom and ConTeXt for two samples, and the results were
rendered with groff 1.25.0 (`-ms -Tpdf`, `pdfmom`) and ConTeXt LMTX,
then looked at.

### 8.1 What was tested

- **Samples**, indented and aligned with spaces, as podoc's readers
  leave code once tabs are expanded:
  - an Oberon module: declarations with trailing comments aligned at
    column 28, nested indentation, comments that are separated by
    blank lines;
  - a C header and function: a `struct` with member names and
    comments in columns, `char *name` with the `*` one column left of
    the names, `#define` values in a column (one name made wide on
    purpose, `WWWWWWWW`), `case` labels with aligned statements.
- **Styles:** Times (ms, mom) and TeX Gyre Termes (ConTeXt), 10
  point, reserved words bold and comments italic (decision 30).
- **Splitting a line:** leading spaces set the indentation. Inside a
  line, every run of *two or more* spaces ends a segment, and the next
  segment starts at its source column. A single space stays an
  ordinary space. Trailing spaces are dropped.
- **Four forms**, each in the three formats:
  - **mono**, the reference: Courier, spaces as they are.
  - **fixed**: each segment is placed at its column × *W*. A guard
    keeps at least a gap *G* after the previous segment, so text never
    overlaps when the proportional prefix is wider than its columns.
  - **elastic**: positions are measured. Consecutive lines with a
    segment starting at the same column form a group, and the group's
    position is the widest text before it on any of its lines, plus
    *G* (the "elastic tabstops" idea).
  - **hybrid**: as elastic, but a group's position is never less than
    its column × *W*. So columns sit where *fixed* puts them, and a
    group moves right, all its lines together, only when its text is
    too wide.
- **Widths tried:** *W* = 0.5 em and 0.4 em per column, *G* = 1 em.

The PDFs, at 0.5 em, were left in `/tmp/vgrind/align-ms.pdf`,
`align-mom.pdf` and `align-context.pdf` for the user to look at.

### 8.2 The forms in roff and ConTeXt

**ms and mom.** No macros are needed; all is in escapes:

- indentation: `\h'|2m'` (four columns × 0.5 em);
- *fixed*, a later segment: `\h'(14m-\n[.k]u)>?1m'`.
  `\n[.k]` is the width already set on the output line, so this is
  "move to 14 em, or 1 em on if already past it". *Verified* in groff
  1.25.0, in `.nf` under ms and inside mom's `.QUOTE`.
- *elastic* and *hybrid*: before the block, a register per group,

  ```
  .nr PdG2 14m
  .nr PdG2 \n[PdG2]>?(\w'\&\h'|2m'\f[R]Max = 100;\f[R]'u+1m)
  .nr PdG2 \n[PdG2]>?(\w'\&\h'|2m'\f[R]Overflow = 100;\f[R]'u+1m)
  ```

  then `\h'|\n[PdG2]u'` before the segment. `\w` measures the line's
  text before the segment, with its fonts, so the alignment is exact.
  (*elastic* starts the register at 0 instead of 14m.) A group's
  prefix only refers to groups at smaller columns, so the registers
  are computed in order of column.
- `\h'|...'` counts from the start of the text, after mom's `.QUOTE`
  indent or ms's paragraph indent, as wanted (*seen*). The user did
  not like code indented from the margin in mom: with `.QUOTE_INDENT
  0` before `.QUOTE`, the code starts at the left margin and every
  form still aligns (*seen*, 2026-11-22). podoc now does this by
  default, with the template variable `code-indent` (decision 34).

**ConTeXt.** TeX does not let a macro ask where it is on the current
line, so a line is built from segments that keep their own count.
Three macros, which would go in podoc's default ConTeXt template:

```tex
\newdimen\PdPos \newdimen\PdT \newbox\PdBox
\def\PdGap{1em}
\def\PdLine{\global\PdPos=0pt\relax}
\def\PdSeg#1#2{%            #1 position, #2 text
  \setbox\PdBox\hbox{#2}%
  \PdT=#1\relax
  \ifdim\PdPos>0pt
    \ifdim\PdT<\dimexpr\PdPos+\PdGap\relax
      \PdT=\dimexpr\PdPos+\PdGap\relax \fi
  \fi
  \hskip\dimexpr\PdT-\PdPos\relax
  \global\PdPos=\dimexpr\PdT+\wd\PdBox\relax
  \box\PdBox}
\def\PdMeasure#1#2{%        #1 group, #2 the line's text before it
  \setbox\PdBox\hbox{#2}%
  \ifdim\dimexpr\wd\PdBox+\PdGap\relax>\getvalue{#1}\relax
    \setxvalue{#1}{\the\dimexpr\wd\PdBox+\PdGap\relax}\fi}
```

- A code line, inside `\startlines` ... `\stoplines`:
  `\PdLine\PdSeg{2em}{Max = 100;}\PdSeg{14em}{{\it (* capacity *)}}`.
  `\PdSeg` is the *fixed* form, guard included.
- *elastic* and *hybrid*: before `\startlines`,
  `\setvalue{PdG2}{14em}` (or `0pt`) and one `\PdMeasure` per line of
  the group, then `\PdSeg{\getvalue{PdG2}}{...}`.
- Each segment is a box, so a font change cannot run from one segment
  into the next: the writer must close and reopen bold or italic at
  each segment, as it does for roff (the experiment did that for
  both).
- *Verified:* ConTeXt LMTX made all four forms with no errors or
  overfull boxes, and they look the same as groff's.

### 8.3 What was seen

- **The idea works in all three formats.** Columns of comments,
  member names, `#define` values and `case` statements line up in
  Times as they do in Courier.
- **fixed, at 0.5 em:** everything lines up, including `*name`
  hanging one column left. Only the deliberately wide `WWWWWWWW` line
  trips the guard: its value and comment move right, alone.
- **fixed, at 0.4 em:** more lines trip the guard. `HALT(Overflow)`
  and the 1 em gap after it do not fit before 28 × 0.4 em, so its
  comment is pushed past the column the other comments use. The
  narrower *W*, the more of these.
- **elastic:** the tightest layout, and exact inside each group. But
  it aligns only lines that are next to each other: the Oberon
  comments at column 28 above and below a blank line end up at
  different places, though they line up in the source. `*name` (one
  column left of the other names) forms a group of its own and loses
  its hanging star.
- **hybrid, at 0.4 em:** the guard's misalignment is gone: when a
  group is too wide, all its lines move together. Groups at the same
  column but separated by blank lines are still placed independently,
  but at the same place whenever their text fits. The `*name` star
  hangs, a little too far left when its neighbours' group was widened.
- **Indentation** at 0.5 em per column is about two average Times
  characters per space, so four-space indentation is 2 em: clearly
  visible, and far narrower than vgrind's 0.6 inch per tab.
- **Cost:** *fixed* adds one escape per run of spaces. *elastic* and
  *hybrid* add, for each group, one register line per member, each
  repeating the line's prefix: in the experiment, about 24 measuring
  lines for the 49 lines of the two samples. The writer must find the
  groups, which means holding the whole block, as the code block's
  `L.Literal` already does.
- **Not a highlighting matter alone:** the same alignment would help
  the proportional style even with highlighting off, and touches only
  code blocks, not inline code.

### 8.4 Problems found on the way

- **mom's smart quotes:** inside `.QUOTE`, mom turned `"wide"` into
  “wide” (*seen*); ms and ConTeXt kept the straight quotes. A writer
  must write `\[dq]` for `"` in mom's proportional code, as the
  verbatim `.CODE` block does not need.
- **ConTeXt ligatures:** the proportional style is not verbatim, so
  TeX Gyre Termes' `--` and the like would form ligatures. The
  experiment wrote `-\kern0pt` for each `-`. podoc's ConTeXt writer
  needs the same for code.
- **Font changes per segment** (§8.2) in ConTeXt.
- **Not tried:** tabs kept with `--preserve-tabs`, lines longer than
  the measure (they would run into the margin, as code does now), and
  the samples at other point sizes.

### 8.5 Recommendation

The *hybrid* form, with *W* = 0.5 em and *G* = 1 em as defaults that
the user can change (variables in the templates, or options):

- it keeps the source's columns wherever the text fits, and moves a
  whole group of lines when it does not;
- ms and mom need only escapes and registers, ConTeXt the three
  macros above;
- *fixed* is the fallback if the cost of measuring is not wanted.

*Decided 2026-11-22* (V4; PLAN.md decisions 32 and 33): all three
forms, chosen with `--code-align` or `code-align` in the metadata,
hybrid by default, with *W* and *G* in the template variables
`code-column` and `code-gap`.
