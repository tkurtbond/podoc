# podoc and mom: scope, possibilities and risks of a pdfmom backend

Research done 2026-11-21. The question is whether podoc should write
groff's mom macros (`-t mom`) and make PDF from them with `pdfmom`
(`--pdf-engine=pdfmom`). It covers what that would take, what it
would give, and what could go wrong. podoc writes ms today and makes
PDF from ms with `groff -Tpdf` or `pdfroff`.

Sources:

- groff 1.23.0, 1.24.2 and 1.25.0 from `/usr/local/sw/versions/groff`.
  These include their `pdfmom` script and its manual page, mom's HTML
  manual (`share/doc/groff-1.25.0/html/mom`), `om.tmac`, `pdfpic.tmac`
  and the examples.
- "Producing PDFs with groff and mom" by Deri James and Peter
  Schaffter (`share/doc/groff-1.25.0/pdf/mom-pdf.pdf`; also at
  <https://www.schaffter.ca/mom/pdf/mom-pdf.pdf>).
- mom's home page, <https://www.schaffter.ca/mom/>, and its
  release page, `mom-05.html`.
- pandoc 3.10, both the program (`--list-output-formats`) and its
  source.
- podoc at 56b6952.
- The user's ms templates, `~/.pandoc/templates/{statement,tkb,digest}.ms`,
  and the user's mom files under `~/current/computer/doctools/groff`.
  These were only read.

Section 4 lists the experiments. They were run in
`/usr/local/sw/tmp/claude-podoc-mom`, which has since been removed.

## 1. Summary

- **mom is part of groff, and so is `pdfmom`.** Every groff the user
  has installed includes them:
  - 1.23.0 has mom 2.5_d;
  - 1.24.2 and 1.25.0 have mom 2.6_d, the release the home page calls
    current.

  `pdfmom` is a Perl script. It runs groff three times so that forward
  references resolve: the table of contents, links that print a
  heading's text, and the PDF outline. Perl is no new dependency,
  because gropdf, which `groff -Tpdf` already needs, is also Perl.
- **pandoc has no mom writer.** `pandoc --list-output-formats` lists
  none. That makes a mom backend podoc's first output with no pandoc
  oracle. AGENTS.md's "match pandoc, not a reading of its manual"
  cannot apply to it, and decision 3's "equivalent to pandoc 3.10's"
  has nothing to be equivalent to. It needs a decision of its own
  (§9, Q1).
- **The user's writing builds do not use mom.** All of their PDF
  builds use ms, with three templates of their own:
  - `statement.ms`, 165 lines;
  - `tkb.ms`, 187 lines;
  - `digest.ms`, 110 lines.

  These templates are ms register settings and redefinitions of ms
  macros (`.nr LL`, `.nr PS`, a redefined `.TL`, `GROWPS`). None of it
  carries over to mom. The user has experimented with mom, though:
  `~/current/computer/doctools/groff` holds nine `.mom` files from
  2023-12. They try columns, PDF links, heading styles and numbering,
  covers, and moving the table of contents (§7).
- **What mom would add over podoc's ms** (§3):
  - a typeset document design by default;
  - nine styled heading levels;
  - multiple columns (`.COLUMNS`);
  - a clickable table of contents that can be moved to the front;
  - covers;
  - endnotes as an alternative to footnotes;
  - captions and labels for figures and tables, and lists of them;
  - headers and footers by default;
  - document types: chapter, letter, slides.

  PDF links and outlines are not new: podoc's ms writer already makes
  them with `.pdfhref`.
- **The work is a new writer about the size of `PdMs`** (1,248 lines),
  plus a default template and a fourth PDF engine. Part of `PdMs` can
  be shared: escaping, font changes, and tbl tables (§5).
- **The main risks** (§8):
  - With no oracle, every output choice is podoc's own. Tests can
    check only that groff accepts the output and that the text
    survives into the PDF.
  - mom's own quirks: macros must start a line, and `\*[PREV]` does
    not nest.
  - Images need their size given, and groff 1.23's mom takes only PDF
    images.
  - The user's built-in filters (general.lua's `box`, `keep` and
    `for-format`) would need a mom branch that their Lua filter does
    not have.
- **Recommendation.** If the user wants a mom backend, schedule it as
  one phase with six subphases (PLAN.md's Phase 23, proposed). Start
  with the decisions in §9. Support groff 1.23 and later, with
  `-Tpdf` only. Leave ms as the default writer for PDF. If no document
  of the user's is to be built with mom, leave the backend in "Later":
  it would be the first feature with no use in the user's builds.

## 2. mom and pdfmom

### 2.1 mom

mom is a groff macro package by Peter Schaffter. The home page
describes how it is developed and released:

> Mom is officially part of groff, present in the groff git repository
> in the /contrib directory. Official releases of groff include the
> version of mom current at the time of the groff release.

and says that "mom is being developed independently of groff". The
current release is "version 2.6_d". Its notes say it adds image
insertion "without requiring conversion to EPS or PDF".

mom splits into two layers:

- **Typesetting macros:** `.FAMILY`, `.PT_SIZE`, `.LS`, `.L_MARGIN`,
  `.COLUMNS` and the like, and inline escapes such as `\*[IT]` and
  `\*[BD]`.
- **Document-processing macros**, which a podoc writer would use. A
  document is:
  - a header: `.TITLE`, `.SUBTITLE`, `.AUTHOR`, `.DOCTYPE`,
    `.PRINTSTYLE`, `.PAPER`, optionally `.COVER` and `.DOC_COVER`;
  - then `.START`;
  - then the body: `.HEADING n`, `.PP`, `.LIST`/`.ITEM`/`.LIST OFF`,
    `.BLOCKQUOTE`, `.QUOTE`, `.CODE`, `.FOOTNOTE`/`.FOOTNOTE OFF`,
    `.ENDNOTE`, `.EPIGRAPH`, `.PDF_IMAGE`, `.FLOAT`, and tbl, eqn and
    pic;
  - optionally `.ENDNOTES` and `.TOC` at the end.

  `.DOCTYPE` takes `DEFAULT`, `CHAPTER`, `NAMED`, `LETTER` or
  `SLIDES`. `.PRINTSTYLE` takes `TYPESET` or `TYPEWRITE`. `.COLLATE`
  joins documents.

### 2.2 pdfmom

`pdfmom(1)`: "a wrapper around groff(1) that facilitates the
production of PDF documents from files formatted with the mom
macros". Its two modes:

- **`-Tpdf`, the default**, uses gropdf. In groff 1.25.0's script it
  runs this pipeline:

  ```
  groff -Tpdf -dLABEL.REFS=1 -mom -z FILES 2>&1 | grep '^\. *ds' |
  groff -Tpdf -dPDF.EXPORT=1 -dLABEL.REFS=1 -mom -z - FILES 2>&1 | grep '^\. *ds' |
  groff -Tpdf -mom - FILES
  ```

  The first two passes print `.ds` definitions for forward
  references. The third reads them, then the files. The 1.23.0
  script runs the same commands; the differences are comments and
  copyright lines.
- **`-Tps`** passes everything to `pdfroff`. groff 1.24 and later do
  not include `pdfroff`. The 1.25.0 script stops with "Since version
  1.24.0 of groff, the pdfmark files (including pdfroff) are no
  longer included with groff". So `-Tpdf` is the only mode that works
  under every groff the user has.

Other points about pdfmom:

- It reads standard input into a temporary file, `pdfmom-XXXXX`.
- It accepts groff's options, so `-t`, `-e`, `-k`, `-K` and `-U`
  pass through.
- It writes the PDF to standard output.

mom-pdf.pdf §6.3: a page size set in the source with `.PAPER` or
`.PAGE` needs no `-P-p` option with `-Tpdf`. Pages of different
sizes are possible.

### 2.3 PDF features

From mom-pdf.pdf:

- **Outline.** It is built from `.HEADING` and the title macros
  (§4). `.PDF_BOOKMARKS_OPEN n` sets how many levels start open.
- **Destinations and links.** `.HEADING n NAMED id "text"` and
  `.PDF_TARGET id` make destinations.
  `.PDF_LINK id [PREFIX t] [SUFFIX t] "text"` links to one, and a
  link text ending in `*` or `+` prints the heading's own text. The
  forward references come from those, and so do pdfmom's passes.
- **External links.** `.PDF_WWW_LINK url [PREFIX t] [SUFFIX t]
  ["text"]`.
- **Link colour.** `.PDF_LINK_COLOR`.
- **Window title.** `.PDF_TITLE`; `.DOC_TITLE` sets it too.
- **Table of contents.** `.TOC`, last in the file. Its entries are
  links. With `-Tpdf`, `.AUTO_RELOCATE_TOC [TOP|...]` moves it to the
  front.

## 3. What mom would give podoc's users

Set against podoc's ms writer, which writes what pandoc's does:

| | ms, as podoc writes it | mom |
|---|---|---|
| PDF outline, links | `.pdfhref O`, `L`, `W`, `M` (pandoc's) | automatic outline, `PDF_LINK`, `PDF_WWW_LINK`, `PDF_TARGET` |
| Table of contents | `.TC` at the end (`.XS` entries) | `.TOC`, clickable; can go first (`AUTO_RELOCATE_TOC`) |
| Headings | `.NH`/`.SH`, 5 levels in practice | `.HEADING 1`–`9`, each styled; numbering by `HEADING_STYLE n NUMBER` |
| Notes | `.FS`/`.FE` footnotes | footnotes, or endnotes (`.ENDNOTE`, `.ENDNOTES`) |
| Columns | `.2C` (whole page) | `.COLUMNS n gutter`, also for the table of contents and endnotes |
| Figures | `.PDFPIC`, a centred caption | `.PDF_IMAGE ... CAPTION LABEL TARGET`, frames, `.FLOAT`, lists of figures |
| Tables | tbl | tbl, with `.TS H BOXED CENTER CAPTION LABEL` |
| Page design | the template's ms registers | `PRINTSTYLE TYPESET`, headers and footers, recto/verso, covers |
| Other documents | | `DOCTYPE LETTER`, `SLIDES`, `CHAPTER`; `COLLATE` |

The design and the document features are the gain. PDF navigation
is about even.

## 4. Experiments

A ten-element mom document was formatted with `pdfmom` under groff
1.23.0 and 1.25.0. It had a title, an author, a `NAMED` heading, a
paragraph with a footnote, a `PDF_LINK` to the heading, a bullet
list, a two-cell tbl table and `.TOC`.

- **Both groffs** made a 2-page PDF with the same text from
  `pdftotext`, an outline, and two link annotations. In 1.25 the
  annotations are inside compressed object streams; they were counted
  after `qpdf --object-streams=disable`. Neither printed a warning
  beyond `-w break`.
- **Size:** 18,677 bytes under 1.23.0 and 3,603 under 1.25.0. This is
  the same font-embedding difference seen with ms in Phase 22.
- **Tables:** without `-t`, 1.25's mom refuses tbl data. It prints
  "[mom]: 't.mom' contains tbl(1) data but '-t' flag is missing from
  the command line. Aborting." and pdfmom exits with status 4. podoc
  would always pass `-t`, as `PdPdf.Roff` does for ms.
- **Moving the table of contents:** `.AUTO_RELOCATE_TOC TOP` placed
  after `.START` left the contents at the end. Placed before
  `.START`, it put them on page 1, under both groffs. The template
  must put it in the header.
- **Images** (from `om.tmac`, not run):
  - mom 2.5_d (groff 1.23) takes only PDF images. It always requires
    `<width> <height>` with `PDF_IMAGE`.
  - mom 2.6_d (groff 1.24.2 and 1.25.0) takes any format ImageMagick reads, if
    ImageMagick and PerlMagick are installed. It finds the size itself
    only in unsafe mode (`-U`), through `pdfpic.tmac`, which runs
    `pdfinfo`, or `identify` or `file`.
  - In safe mode both versions need the size given.

## 5. The writer

### 5.1 Shape

A `PdMom` module, beside `PdMs`. It would share these with ms:

- escaping: `\` as `\e`, `\&` before a leading `.` or `'`, and
  special characters as `\[...]`;
- the font state, written as `\f[I]`, `\f[B]`, `\f[BI]` and `\f[CR]`
  with the font to return to (mom's `\*[PREV]` goes back only one
  font, so nested emphasis cannot use it);
- the tbl table writer;
- wrapping at `--columns` (Phase 18.1).

Moving these from `PdMs` into a shared `PdRoff` module first, with
ms output left byte for byte the same, keeps the two writers from
drifting apart. That is Phase 23.1.

### 5.2 From pandoc's AST to mom

What each element would become. "To check" marks a choice that the
mom manual leaves unclear. These must be tried in groff before they
are fixed.

| AST | mom |
|---|---|
| `Header n` | `.HEADING n NAMED id "text"` (the id from the attribute; `"` in the text as `\(dq`); `--number-sections` as `HEADING_STYLE n NUMBER` in the template |
| `Para` | `.PP`, then the text (mom does not indent the first paragraph after a heading) |
| `Plain` | the text |
| `BlockQuote` | `.BLOCKQUOTE` ... `.BLOCKQUOTE OFF` |
| `CodeBlock` | `.CODE` ... `.CODE OFF` in no-fill (to check: `CODE BR`, or `QUOTE` with `.CODE`) |
| `LineBlock` | `.QUOTE` ... `.QUOTE OFF`, which mom sets in no-fill (to check) |
| `BulletList` | `.LIST BULLET`, `.ITEM` per item, `.LIST OFF`; lists nest |
| `OrderedList` | `.LIST DIGIT\|ALPHA\|alpha\|ROMAN<n>\|roman<n>` with separator `.` or `)` and prefix `(`; the start number (to check: `ITEM`'s enumerator or mom's list reset) |
| `DefinitionList` | no mom element: the term in bold, the definition indented (`.IL`/`.IQ`), as the ms writer does with `.IP` |
| `HorizontalRule` | `.LINEBREAK` (mom's scene break), or a drawn rule from the template, as ms's `HLINE` |
| `Table` | tbl `.TS` ... `.TE`, through the shared writer; a caption as `CAPTION` |
| `Figure` | `.PDF_IMAGE -C file w h CAPTION "..."` for an image, and its id as `TARGET` |
| `Div` | its blocks; an id as `.PDF_TARGET id` |
| `RawBlock` | its text if the format is `mom` (and `roff`? Q7) |
| `Note` | `\c` at the end of the line, `.FOOTNOTE`, the blocks, `.FOOTNOTE OFF`; or `.ENDNOTE` (Q6) |
| `Emph`, `Strong` | font changes through the shared font state |
| `Code` | `\f[CR]` through the font state |
| `Strikeout`, `Underline`, `SmallCaps` | as the ms writer does (mom has none of its own) |
| `Superscript` | `\*[SUP]` ... `\*[SUPX]` |
| `Subscript` | `\v`-based strings from the template, as ms's `\*<` `\*>` |
| `Quoted` | `\(lq` `\(rq`, `\(oq` `\(cq` |
| `Link` to `#id` | a line break, then `.PDF_LINK id SUFFIX "..." "text"` with trailing punctuation moved to `SUFFIX`, so no space is added before it |
| `Link` elsewhere | `.PDF_WWW_LINK url SUFFIX "..." "text"`, broken out the same way |
| `Image`, inline | as the ms writer: mom has no inline images |
| `Math` | as the ms writer, the TeX text (`eqn` is in "Later" for ms too) |
| `LineBreak` | `.BR` |
| `Span` | its content; an id as `.PDF_TARGET` (`\c` around it) |
| `Cite` | its content |

The roff side brings two constraints:

- **Macros start lines.** Links, notes and targets break the line,
  as `.pdfhref` does in pandoc's ms writer. `PdMs` already breaks
  lines this way, and the mom writer would do the same.
- **Macro arguments are quoted.** Text inside them escapes `"` as
  `\(dq`, and a line break in a heading becomes a separate quoted
  argument ("another line").

### 5.3 Metadata and the template

pandoc has no mom template, so podoc would supply its own default
under podoc's licence. The variables:

- **Title block:**
  - `title` → `.TITLE` and `.DOC_TITLE`;
  - `subtitle` → `.SUBTITLE`;
  - `author` (a list) → `.AUTHOR "a" "b"`;
  - `date` → `.MISC`, or a cover;
  - `abstract` → a `.BLOCKQUOTE` after `.START` (mom has no
    abstract).
- **Table of contents:** `toc` → `.AUTO_RELOCATE_TOC TOP` before
  `.START` and `.TOC` last; `toc-title` → `.TOC_HEADER_STRING`.
- **Page:**
  - `papersize` → `.PAPER`, so `PdPdf.AddPaper`'s `-dpaper` is not
    needed;
  - `margin-left`, `-right`, `-top`, `-bottom` → `.L_MARGIN`,
    `.R_MARGIN`, `.T_MARGIN`, `.B_MARGIN`.
- **Type:**
  - `fontfamily` → `.FAMILY`;
  - `pointsize` → `.PT_SIZE`;
  - `lineheight` → `.AUTOLEAD` or `.LS`.
- **mom's own** (new variables, since pandoc has none):
  - `columns` → `.COLUMNS n gutter`;
  - `printstyle` (TYPESET by default);
  - `doctype`;
  - `linkcolor` → `.PDF_LINK_COLOR`.
- **The usual three:** `header-includes`, `include-before`,
  `include-after`.

`--template` works as for ms. The user's ms templates cannot be
reused (§1). A mom counterpart of `statement.ms` would set the page
(5.5×8.5 in), the type (Optima, 10/12) and the title's growth with
mom's own macros. Writing it is the user's work: their templates
stay read only. podoc can only show the way in its default template
and in docs/user/podoc.md.

### 5.4 The built-in filters

`PdFilters`' general filter (the user's `general.lua`) does some
things by output format:

- `box` becomes `.B1`/`.B2` for ms;
- `keep` becomes `.KS`/`.KE` for ms;
- tables are wrapped in `.na`/`.ad` for ms;
- `for-format` keeps blocks only for the named format.

mom has `.BOX` and `.BOX OFF`, but no `.KS`/`.KE` (its nearest is
`.FLOAT`). As things are, `-t mom` would drop `for-format ms` blocks
and lose boxes and keeps, with notes on standard error as for any
format the filter does not know. Adding a mom branch would make
podoc's filter differ from the user's Lua filter, which decision 6
and Phase 13 kept in step. That is Q8.

## 6. PDF through pdfmom

- **The engine.** `--pdf-engine=pdfmom` (also `--pdf-engine=PATH/pdfmom`,
  as for the others), the default when the writer is mom.
  `PdOptions.PdfWriterAndEngine` pairs `mom` with `pdfmom`, and
  `-o x.pdf` without `-t` keeps its present writer.
- **The command:** `pdfmom -t -k -KUTF-8 [-U] OPTS < source > output.pdf`
  in the temporary directory, as `PdPdf.Roff` runs groff.
  - `-e` is passed when eqn is used, as for ms.
  - `-U` is passed when there are images and their sizes come from
    `pdfpic.tmac` (§6.1).
  - `--pdf-engine-opt` adds options. `-Tps` is refused, or at least
    documented as needing a separate `pdfroff`.
- **Errors.** The exit statuses are those of the other engines: 47 if
  `pdfmom` is not found, 43 if it fails, with groff's messages.
  pdfmom prints `pdfmom: fatal error: groff exited with status N`.

### 6.1 Images

podoc already turns images into PDF for ms:

- SVG, PNG and JPEG with the converters (decision 23);
- EPS and PostScript with Ghostscript (decision 26).

The mom engine would always use the PDF, because mom 2.5_d takes
nothing else and because 2.6_d's own route needs ImageMagick and
PerlMagick at format time. The open part is the size `PDF_IMAGE`
needs (Q4):

1. **From the document**, when the image has `width` and `height`.
   Both are needed, and podoc must turn `%` and `em` into lengths.
2. **From `pdfinfo`** (poppler-utils), which podoc would run on the
   converted PDF. This is what groff 1.25's `pdfpic.tmac` does in
   unsafe mode, but groff 1.23's mom cannot do it.
3. **From the PDF itself**, by reading the first page's `/MediaBox`
   in podoc. This is simple for the PDFs podoc's converters write, but
   not for a PDF whose page objects sit in compressed object streams
   (PDF 1.5 and later). Users' own PDFs may be like that.

The recommendation is 1, then 2, then a warning and no image. That
needs no new code for PDF parsing, and it works with groff 1.23.

## 7. The user's mom experiments

The nine files in `~/current/computer/doctools/groff` (2023-12) use
these macros:

- `PP` 64 times and `HEADING` 40;
- `LIST` 8 and `ITEM` 9;
- `TITLE`, `AUTHOR`, `START` and `PRINTSTYLE`;
- `TOC` 4, `AUTO_RELOCATE_TOC` 4 and `COVER` 4;
- `COLUMNS` 4;
- `HEADING_STYLE` with `NUMBER`;
- `PDF_LINK`, `PDF_WWW_LINK`, `PDF_TARGET`, `PDF_TITLE` and
  `PDF_BOOKMARKS_OPEN`.

They are tests of mom, not documents built from markdown or rST. They
show which mom features the user cares about: columns, links, numbered
headings and a table of contents at the front. The plan puts those
first.

## 8. Risks

1. **No oracle.** Every other writer is checked against pandoc 3.10,
   and the reader byte for byte. For mom, podoc's own output is the
   only reference. Its tests can show:
   - that groff accepts the output without warnings
     (`groff -mom -z -ww`);
   - that the PDF holds the text, the pages, the outline and the
     links (`pdftotext`, `pdfinfo`, `mutool show ... outline`);
   - that the text matches the ms PDF made from the same input (the
     ms writer is checked against pandoc, so this is an indirect
     oracle).

   Layout, spacing and the look cannot be tested this way. They need
   the user's eye.
2. **A writer the user's builds do not use.** AGENTS.md's scope rule:
   "add a feature when the user's documents or filters need it, or the
   plan schedules it". This one would be scheduled by the plan, on the
   user's word. With no document built through it, bugs would be found
   late. A mom counterpart of one real build (say the 005-merchant
   statement) would serve as its test, once the user writes the
   template.
3. **mom's quirks.**
   - Macros must start a line, so inline links, notes and targets
     break the line.
   - Quoting rules apply to macro arguments.
   - `\*[PREV]` does not nest.
   - `AUTO_RELOCATE_TOC` works only before `.START` (§4).
   - mom aborts on tbl data without `-t`.
   - `PRINTSTYLE TYPEWRITE` underlining does not work with `-Tpdf`
     (mom-pdf.pdf §7).
   - The manual is in places unclear about code blocks, line blocks
     and list numbering (the "to check" rows of §5.2).
4. **Versions.**
   - groff 1.23's mom is 2.5_d, and 1.24.2's and 1.25.0's is 2.6_d. They
     differ in `PDF_IMAGE` (§4), in outline numbering (2.6_b) and in
     image formats.
   - gropdf before 1.25 needs PDF 1.4 images. podoc's converters
     already write PDF 1.4 (decision 26).
   - groff 1.23 PDFs are about five times larger (§4).
   - Tests must run under at least 1.23.0 and 1.25.0.
5. **Maintenance.** mom is maintained by one person, outside groff's
   own tree, and comes into groff at each release. pdfmom is
   maintained by Deri James, gropdf's author. Both have been stable:
   the 1.23 and 1.25 pdfmom run the same commands. A mom change would
   reach podoc only through a new groff.
6. **Other systems.** Of the six BSD VMs, two have groff; whether
   their groffs include mom and pdfmom is unchecked. The PDF tests
   would skip where `pdfmom` is missing, as `pdf-eps` skips today.
7. **Size of the work.** About 1,000–1,400 lines for `PdMom`, plus
   about 200 moved into `PdRoff`, 60 in `PdPdf` and 30 in `PdOptions`,
   a 100-line template, case tests and documentation. That is a phase
   the size of Phase 8 (the ms writer) plus Phase 21's engine work.

## 9. Questions for the user

Answered by the user on 2026-11-21: PLAN.md's decision 27. Q4 took
option (a); Q5 mom's defaults with all the listed variables, and an
example statement template; Q6 endnotes on request; Q7 raw `mom`
only, passed unchanged; Q8 a `for-format mom` class and `box` and
`keep` for mom.

- **Q1. Schedule it?** A mom backend is podoc's first output with no
  pandoc counterpart (decision 3's "equivalent to pandoc 3.10's" cannot
  apply) and no use in the user's builds today. Options:
  - schedule it as Phase 23;
  - leave it in "Later";
  - drop it.
- **Q2. Names.** `-t mom` (and `.mom` for `-o`), and
  `--pdf-engine=pdfmom`, the default for mom. `-o x.pdf` with no `-t`
  stays ms. Recommended as stated.
- **Q3. groff versions and devices.** groff 1.23 and later, with
  `-Tpdf` only (no `pdfroff`, no `-Tps`). Recommended.
- **Q4. Image sizes:**
  - (a) the document's `width` and `height`, then `pdfinfo`, then a
    warning (recommended);
  - (b) podoc reads `/MediaBox` itself;
  - (c) require `-U` and groff 1.24 or later.
- **Q5. The default template's look:**
  - mom's own defaults, `TYPESET` and `DEFAULT` (recommended:
    that is what mom is for);
  - or as close to pandoc's ms default as mom allows.

  Also: which mom-only variables (`columns`, `printstyle`, `doctype`,
  `linkcolor`, covers)?
- **Q6. Notes.** Footnotes always, as ms? Or endnotes on request?
  pandoc's `--reference-location=document` would be the natural
  switch, but pandoc does not use it for ms.
- **Q7. Raw formats.** Raw blocks and inlines kept for `mom` only
  (recommended), or for `roff` too? Raw `ms`, as in the user's rST
  files (`raw:: ms`), would be dropped, since ms macros do not work
  under mom.
- **Q8. The built-in filters.** Should the general filter give mom
  `.BOX`/`.BOX OFF` for `box` and a keep for `keep`, and treat
  `for-format mom`? That would go past the user's `general.lua`,
  which does nothing for a mom format.
