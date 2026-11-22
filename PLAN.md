# Plan

podoc is a proof of concept: an Oberon-2 program, built with `poc`,
that does what the user's writing builds need from pandoc. It reads
pandoc markdown with YAML metadata and writes HTML, groff `ms`,
ConTeXt and markdown, and drives `pdfroff`, `groff -Tpdf` and `context`
to make PDFs. The user's Lua filters and `pandoc-include` are built in.

The research behind this plan, and the reasons for its choices, are in
[docs/research/podoc-scope.md](docs/research/podoc-scope.md). Section
numbers below (§n) refer to it. The user's decisions on its open
questions are recorded under "Decisions" below.

Each phase ends with its tests passing under `-O2` and `-OC` and a
commit. A phase is marked `[done]` in its heading when it is, and the
State section at the end records what was verified.

## Goal and scope

- Input: pandoc markdown (§3.1), with YAML metadata blocks (§9).
- Output: HTML5, `ms`, ConTeXt, markdown, plain text (decision 10),
  and JSON (pandoc's AST, as the test oracle) (§3.2).
- PDF through `pdfroff`, `groff` or `context` (§7).
- The command-line options the user's GNUmakefiles pass to pandoc, so
  that `make PANDOC=podoc` works (§2, §4).
- Built-in equivalents of `subs.lua`, `strip-comments.lua`,
  `general.lua`, `toc-columns.lua`, `combine-docs.lua` and
  `pandoc-include` (§4, §5).
- Output equivalent to pandoc 3.10's (decision 3): the same AST, and
  writer output that gives the same PDF or rendered HTML.

Not in scope: other input formats (reStructuredText came into scope
on 2026-11-20, decisions 18 to 22, Phase 19);
citations; mermaid (decision 4); Lua filters (decision 6); VAX/VMS
(decision 1). Plain text output, grid tables (reader and writers) and
output wrapping came into scope on 2026-11-20 (decisions 10 to 15,
Phases 16 and 17).

## Decisions

Made by the user on 2026-11-20, on the questions of §15.

1. **No VAX/VMS.** podoc is for LLVM targets: Linux and the BSDs. C
   parts are acceptable where they earn their place, and pounicode is
   usable everywhere podoc is.
2. **YAML: start with the small Oberon reader** (§9). polibfyaml stays
   available as an alternative: libfyaml is not a hard prerequisite to
   meet, so a `make YAML=libfyaml` build is a reasonable later step if
   the subset falls short.
3. **Equivalent output is enough.** The reader's JSON must match
   pandoc's exactly (that is what makes it a usable oracle); the
   writers' output must be equivalent, with known differences listed
   in the user documentation.
4. **No mermaid.** `--filter pandoc-mermaid-selenium-filter` is
   accepted with a warning and does nothing, leaving mermaid blocks as
   code blocks.
5. **Substitutions may use a new format.** The table moves from
   `substitutions.lua` to YAML metadata (Phase 13.2).
6. **No Lua for now.** Embedded Lua stays a later possibility, if a
   need appears; it is not scheduled.
7. **A full markdown writer** for the `-whole.md` targets (Phase 10),
   not a textual expansion of the includes.
8. **The name `podoc` and pandoc's command line.**
9. **`.br` after a heading's text in ms, before its `.pdfhref`
   lines** (2026-11-20), when a PDF engine is set. pandoc writes none;
   without it groff 1.25's `.SH` and `.NH` box the `.pdfhref` lines
   with the heading, print them, and make no bookmarks. Listed in
   docs/user/differences.md.
10. **Plain text output, with grid tables and wrapping**
    (2026-11-20). `-t plain` is added (Phase 16), and grid tables in
    the writer and output wrapping at `--columns`, which it needs to
    match pandoc's default output, come into scope with it.
11. **Wrapping for markdown too** (2026-11-20). `--wrap=auto` and
    `--columns` apply to `-t markdown` as well as to `-t plain`
    (Phase 17.2).
12. **The `gutenberg` extension** (2026-11-20): `-t plain+gutenberg`
    is supported (Phase 16.4).
13. **Grid tables in the reader** (2026-11-20), as pandoc's markdown
    reader reads them (Phase 16.2).
14. **The markdown writer writes grid tables where pandoc does**
    (2026-11-20), instead of HTML (Phase 16.3).
15. **The markdown writer writes pipe tables where pandoc does**
    (2026-11-20), instead of HTML (Phase 16.3).
16. **Wrapping for ms and ConTeXt** (2026-11-20). `--wrap=auto` and
    `--columns` apply to `-t ms` and `-t context` as well (Phase 18),
    so that their default output is pandoc's, byte for byte. HTML
    stays unwrapped (in "Later"): `PdHtml` writes ropes, not
    `PdLayout` Docs, and wrapping it as pandoc does would mean
    restructuring the writer for output a browser shows the same.
17. **Emoji widths as doclayout's** (2026-11-20). `PdWidth` joins
    emoji sequences as doclayout's `realLength` does, from emojis
    0.1.5's base emoji (Phase 18.3), so that a line or table holding
    `🏛️` (U+1F3DB U+FE0F) and the like is laid out as pandoc lays
    it out.
18. **A reStructuredText reader** (2026-11-20). podoc reads rST as
    pandoc 3.10's `-f rst` does, its JSON matching pandoc's byte for
    byte (docs/research/rst-implementation.md). This reverses "Not in
    scope: reStructuredText" in the goal above.
19. **No rST writer for now** (2026-11-20). `-t rst` goes to "Later":
    no build writes rST with pandoc.
20. **All of pandoc's rST reader** (2026-11-20), not only what the
    user's pandoc-built files use: every directive and role
    `Readers/RST.hs` handles, held to pandoc's `test/rst-reader.rst`,
    `test/tables.rst` and the command tests that read rST, as well as
    to the user's files.
21. **The rST of the docutils and Nikola projects too** (2026-11-20).
    podoc must read the standard rST in the `.rst` files the user
    builds with docutils (`current/RPG/Campaigns/Possible`,
    `current/RPG/WVHTCF`, ...) and with Nikola
    (`~/Repos/tkurtbond.github.io`), as pandoc reads them. podoc does
    not take over those tools' output: not docutils' LaTeX writer,
    not Nikola's templates, blog pages or its own directives and
    roles. Those come out as pandoc gives them: an unknown directive
    as a `Div` with its name as a class, an unknown role as `Code`
    with the class `interpreted-text`.
22. **Reporting what the rST reader drops** (2026-11-20). By default
    podoc is silent, as pandoc is; `--verbose` prints pandoc's
    `[INFO] Skipped ...` lines. A podoc option, proposed as
    `--unknown=warn|error` (the name can change when it is built),
    reports, with file, line and column, every unknown directive and
    role and anything else pandoc drops or skips: as a warning, or as
    an error ending podoc with status 64. podoc's own addition, to be
    listed in docs/user/differences.md.

23. **Images in ms output** (2026-11-20). pandoc's ms writer writes
    `.PDFPIC` only for `.pdf` files and `.PSPIC` for `.ps` and `.eps`;
    any other image (SVG, PNG, JPEG) becomes a groff comment and is
    missing from the PDF, and pandoc converts images only for its TeX
    engines. podoc will convert such images to PDF and write
    `.PDFPIC`, both for PDF output and for `-t ms`. A deliberate
    difference from pandoc, to be listed in docs/user/differences.md.
    Planned as Phase 21. Decided on 2026-11-20 too:
    - **Converters:** bitmaps are converted with the first of
      `img2pdf`, `magick` (or ImageMagick 6's `convert`) and `gm
      convert` found (img2pdf keeps JPEGs unchanged and keeps
      transparency; gm loses transparency).
      **Changed 2026-11-21, during Phase 21; confirmed by the user the
      same day:** `gm` is not used. GraphicsMagick 1.3.45's PDFs hold a malformed
      object (`<< >> endstream` with no `stream`), and gropdf fails on
      them in groff 1.23.0, 1.24.2 and 1.25.0. The chain is `img2pdf`,
      then `magick` (or `convert`). And for groff, `rsvg-convert` is
      asked for PDF 1.4 (`-f pdf1.4`): gropdf in groff 1.23.0 and
      1.24.2 rejects the PDF 1.5 and later cairo writes by default
      (1.25.0 reads both).
    - **`--extract-media=DIR`**, pandoc's option: podoc copies local
      images into `DIR`, as pandoc does, and converts them there too.
    - **Without it,** `-o out.ms` puts the converted images in
      `out-media/` beside `out.ms`. groff finds `.PDFPIC` files from
      the directory it runs in, not the `.ms` file's, so the paths
      written work with groff run in the output's directory. (This
      replaces the user's first idea, one temporary directory for
      the `.ms` and the PDFs.)
    - **To standard output,** without `--extract-media`, the images
      keep pandoc's output and podoc warns, suggesting
      `--extract-media`.
    - **Names:** the image's name with `.pdf` (`map.png` gives
      `map.pdf`); a number is added when two would clash.
    - **Resolution:** the converter is given 96 dpi, pandoc's default
      `--dpi`, for an image with none of its own, so an image's size
      does not depend on which converter is installed.
    - **Case:** `.pdf`, `.ps` and `.eps` are matched exactly, as
      pandoc does; the extensions to convert ignore case.

24. **The heap limit** (2026-11-20). podoc keeps poc's default heap
    limit, 1 GB, which inputs above about 35 MB reach; the environment
    variable `PODOC_HEAP_LIMIT`, a number of megabytes, changes it
    (`GarbageCollectedHeap.SetHeapLimit`). A value that is not a
    positive number ends podoc with status 6; one too big for the
    machine's addresses is taken as the most they allow. Chosen over a
    bigger default (4 GB on 64-bit systems, 2 GB on 32-bit) and over no
    limit, which would let a runaway reach the OOM killer.
25. **Links in rST footnotes are resolved** (2026-11-21). pandoc's
    rST reader leaves named hyperlink references (`` `name`_ ``),
    anonymous ones and substitutions in a footnote's text unresolved,
    with its placeholder URLs (`##REF##name`, `##SUBST##|name|`); podoc
    resolves them, after the rest of the document, so that the main
    text and its anonymous references stay pandoc's. A footnote
    reference inside a footnote stays as pandoc leaves it
    (`##NOTE##2`): resolving it would nest one note in another, which
    no writer, pandoc's or podoc's, renders properly. None of the
    user's 73 rST files is affected.

26. **EPS images in PDF made with groff** (2026-11-21). pandoc's ms
    writer writes `.PSPIC` for `.eps` and `.ps` images, which
    `groff -Tpdf` (gropdf) ignores, so with `--pdf-engine=groff`, the
    default for ms, they are missing from the PDF; `pdfroff` showed
    them, but groff 1.24 and later do not include `pdfroff`. Asked for
    by the user after the 005-merchant scenario's figures (`for-format
    ms`, `.gen.eps`) went missing under groff 1.25.0: for PDF made with
    `groff`, podoc converts local `.eps` and `.ps` images (matched
    exactly, as pandoc matches them) to PDF with Ghostscript (`gs
    -sDEVICE=pdfwrite -dEPSCrop -dCompatibilityLevel=1.4`, PDF 1.4 for
    gropdf before 1.25) and writes `.PDFPIC`. `pdfroff` and `-t ms`
    output keep `.PSPIC`, which `groff -Tps` shows. Planned and done
    as Phase 22.

27. **mom output and PDF through pdfmom** (2026-11-21), on the
    questions of docs/research/pdfmom-backend.md §9. Scheduled as
    Phase 23 (Q1). Its acceptance target is the 005-merchant
    scenario (`return-005-merchant.rst`), made as close as mom allows
    to its statement-sized ConTeXt PDF: the contents at the start, a
    statement page (5.5 by 8.5 in), and the figures. The pages need
    not break in the same places.
    - **Names** (Q2): `-t mom`, `.mom` for `-o`, and
      `--pdf-engine=pdfmom`, the default for mom. `-o x.pdf` with no
      `-t` stays ms.
    - **groff** (Q3): 1.23 and later, `-Tpdf` only (no `pdfroff`, no
      `-Tps`).
    - **Image sizes** (Q4, option a): from the image's `width` and
      `height`; a percentage width is of the line length, so
      `:width: 100%` is the line length. Without them, from `pdfinfo`
      on the PDF podoc made, scaled down to the line length when
      wider; without a size, podoc warns and leaves the image out.
      `PDF_IMAGE` always gets its size, so groff 1.23 (mom 2.5_d)
      works and pdfmom needs no `-U`.
    - **The default template** (Q5): mom's own design (`TYPESET`,
      mom's defaults), with the variables `columns`, `printstyle`,
      `doctype`, `linkcolor` and covers. podoc also ships an example
      template like the user's `statement.ms` (statement page,
      Optima, the contents first), which the user may copy; podoc
      never writes to `~/.pandoc`.
    - **Notes** (Q6): footnotes, or endnotes with
      `--reference-location=document` (settled by the user the same
      day).
    - **Raw formats** (Q7): raw `mom` blocks and inlines are passed to
      mom unchanged, so they may hold anything mom accepts, roff
      requests and escapes included. Other raw formats, `ms` and
      `context` among them, are dropped. The scenario's page break
      before "Map" is the user's to add, as a `raw:: mom` with
      `.NEWPAGE`.
    - **The built-in filters** (Q8): `for-format` gets a `mom` class,
      kept only by the mom writer; mom does not take the `ms` or
      `context` blocks. The general filter gives mom a box for `box`
      (`.BOX`, or a drawn frame if mom 2.5_d has none) and a keep for
      `keep`, going past the user's `general.lua`.

28. **No LaTeX backend** (2026-11-22). After the research in
    docs/research/latex-backend.md, the user decided that podoc will
    not write LaTeX or make PDF through TeX engines: podoc makes PDF
    with groff (ms and mom) and ConTeXt. The plan that was proposed,
    numbered L1, is kept in that document's §10.

29. **No port of skylighting** (2026-11-22). After the research in
    docs/research/syntax-highlighting-big.md, the user decided that
    highlighting through a port of skylighting (its regex engine,
    tokenizer and 164 syntax files, for ms, mom and ConTeXt) is too
    big, and will not be done. podoc keeps writing code plain. A
    smaller form of highlighting, or accepting pandoc's highlighting
    options, is a separate question, not settled here.

30. **Comments in italic in the proportional style** (2026-11-22).
    After the research in docs/research/vgrind.md (its question V1),
    the user decided that the proportional style of the small
    highlighting design (docs/research/syntax-highlighting-small.md)
    sets comments in italic, as vgrind does, as well as reserved words
    in bold.

31. **Reserved-word lists in podoc's own format only** (2026-11-22).
    On vgrind.md's question V3, the user decided that podoc reads
    users' reserved-word lists in its own format only, not in
    vgrindefs format.

32. **Column width and gap for aligned code** (2026-11-22). On
    vgrind.md's question V4, part 2: if the proportional style aligns
    columns (vgrind.md §8), the defaults are 0.5 em per source column
    (*W*) and a least gap of 1 em (*G*), and the user must be able to
    change both. The form of alignment (V4 part 1) is decision 33.

    How they are changed (decided the same day): through template
    variables, `code-column` and `code-gap`, set with `-V` or in the
    metadata like podoc's other variables. Each value is a plain
    number of ems (`code-column: 0.4`), so one setting serves every
    format; each template adds its own unit (`m` in ms and mom, `em`
    in ConTeXt) and holds the default:

    ```
    .nr PdCodeCol $if(code-column)$$code-column$$else$0.5$endif$m
    .nr PdCodeGap $if(code-gap)$$code-gap$$else$1$endif$m
    ```

    ```
    \newdimen\PdColumn \PdColumn=$if(code-column)$$code-column$$else$0.5$endif$em
    \def\PdGap{$if(code-gap)$$code-gap$$else$1$endif$em}
    ```

    The writer writes source column numbers, not lengths
    (`\h'|28*\n[PdCodeCol]u'`, `\PdSeg{28}{...}`), so its output does
    not depend on the widths and no command-line option is needed.
    Not yet verified: the experiment wrote lengths directly. Ems are
    fixed at the body size where the template sets them.

33. **The form of alignment is a choice** (2026-11-22). On vgrind.md's
    question V4, part 1: the user chooses the form with podoc's own
    option `--code-align=none|fixed|elastic|hybrid`, or with
    `code-align` in the document's metadata. The default is `hybrid`.
    - `none`: the proportional style with spaces kept as they are;
    - `fixed`, `elastic`, `hybrid`: as in vgrind.md §8.1.

    The option changes what the writer writes (fixed writes no
    measuring lines), so it is read by the writer, not only by the
    template. When both are given, the command line wins, as pandoc's
    `-M` wins over a document's metadata. Being podoc's own, it goes
    in docs/user/differences.md when it is implemented.

34. **mom code blocks at the left margin** (2026-11-22). `PdMom`
    writes code blocks as mom's `.QUOTE` with `.CODE`, as mom's
    documentation advises, and `.QUOTE` indented them by about an inch
    (75 pt). The user preferred them at the margin, with the indent a
    template variable: `default.mom` and `statement.mom` set
    `.QUOTE_INDENT $if(code-indent)$$code-indent$$else$0$endif$`.
    `code-indent` takes mom's own argument, as the other mom variables
    do (`2m`, `1P`, or a whole number of paragraph indents). `PdMom`
    uses `.QUOTE` only for code blocks. Its `.CODE OFF` before
    `.QUOTE OFF`, which mom's documentation calls unneeded, was kept:
    removing it moved nothing, on one page or across eight.

35. **The code style option** (2026-11-22). On
    syntax-highlighting-small.md's Q1: the option is
    `--code-style=none|mono|proportional`, and `code-style` in the
    metadata sets it too. The default is `none`. A single code block
    overrides it with a class: `.mono`, `.proportional` or `.plain`
    (for `none`), as ```` ```{.oberon .proportional} ```` in markdown
    or `:class: proportional` in rST. The block's class wins, then the
    command line, then the metadata.

36. **The ms code font** (2026-11-22). On the study's Q6: ms code
    blocks are written with `\f[CR]`, not `\f[C]`, which groff 1.25
    cannot open; a change of its own (Phase 24.2), and a difference
    from pandoc for docs/user/differences.md.

37. **mom's proportional code in roman** (2026-11-22). On the
    study's Q7: the proportional style keeps `.QUOTE`, set in roman
    with `.QUOTE_FONT R` before the block.

38. **Inline code is highlighted, in the code font** (2026-11-22). On
    the study's Q2: inline code with a language class gets its
    reserved words in bold, in either style, and stays in the code
    font even in the proportional style, since in the text font it
    would be hard to tell from the running text.

39. **Pascal: a list per mode** (2026-11-22). On the study's Q4: each
    FreePascal mode has its own list, chosen by the class (`objfpc`,
    `delphi`, `fpc`, `tp`, `macpas`, `iso`; study §5.4). Plain
    `pascal` means `fpc`, FreePascal's default mode (decided
    2026-11-22).

40. **Users' lists from files and metadata** (2026-11-22). On the
    study's Q5: both `--keywords=pascal:words.txt` and the metadata
    field `keywords` (study §6). A list adds to the built-in one
    unless it says otherwise; both forms are accepted (decided
    2026-11-22):
    - in a file, a first line `#!replace` makes the file replace the
      built-in list, and a line `-word` removes that word from it;
    - in the metadata, a plain list adds, and
      `keywords: {pascal: {replace: true, words: [...]}}` replaces;
      `-word` in a list removes.

41. **Oberon variants** (2026-11-22). On the study's Q8: the built-in
    lists know original Oberon, Oberon-2, Oberon-07 and Component
    Pascal, each as a class; `oberon` means Oberon-2. The classes
    (decided 2026-11-22): `oberon` and `oberon2` for Oberon-2,
    `oberon1` and `oberon87` for the original, `oberon07` for
    Oberon-07, `cp` and `componentpascal` for Component Pascal.

42. **Code with no known language** (2026-11-22). On the study's Q9:
    in the proportional style, a code block with no class or an
    unknown one is still set in the text font and aligned, with
    nothing in bold.

43. **Comments in italic in mono too** (2026-11-22). On the study's
    Q10: the mono style sets comments in italic monospace, as the
    proportional style does (decision 30).

44. **Strings are left whole** (2026-11-22). On the study's Q11: a run
    of two or more spaces inside a string literal does not start an
    alignment segment; the spaces are part of the string's value, not
    layout.

45. **Built-in lists hold reserved words only** (2026-11-22). On the
    study's Q3: words a language reserves, and nothing else. Oberon's
    predeclared identifiers, FreePascal's modifiers, C++'s contextual
    words, C's preprocessor names and sh's builtins can all be names,
    so bolding them would sometimes be wrong; a user who wants them
    adds them with a list (decision 40).

46. **HTML output too** (2026-11-22). The study left HTML out (its
    §2); the user added it, as Phase 24.5. The scanner and the lists
    are shared; only the writing differs:
    - *mono*: reserved words in `<b>`, comments in `<i>`, inside the
      `<pre><code>` written now;
    - *proportional*: `pre` in the body font, and only the `fixed`
      alignment: each segment a `<span>` placed at `left:` its
      column times `code-column`, in a line that is
      `position:relative`. `elastic` and `hybrid` need the text
      measured, which HTML cannot do without JavaScript; with HTML
      they fall back to `fixed`.
    - The CSS goes in the template inside `$if(...)$`, so the output
      with the style `none` stays byte for byte as it is now.
    - The text inside `<pre>` is unchanged, so copying it from a
      browser gives the code exactly.
    - It does not imitate pandoc's skylighting markup (a `<span>`
      per token, numbered lines, colour).

The user also accepted the other recommendations of §8.4 and §15:
native filters, a pure-Oberon core where there is a choice, and the
JSON AST compared byte for byte.

## Design

- **Pure Oberon where there is a choice.** The core has no C, so it
  builds wherever poc does. Optional C (libfyaml through polibfyaml)
  stays behind a build option.
- **Pipeline:** read (markdown and YAML) → AST → includes → filters →
  writer → template → (PDF engine). Each stage is a module, and the
  AST is the only thing they share.
- **The AST mirrors pandoc's** (pandoc-types 1.23): the same block and
  inline constructors, `Attr` as identifier, classes and key-value
  pairs, and `Meta` as a map of `MetaValue`s. Mirroring it is what
  makes the JSON oracle possible and the filters easy to port.
- **Text is held in Ropes** (`~/Repos/Oberon/Ropes`, §12.1) in the
  AST: every string field is a `Ropes.Rope`, NIL being the empty
  string. The reader works on the input as one flat `ARRAY OF CHAR`,
  for speed, and makes Ropes only for the text it keeps. **Writers
  write straight to `PdIO`'s buffered output**, and build a Rope only
  where output must be held and spliced (a template's body, a table
  of contents); a Rope is written leaf by leaf (`PdIO.WriteRope`,
  through `Ropes.IterateChunks`), never flattened. Measured in Phase
  2.1 (2026-11-20), on 774 KB of input (the Lost-Worlds and
  Galactic-Bounty-Hunters sources, twice over; 122,960 Str nodes):
  making the nodes took 22 ms (`-O2`) and 19 ms (`-OC`); writing
  JSON-like output of 4.7 MB built as one Rope by `Cat` (depth 40)
  took 89 and 85 ms, and written directly through `PdIO`, 10 and 12
  ms; the whole run 0.12 s and about 75 MB. Both are fast enough;
  writing directly is about 8 times faster and uses less memory.
- **Writers build `PdLayout` Docs** (2026-11-20), doclayout's `Doc`
  ported to Oberon: templates interpolate Docs, indent them and wrap
  them, which flat output cannot do. A writer builds a Doc for the
  body and each metadata value, `PdTemplate` renders the template
  around them, and `PdLayout.Render` makes the Rope that `PdIO`
  writes. Writing straight to `PdIO` stays the way for output with no
  template (`-t json`).
- **Modules** (names prefixed `Pd` to stay clear of the runtime's
  global module namespace):
  - `PdIO`: reading input whole, buffered output, messages and exit.
  - `PdSource`: the inputs prepared and joined as pandoc does.
  - `PdAst`: the AST, constructors, a generic walk.
  - `PdJson`: the JSON writer.
  - `PdYaml`: the YAML subset.
  - `PdMdBlocks`, `PdMdInlines`, `PdMarkdown`: the reader.
  - `PdIdent`: automatic identifiers.
  - `PdLayout`: doclayout's `Doc`, rendered at a width.
  - `PdTemplate`: the doctemplates language.
  - `PdContext`: a template's context, the variables, and finding
    templates; `PdDefaults`, written by `tools/mktemplates`, holds
    the built-in templates.
  - `PdHtml`, `PdMs`, `PdConTeXt`, `PdMdWriter`: the writers, with
    shared helpers in `PdWrite`.
  - `PdInclude`: `!include`.
  - `PdFilters`: the native filters.
  - `PdPdf`, `PdRun`: temporary directories and running engines.
  - `PdOptions`: the pandoc-compatible command line.
  - `podoc`: the main module.
- **Errors** the user can cause (a missing file, a bad option, a
  syntax error) are reported as `podoc: ...`, with the file name and
  line where there is one, and end the program with pandoc's exit
  status for that error (`Text.Pandoc.Error`: 1 for input and output,
  6 for options, 22 for an unknown output format, and so on), so that
  a build sees what it would from pandoc. HALT, with a code in
  podoc's own range (below), is kept for what should never happen.

## Halt codes

podoc is an application, so its codes start at 100, as in the other
Oberon projects: the runtime uses 10..20 and the po* libraries 61..99.
The table is kept in AGENTS.md as codes are assigned.

## Testing

- `make test` builds and runs `test/<Name>Test.Mod` unit tests, which
  print `ok   - ` and `FAIL - ` lines, compared with
  `test/<Name>Test.expected`, and the case tests (`tools/runcases`):
  each `test/cases/<name>.md` is converted by podoc, with the extra
  arguments in `<name>.args` if there is one, and compared with the
  committed `<name>.json`, `<name>.html`, `<name>.ms`,
  `<name>.context`, `<name>.markdown` and `<name>.source` that exist
  beside it; standard error with `<name>.errors`, or nothing. Both
  run under `-O2` and `-OC`. `make test` does not need pandoc.
- The expected `.json` files are pandoc 3.10's, unchanged. The writers'
  expected files start as pandoc 3.10's `--wrap=none` output; where
  podoc's output differs but is equivalent (decision 3), the file is
  replaced by podoc's, after checking, and the difference is recorded
  in `docs/user/differences.md`.
- `make compare` (only where pandoc is installed) runs pandoc and
  podoc side by side over a list of inputs and shows the differences:
  the user's documents and the pandoc fixtures listed in
  `test/pandoc-cases.txt`. For PDFs it compares `pdftotext` output.
- `tools/mkcase` makes a case's expected files with pandoc.

## Phase 1: The repository and the skeleton [done]

### Phase 1.1: Repository files and the build [done]

- `README.md`, `LICENSE` (BSD 3-Clause, as the other Oberon projects),
  `.gitattributes`, `.gitignore`.
- `GNUmakefile`: `make` builds `podoc` under `-O2` and `-OC` in
  `build/O2` and `build/OC`; `make test`; `make clean`.
- Check that each dependency (ArgParser, pounicode, Ropes) is installed
  for both size models, and record in AGENTS.md how to install a
  missing one.

### Phase 1.2: A program that runs [done]

- `podoc` reads files named on the command line (or standard input),
  joins them as pandoc does, and writes them unchanged to `-o` or
  standard output (`-t source`). pandoc's joining
  (`App/Input.hs`, `Sources.hs`): each input has a UTF-8 BOM dropped
  and its CRs removed, its tabs expanded to `--tab-stop` (4) counted in
  characters, and a final new line ensured (none of this with
  `--preserve-tabs`), and then a new line appended.
- `--version` and `--help`.
- A first case test, to prove the harness.

## Phase 2: The AST and the JSON writer [done]

### Phase 2.1: `PdAst` [done]

- Types for every block and inline constructor of pandoc-types 1.23
  that §3.1 needs, plus the rest as stubs that the JSON writer can
  still print.
- `Attr`, `Meta`, `MetaValue`; lists of blocks and inlines.
- A walk with callbacks for blocks and inlines, in pandoc's order, to
  serve the filters.
- Settle the use of Ropes (Design): measure building and writing a
  document the size of the largest Lost-Worlds build; record the
  result here. Done: see Design, "Text is held in Ropes".

### Phase 2.2: `PdJson` writer [done]

- Write `-t json` exactly as pandoc does: compact, field order, the
  `pandoc-api-version`, string escapes (pandoc escapes only what JSON
  requires), and numbers.
- Unit test by building small ASTs by hand and comparing with
  pandoc's JSON for the same documents.
- `-t json` on podoc's command line comes with the reader, Phase 3.

## Phase 3: The markdown reader, blocks [done]

### Phase 3.1: Lines and the block structure [done]

- Read UTF-8 text into lines, tabs expanded to four columns as pandoc
  does, and keep line numbers for messages.
- Paragraphs, ATX headers, setext headers, horizontal rules, block
  quotes (with laziness), indented and fenced code blocks (with
  attributes and info strings), blank lines.

### Phase 3.2: Lists [done]

- Bullet and ordered lists, with pandoc's rules: the four-space rule
  for continuation, lazy continuation, tight and loose lists, list
  styles and delimiters (`1.`, `1)`, `(1)`, `#.`, `a.`, `i.`), starting
  numbers, nesting.
- Cases for each rule, taken from pandoc's `testsuite.txt` and the
  user's `Includes/` stat blocks.

### Phase 3.3: Raw blocks, HTML blocks and line blocks [done]

- ```` ```{=format} ```` raw blocks.
- HTML blocks kept as `RawBlock "html"`.
- Line blocks (`| `).
- Brought forward from Phase 4.6, because the block structure needs
  them: fenced and HTML divs, definition lists, header attributes and
  identifiers (ASCII letters only so far), and task list items.
- Left for Phase 4: Unicode letters in identifiers and words, the full
  table of named entities (only `&amp;`, `&lt;`, `&gt;`, `&quot;`,
  `&apos;` and numeric references so far), entities in HTML attribute
  values, raw inline HTML and TeX (an HTML comment on a list item's
  continuation line is read as a block, not as pandoc's `RawInline`),
  emphasis, links, smart punctuation, implicit figures, tables, notes,
  reference keys, abbreviations, raw TeX blocks, the title block and
  YAML (Phase 5).

## Phase 4: The markdown reader, inlines [done]

### Phase 4.1: Text, escapes and code [done]

- `Str`, `Space`, `SoftBreak`, `LineBreak` (two spaces and backslash
  newline), backslash escapes, entities, inline code with attributes,
  raw inlines `` `x`{=ms} ``.

### Phase 4.2: Emphasis [done]

- `*` and `_` emphasis and strong emphasis, with pandoc's rules for
  intraword underscores and for nesting, and `~~` strikeout, `^`
  superscript and `~` subscript.

### Phase 4.3: Links and images [done]

- Inline links and images, reference links and images (definitions
  collected in a first pass over the whole document), autolinks,
  `{width=...}` attributes, implicit header references.
- An image alone in a paragraph becomes a `Figure`, as pandoc 3 does.

### Phase 4.4: Smart punctuation [done]

- Curly single and double quotes (`Quoted`), apostrophes, `--`, `---`,
  `...`, with pandoc's rules for contractions and for quotes next to
  punctuation. `test/command/smart.md` is the reference.

### Phase 4.5: Identifiers [done]

- pandoc's `auto_identifiers` with Unicode letters (using pounicode),
  duplicates numbered `-1`, `-2`, and explicit `{#id}` header
  attributes. Written in `PdMdInline`, not a module of its own.

### Phase 4.6: The rest of the extensions [done]

- Pipe tables, with alignment, captions and inline content in cells.
- Simple and multiline tables, brought forward from Later on
  2026-11-20: the acceptance needs them, for one multiline table in
  Galactic-Bounty-Hunters and for YAML front matter, which pandoc
  reads as a simple table when metadata blocks are off.
- Raw TeX inlines, in the general form of pandoc's LaTeX reader.
- Footnotes, inline and by reference.
- Fenced divs (`:::`) and bracketed spans (`[text]{.class}`), with
  attributes, nesting, and the setext and fenced-div interaction
  (`test/command/setext-fenced-div.md`).
- Definition lists.
- Header attributes (`{#id .class key=val}`).
- TeX math passed through as `Math` (no parsing of its content).
- Acceptance: every markdown file of Lost-Worlds and
  Galactic-Bounty-Hunters gives the same JSON as pandoc. The five
  files that start with YAML metadata are accepted on their blocks
  (the same as pandoc's with `-yaml_metadata_block`); their metadata
  is Phase 5's acceptance.

## Phase 5: YAML metadata [done]

### Phase 5.1: `PdYaml` [done]

- The subset of §9: block maps and sequences, flow collections of
  scalars, plain, quoted and block scalars, comments. Anything else is
  an error naming the construct and the line, and suggesting the
  libfyaml build once it exists.
- Unit tests against cases from `yaml-metadata-blocks.md` and the
  user's metadata.

### Phase 5.2: Metadata in the document [done]

- YAML blocks anywhere pandoc accepts them, merged in order.
- String values parsed as markdown (`MetaInlines` or `MetaBlocks`),
  booleans as `MetaBool`, as pandoc does.
- `-M key=value` (repeatable, building lists) and `--metadata-file`.

## Phase 6: Templates [done]

### Phase 6.1: `PdTemplate` [done]

- The language of §6: variables and fields, conditionals, loops with
  separators, comments, `$$`, partials, the pipes needed, and
  indentation of multi-line values.
- Unit tests from doctemplates' own test cases, where they fit.

### Phase 6.2: Template lookup and variables [done]

- The default templates bundled in `data/templates` (`default.html5`,
  `styles.html`, `default.ms`, `default.context`, `default.markdown`),
  copied from pandoc 3.10 under their BSD licence and built into the
  program.
- `--template=name`: the name as given, then with the format's
  extension, then in `~/.pandoc/templates`.
- `-V`, metadata as variables, and the writer's own variables
  (`body`, `toc`, `header-includes`, `include-before`,
  `include-after`, `pagetitle`, `lang`, ...).
- `-H`/`--include-in-header`, `-B`, `-A`.

The writer's own variables (`body`, `toc`, `pagetitle`, `lang`, ...)
are set by each writer, through `PdContext.DefField` and
`ResetField`, in Phases 7 to 10. Templates are looked for in pandoc's
user data directory (`$XDG_DATA_HOME/pandoc`, or `~/.pandoc` when only
that exists), which on the user's machine is `~/.pandoc`.

## Phase 7: The HTML writer [done]

### Phase 7.1: Blocks and inlines [done]

- Every element of §3.3, escaping, attributes, figures, tables with
  alignment, footnotes at the end.
- Raw `html` passed through; other raw formats dropped.

### Phase 7.2: Standalone HTML [done]

- `-s` with the default template and `--css`; `--toc` (and
  `--toc-depth`); `--number-sections`.
- Acceptance: the user's HTML targets are equivalent to pandoc's.

## Phase 8: The ms writer [done]

### Phase 8.1: Blocks and inlines [done]

- Every element of §3.3: escapes (`\&` before `.` and `'`, `\e`), the
  special characters, smart quotes and dashes, font changes, lists,
  block quotes, rules, line blocks, footnotes, images.
- Tables through `tbl`.

### Phase 8.2: Standalone ms [done]

- The default template and the user's `tkb.ms` and `statement.ms`.
- The title block, authors, abstract, date; `--toc` (`.TC`);
  `--number-sections` (`.NH`).
- Acceptance: the ms for the user's documents is equivalent to
  pandoc's.

## Phase 9: The ConTeXt writer [done]

### Phase 9.1: Blocks and inlines [done]

- Every element of §3.3: escapes, sections, lists, tables
  (`xtable`), block quotes, line blocks, images, footnotes, links.

### Phase 9.2: Standalone ConTeXt [done]

- The default template and the user's `tkb.context` and
  `statement.context`, with their variables.
- Acceptance: the ConTeXt for the user's documents is equivalent to
  pandoc's.

## Phase 10: The markdown writer [done]

pandoc's is 1,928 lines of Haskell (`Writers/Markdown.hs` and
`Writers/Markdown/`); podoc's should be 1,200 to 1,500 lines of
Oberon (decision 7).

### Phase 10.1: Blocks and inlines [done]

- `PdMdWriter`: every element the reader produces, written as pandoc
  markdown, unwrapped: headers (ATX), lists with pandoc's indentation,
  block quotes, code blocks (fenced when they have attributes), pipe
  tables, raw blocks and inlines, fenced divs and bracketed spans,
  footnotes (collected at the end), line blocks, definition lists,
  figures, links and images with attributes.
- Escaping: the characters that would otherwise start markdown
  syntax, in the places they would (a `#` or `1.` at the start of a
  line, `*`, `_`, `` ` ``, `[`, `<`, `\`, `|` in tables, `$`), as
  pandoc does; smart quotes and dashes written back as their ASCII
  forms.

### Phase 10.2: Standalone markdown and the round trip [done]

- `-s` writes the metadata as a YAML block (so `PdYaml` gains a
  writer), with the default markdown template.
- The round-trip test: for every case and every user document, the
  JSON of podoc's markdown, read again, equals the JSON of the
  original, both by podoc and by pandoc.
- Acceptance: the `-whole.md` targets of Lost-Worlds and
  Galactic-Bounty-Hunters (after Phase 12) read back to the same AST
  as pandoc's `-whole.md`.
- As done: pandoc's own round trip is not exact (consecutive lists,
  simple tables' alignments, raw HTML blocks, numbers in metadata:
  docs/user/differences.md), so the round-trip test is run on the
  cases that round-trip, listed in `test/roundtrip.txt`, among them
  `roundtrip`, made for it; elsewhere podoc's markdown must read back
  as pandoc's does. The `-whole.md` acceptance moves to Phase 12,
  which builds those targets.

## Phase 11: The command line [done]

### Phase 11.1: `PdOptions` [done]

- pandoc's options in pandoc's forms, both `--opt=val` and `--opt val`:
  `-s`, `-f`/`-r`, `-t`/`-w`, `-o`, `-V`, `-M`, `--metadata-file`,
  `--template`, `-H`, `-B`, `-A`, `--css`, `--toc`, `--toc-depth`,
  `--number-sections`, `--pdf-engine`, `--pdf-engine-opt`,
  `--lua-filter`, `-F`/`--filter`, `--wrap=none`, `--version`,
  `--help`.
- The output format inferred from `-o`'s extension when `-t` is
  absent, as pandoc does (`.html`, `.ms`, `.tex`/`.context`, `.md`,
  `.pdf`).
- Unknown options and unsupported formats are errors naming the
  option.
- Use ArgParser if it handles these forms; otherwise a small parser of
  podoc's own. Record which.

As done: ArgParser handles every form (`--opt=val`, `--opt val`,
`-ovalue`, `-o value`, clustered short options), so `PdOptions` uses
it. Its errors (an unknown option, a missing argument) exit with 2,
not pandoc's 6. Until Phase 14, PDF output ends podoc with status 43
once the writer and engine are chosen; until Phases 12 and 13, the
user's filters end it with status 83.

## Phase 12: Includes [done]

### Phase 12.1: `PdInclude` [done]

- `!include path` and `` !include`incrementSection=n` path ``, as §5:
  globs in sorted order, recursion, paths relative to the including
  file, metadata merged with the outer keys winning, header levels
  shifted, relative image paths rewritten, cycles detected.
- The other `pandoc-include` keys rejected with a message.
- Run when `-F pandoc-include` (or `--filter pandoc-include`) is given,
  so that output without it still matches pandoc's.
- Acceptance: the user's `-whole.md` targets (Phase 10.2).

As done: globs are Python's (`PdGlob`: `glob.glob` with
`recursive=True`, `fnmatch` sets, natsort's order), as pandoc-include
finds files. Reading directories needs `opendir`, so `PdGlob` has a
small POSIX C part, `PdGlob.c` (decision 1: C where it earns its
place); it needs no library. A cycle, which pandoc-include follows
forever, ends podoc with status 83, and `tools/compare` stops pandoc
after 10 seconds where `timeout` is installed. The include line is
rendered as pandoc-include sees it, `markdown_strict` with `\*` and
`\_` unescaped, for the escapes that matter to paths (`[` and `]`).
Headers shifted below level 1 are written as paragraphs in HTML, as
pandoc writes them.

## Phase 13: Native filters [done]

### Phase 13.1: The filter mechanism [done]

- `--lua-filter` and `-F` options become a list of passes, run in
  command-line order; a pass is chosen by the filter's base name.
  `pandoc-mermaid-selenium-filter` warns and does nothing
  (decision 4). Any other filter is an error naming it.

As done: `PdFilters` holds the passes, run by `podoc` in command-line
order. A filter is known by its base name and the option that gives
it, as pandoc would find it: `pandoc-include` with `-F`, the Lua
filters with `-L` (added as `--lua-filter`'s short form, as pandoc);
the other way round ends podoc with pandoc's message and status 83.
Lua's `FORMAT` is the writer's name as given (`html5`, and `ms` for
PDF made through ms), kept as `PdOptions.filterFormat`. A filter's
messages go through `PdIO.Note`, without "podoc: ".

### Phase 13.2: `subs` and `strip-comments` [done]

- The new substitutions format (decision 5): a metadata map,
  `substitutions`, usually kept in its own file and given with
  `--metadata-file=substitutions.yaml`:

  ```yaml
  substitutions:
    "|SCA|": Seltroti
    "|PKA|": Bayhang Avirang
  ```

  The keys are literal text; the values are taken as plain text
  (stringified). Being metadata, the table also works with pandoc, if
  `subs.lua` is changed to read `meta.substitutions` (a few lines,
  offered to the user, not done unasked). A script converts
  `substitutions.lua` once.
- Literal substitution in every `Str`.
- `strip-comments`, recursively.

As done: `tools/subs2yaml` converts `substitutions.lua`. With no
`substitutions` map, `subs` ends podoc with status 83 and a message
naming the map and `--metadata-file`. Keys are applied in key order
(metadata maps are kept sorted), each over every `Str`, left to right
without rescanning.

### Phase 13.3: `general` [done]

- The Div and Span rules of §4.3 for HTML, ms and ConTeXt, written as
  raw blocks and inlines, with the same warnings on standard error.
  For the markdown writer, Divs and Spans are left alone.

As done: for the markdown writer too, `general` does what general.lua
does there (pandoc runs it for every writer): `for-format` Divs
without `markdown` are dropped, and the Span messages are printed.
All its messages go to standard error, the Spans' first
(docs/user/differences.md).

### Phase 13.4: `toc-columns` and `combine-docs` [done]

- `toc-columns`: the raw ConTeXt block, placed as §2.1 says.
- `combine-docs`: the digest of §2.1, reading each file with the
  reader.
- Acceptance: the Lost-Worlds GNUmakefile's targets, run with
  `PANDOC=podoc`, produce intermediate HTML, ms and ConTeXt equivalent
  to pandoc's.

As done: `combine-docs` reads each file with `PdMarkdown`, takes its
title from its metadata, a lone first level-1 header (removed) or its
file name, shifts its headers so the highest is level 2, prefixes its
identifiers with the file's stem, and puts a ConTeXt `\page` between
files. `tools/compare` takes `FILTERDIR`, a directory of the user's Lua
filters, so that pandoc finds them.

## Phase 14: PDF output [done]

### Phase 14.1: `PdRun` [done]

- Make and remove a temporary directory under `TMPDIR`.
- Run a program with arguments, standard input from a file or buffer,
  standard output to a file; report its exit status. Through
  `Platform.System`, with every argument in POSIX single quotes: pounix
  is built for `-OC` only, and podoc must build under both models
  (2026-11-20). pounix stays a possible `-OC` refinement.

As done: `PdRun` builds a command as text for `/bin/sh`, each argument
in single quotes, and runs it with `Platform.System`; a signal gives
128 and its number, as the shell reports it. The temporary directory
is `podoc<pid>-<n>` under `TMPDIR` or `/tmp`, made with `mkdir -m 700`
and removed with `rm -rf`; images are copied with `cp`. Standard input
and output are redirections in the command, not buffers.

### Phase 14.2: The engines [done]

- `pdfroff`, `groff` and `context` with the arguments of §7, plus
  `--pdf-engine-opt` and `papersize`.
- For ConTeXt: images copied into the temporary directory, SVGs
  converted with `rsvg-convert` when it is present.
- Engine errors shown with the engine's log.
- Acceptance: every PDF target of Lost-Worlds and
  Galactic-Bounty-Hunters builds with `PANDOC=podoc`, and its
  `pdftotext` matches that of pandoc's PDF.

As done: `PdPdf` chooses the engine by the program's base name, as
pandoc does, and runs it with pandoc's arguments: pdfroff and groff
read the ms from standard input (`-U` when it has `.PDFPIC`), context
runs on `input.tex` in the temporary directory with `--batchmode`.
For every engine, an image that is not there is replaced by its
description with pandoc's warning; for context, images are copied into
the temporary directory as `img<n>` and SVGs converted with
`rsvg-convert`, and smart ligatures (`---`, `--`, `'`) are off, as
pandoc's TeX output for PDF. Errors and statuses are pandoc's: 43 with
the engine's output (context: its first `tex error` line), 47 for an
engine not found, 4 for PDF to a terminal. The differences (images
found from the working directory only, URLs not fetched, `img<n>`
names, no `--verbose` log) are in docs/user/differences.md.

## Phase 15: The proof of concept, finished [done]

### Phase 15.1: Portability [done]

- Build and test on at least one BSD.
- Record what a minimal system needs: poc, the libraries, groff
  and/or ConTeXt.

As done: built and tested on the VMs alerik (FreeBSD 15.1, amd64) and
artos (NetBSD 11.0, amd64), with poc 0.15.0, after installing
ArgParser, Ropes and pounicode there in `~/.local/lib/poc`. What a
minimal system needs is in docs/user/podoc.md: poc, those libraries,
GNU make and `/bin/sh` to build and run; for PDF, `mkdir`, `cp`, `rm`
and the engine. NetBSD's base groff, 1.19.2, has neither `-k` nor
`gropdf`, so ms PDF there needs a newer groff (1.23.0 works); podoc
reports the engine's failure as pandoc would (43; 47 for a missing
`pdfroff`).

### Phase 15.2: Installing and documenting [done]

- `make install` (`PREFIX`, as the other projects), and
  `docs/user/podoc.md`: the supported subset, the options, the
  substitutions format, and `docs/user/differences.md`.
- README and AGENTS.md updated.

As done: `make install` installs `build/$(MODEL)/podoc` (`-OC` by
default) and `tools/subs2yaml` in `BINDIR`, and README, LICENSE, the
user documentation and the templates' licence (`templates-LICENSE`,
which a binary distribution must carry) in `DOCDIR`; `PREFIX`
defaults to `~/.local`, and `DESTDIR` is honoured. `POCLIBDIR` no
longer follows `PREFIX`. `make uninstall` removes what it installed.

## Phase 16: Plain text and grid tables [done]

Planned 2026-11-20 at the user's request; no build of the user's
uses `-t plain` so far. pandoc's `plain` writer is its markdown writer
run with `envVariant = PlainText` (`Writers/Markdown.hs`, `writePlain`),
which changes about 25 places in `Writers/Markdown.hs` and
`Writers/Markdown/Inline.hs`, and with `plainExtensions`
(`Extensions.hs`): table captions, implicit figures, simple,
multiline and grid tables, LaTeX macros, fancy lists, startnum,
definition lists, example lists, intraword underscores, blank before
block quote and header, strikeout. So the work is a variant of
`PdMdWriter` and `PdMdInline`, not a new writer.

Grid tables and wrapping come in with it (decision 10); wrapping
applies to markdown too (decision 11); `gutenberg` is supported
(decision 12); grid tables are read (decision 13) and written by the
markdown writer where pandoc writes them (decision 14), as are pipe
tables (decision 15). The grid
table reader comes before the writer: podoc reads only markdown, so
without it no table with block cells, spans or a footer can reach a
writer to test it.

### Phase 16.1: The variant, unwrapped [done]

- `-t plain` in `PdOptions` and `podoc`; output extensions stay as
  pandoc's (`.txt` deduces markdown, not plain). `-s` uses pandoc
  3.10's `default.plain`, added to `data/templates` and `PdDefaults`
  by `tools/mktemplates`.
- `PdMdWriter` and `PdMdInline` gain a plain variant, following each
  `PlainText` branch:
  - no escaping of `Str`; smart quotes and dashes left as they are
    (no `smart` extension), so curly quotes stay curly;
  - emphasis, strong, underline and spans: their contents only;
    small caps: their contents in capitals; strikeout `~~...~~` (the
    `strikeout` extension); code: its text without backticks;
  - subscripts and superscripts (no `subscript` or `superscript`
    extension): in Unicode where every character has a form
    (`toSubscriptInline`, `toSuperscriptInline`), else `_(...)` and
    `^(...)`. The markdown writer has no such fallback yet, so this
    is new code, with Unicode's sub- and superscript tables. pandoc's
    subscript fallback for rendered text calls `toSuperscript`;
    follow it and note it;
  - math: TeX math through texmath's `texMathToInlines`, made plainer
    (`makeMathPlainer`: emphasis to spans). Check how far podoc's
    math goes now and settle the subset with the user's documents;
  - links: their text, or the URL for an autolink; images:
    `[alt]`; notes: `[n]` in the text and `[n] text` at the end (no
    `footnotes` extension);
  - headings: the text and a blank line at every level, no `#` and
    no attributes; divs, fenced or not: their contents, separated
    from what follows by an empty Plain where markdown uses a
    comment;
  - code blocks: indented four spaces, never fenced; block quotes:
    indented two spaces (`blank_before_blockquote`, no `>`); line
    blocks: the lines, without `| `, empty ones blank;
  - raw blocks and inlines: kept only for format `plain`, else
    dropped, with pandoc's warning;
  - the title block: title, authors and date, each on its line, a
    blank line after (`plainTitleBlock`), instead of YAML;
  - horizontal rules: dashes to `--columns` (72 by default).
- Tests: cases with `<name>.plain` expected files, `tools/runcases`
  and `tools/mkcase` taught the extension; pandoc 3.10's
  `test/writer.plain`, regenerated with `--wrap=none`, as a case;
  both models.
- Acceptance: `-t plain --wrap=none` equals pandoc's, byte for byte,
  on every case without tables that need grid tables, or each
  difference listed in docs/user/differences.md.

### Phase 16.2: Grid tables in the reader [done]

- `PdMarkdown` reads grid tables as pandoc 3.10 does: its
  `Parsing/GridTable.hs` (308 lines) over the `gridtables` package
  (`Text.GridTable`, 0.1.x; the source is in
  `~/.cabal/packages/hackage.haskell.org/gridtables`, unpacked into
  the session's scratch directory to read). That means the table's
  outline, `=` header separators, `:` alignment markers, a footer
  below a final `=` separator, row and column spans, cells parsed as
  blocks (lists, paragraphs, code), column widths from the dashes
  relative to `--columns`, a caption before or after, and indented
  tables (`test/command/grid-table-indented.md`).
- Character widths: cells and borders are measured in columns, East
  Asian wide characters as 2, as for multiline tables; the known
  `realLength` approximation (Later) applies here too.
- The `grid_tables` extension: on by default for `markdown`, and
  turned off by `-f markdown-grid_tables`.
- Tests: cases from pandoc's `test/markdown-reader-more.txt` grid
  tables and the `test/command/*.md` that use them, JSON byte for
  byte, both models. Acceptance: also the Minimal OpenD6 SRD
  translated from reST with grid tables kept (`-w markdown` without
  `-grid_tables`) gives pandoc's JSON byte for byte.

### Phase 16.3: Grid and pipe tables in the writers [done]

- pandoc's `gridTable` (`Writers/Shared.hs`, about 40 lines and the
  helpers it calls) on `PdLayout`: cells as block lists rendered to a
  width, column widths from the relative widths or the content, row
  and column spans, header and footer separators, alignments in the
  `:` markers.
- The choice of table follows pandoc's order (`Writers/Markdown.hs`):
  simple, then multiline, then grid (when there are spans or a
  footer, or `--columns` is at least 8 times the number of columns;
  72 until Phase 17 adds `--columns`). For `plain` nothing comes
  after grid. For `markdown`, grid and pipe tables where pandoc
  writes them (decisions 14 and 15), and HTML only where pandoc falls
  back to it; the entries in docs/user/differences.md change to
  match.
- pandoc's `pipeTable` (`Writers/Markdown/Table.hs`, about 55 lines):
  the header row (empty when the table has none), the `|---|`
  separator with `:` for alignment, cells on one line. Cells are
  padded to the widest in the column (at least 3) only when those
  widths together fit in `--columns`. The separator's dashes follow
  the relative widths when the table has them and is wider than
  `--columns` (markdown only), else the padded widths, else 4 per
  column. `|` in cells is escaped (`Writers/Markdown/Inline.hs`,
  with `pipe_tables`). The approximate pipe table pandoc writes for
  spans when raw HTML is off (`-t markdown-raw_html`) went to Later:
  podoc takes no writer extensions, so nothing reaches it.
- Tests: pandoc's `test/tables.plain` and `test/tables.markdown`
  (regenerated with `--wrap=none`), cases with block cells, spans and
  footers read by 16.2, both models; the markdown round trip on them.
  Acceptance as 16.1.

### Phase 16.4: `gutenberg` [done]

- `-t plain+gutenberg` (Project Gutenberg's conventions), as pandoc's
  `Ext_gutenberg` branches: emphasis between underscores; strong in
  capitals; level-1 headings in capitals, with three blank lines
  before and two after; level-2 headings with two blank lines before.
  Capitals by pandoc's `capitalize` (`T.toUpper` on each `Str`), so
  a Unicode upper-case mapping: use pounicode's if it has one, else
  add one generated from UnicodeData.txt as `tools/mk*` do.
- `+gutenberg` as pandoc 3.10 takes it: for `plain`; for `markdown`,
  accepted and without effect; for `html`, `ms` and others, exit 23
  (checked 2026-11-20).
- Tests: cases with each convention, under both models; acceptance as
  16.1.

## Phase 17: Wrapping [done]

pandoc wraps `plain` at 72 columns by default (`--wrap=auto`,
`--columns`). `PdLayout` already wraps at a width as doclayout does
(`PdLayoutTest`), and `PdMdWriter` writes spaces as `L.Space()`;
every writer passes 0 (no wrapping) to `L.Render` and `L.Write`.

### Phase 17.1: `--wrap=auto` and `--columns` for plain [done]

- `--columns` in `PdOptions` (pandoc: 72 by default; 6 for a bad
  value); `--wrap=auto` passes it to `L.Write` for `plain`.
- Check every `NoWrap`, `Prefixed`, `Hang` and `Nest` in the writer
  against pandoc's, since none has been exercised with a width:
  headings, list markers, definition lists, block quotes, notes,
  table cells (which render at their column's width already),
  links' text.
- Tests: the `plain` cases again without `--wrap=none`, and
  `test/writer.plain` and `test/tables.plain` as pandoc ships them;
  long words, URLs and East Asian text at the margin.
- Acceptance: byte for byte with pandoc's default `plain` output, or
  differences listed.

### Phase 17.2: Wrapping for markdown [done]

- The same for `-t markdown` (decision 11), whose expected files are
  now `--wrap=none`: they keep `--wrap=none` in their `.args`, and
  new cases check wrapped output; the round trip must hold with
  wrapping on, and the `-whole.md` targets must still read back to
  pandoc's AST.
- Done otherwise in one respect: a case's `.args` serve all its
  formats, so `--wrap=none` there would unwrap its `plain` output too.
  The `markdown` expected files were instead replaced by the wrapped
  output, each checked against pandoc's first, as in 17.1.

## Phase 18: Wrapping for ms and ConTeXt [done]

pandoc wraps `ms` and `context` at `--columns` (72) by default too.
`PdMs` and `PdConTeXt` already build `PdLayout` Docs with breaking
spaces, as pandoc's writers do, and write them with no wrapping
(width 0). Each sub-phase passes the width through, finds what
pandoc keeps from wrapping (`nowrap`, `afterBreak`, literal spaces),
and is checked as 17.2 was: every case, pandoc's test files, a file
of edge cases at several widths, with and without `-s` and with
`--wrap=preserve`, and the user's 54 documents at 40, 72 and 100
columns under `-O2` and `-OC`. The cases' expected files become the
wrapped output, each checked against pandoc first, and `make compare`
must show no new differences.

### Phase 18.1: ms [done]

- `PdMs` renders at `--columns` under `--wrap=auto`. A line a wrap
  starts with `.` or `'` must not become a request: pandoc's
  `afterBreak "\\&"` (`Ms.hs`), which `PdLayout.AfterBreak` provides.
- PDF output through `pdfroff` and `groff -Tpdf` still works, checked
  on a wrapped document.

### Phase 18.2: ConTeXt [done]

- `PdConTeXt` renders at `--columns` under `--wrap=auto`.
- PDF output through `context` still works, checked on a wrapped
  document.

### Phase 18.3: Emoji widths [done]

doclayout's `realLength` counts an emoji sequence as one wide
character: a variation selector U+FE0F or a skin tone modifier
U+1F3FB..1F3FF after an emoji that takes it adds no width, and a
zero-width joiner U+200D after an emoji, U+FE0F or a skin tone
cancels the width of the one before it (`updateMatchStateNarrow`,
`emojiMap`, from emojis 0.1.5's `baseEmojis`). `PdWidth` counted
each character alone, so a heading starting `🏛️` in
galactic_bounty_hunters_one_shot.md wrapped one word later than
pandoc's at 40 columns.

- `tools/mkwidth` also reads emojis' `emojis.inc` and generates
  doclayout's `emojiMap` (the characters an emoji starts with, and
  whether a variation selector or skin tone may follow) and a
  `PdWidth.State` (`Start`, `Add`, `Total`), doclayout's
  `MatchState`.
- `realLength` is the State wherever pandoc uses it: `PdLayout`'s
  string widths, the reader's pipe and simple table widths
  (`PdMdInline.RealLength`) and the width of a grid table's character
  grid (gridtables' `toCharGrid`). `charWidth`, one character
  alone, stays where pandoc uses it (gridtables' cells, `chop`,
  `splitAtWidth`).
- Checked against pandoc 3.10, a unit test (`PdWidthTest`) and a case
  (`emoji-widths`).

## Phase 19: The reStructuredText reader [done]

podoc reads rST as pandoc 3.10's `-f rst` does, all of
`Readers/RST.hs` (decisions 18, 20 and 21;
docs/research/rst-implementation.md). The output is the same AST the
markdown reader builds, so the writers, templates, built-in filters
and PDF output need no change.

The modules are:

- `PdRst`: blocks, directives and the passes after parsing;
- `PdRstInline`: inline markup, roles, references and substitutions;
- `PdRstTable`, if `PdRst` grows too big: simple, list and CSV
  tables.

They reuse `PdMdBase`'s text buffer and character classes,
`PdMdInline.RealLength` and `CharWidth`, and `PdGridTable.Trace`.
The estimate is about 4,500 lines.

Each sub-phase is checked against `pandoc -f rst -t json`, byte for
byte, with and without `-s`:

- **case tests:** `test/cases/<name>.rst`, with expected JSON and,
  where a construct reaches a writer in a new way, ms, ConTeXt, HTML
  and markdown. `tools/runcases` learns `.rst` inputs.
- **pandoc's fixtures:** the parts of `test/rst-reader.rst` and
  `test/tables.rst` the sub-phase covers, and the command tests that
  read rST (61 in `test/command/*.md`).
- **the user's corpus:**
  - the 526 rST files of the 50 pandoc builds, each read from its own
    directory so that includes resolve;
  - the standard rST of the docutils projects and the Nikola site
    (decision 21);
  - `make compare` gains these comparisons, where pandoc is
    installed.

All of this runs under `-O2` and `-OC`, as every phase does.

### Phase 19.1: Blocks [done]

- `-f rst` and `-r rst`, and `.rst` inputs when there is no `-f`
  (today these exit with status 21; differences.md changes).
- Sections:
  - over- and underlined titles;
  - levels in the order their adornments first appear;
  - `auto_identifiers`, the one extension pandoc enables for rST,
    and `-f rst-auto_identifiers`.
- Paragraphs, transitions (`HorizontalRule`) and comments.
- Literal blocks: `::` and its expanded and partly minimized forms,
  quoted literal blocks, and doctest blocks.
- Block quotes, with attributions.
- Lists:
  - bullet lists;
  - enumerated lists, in every numbering style and with `#`;
  - definition lists, with classifiers;
  - field lists;
  - option lists.
- Line blocks, keeping their leading spaces as U+00A0.
- `rst+lhs` (literate Haskell, `lhsCodeBlock`), as pandoc gives it.

### Phase 19.2: Inlines [done]

- Emphasis, strong and inline literals. pandoc's recognition rules
  for where inline markup starts and ends (`notAfterString`, ...) are
  followed, not docutils'.
- Escapes, with `\ ` as nothing.
- Interpreted text, with every standard role pandoc handles:
  - `emphasis`, `strong`, `literal`, `code`;
  - `sup`/`superscript`, `sub`/`subscript`, `mark`;
  - `math`, `title-reference`/`title`/`t`, `span`, `raw`;
  - `rfc-reference`, `pep-reference`.

  A role can come before or after the text. `default-role` is also
  in this sub-phase.
- `.. role::`, with a base role (`ss(emphasis)`) and the options
  `class`, `language` and `format`. An unknown role becomes `Code`
  with the class `interpreted-text`.
- Hyperlinks:
  - named, anonymous and embedded references;
  - standalone URIs and e-mail addresses (the class `uri`);
  - internal targets, inline targets and indirect targets.
- Footnotes (numbered, `#`, `#label` and `*`) and citations, with
  pandoc's ordering of notes and its `citations` Div.
- Substitutions: `replace`, `unicode`, `date` and image
  substitutions, inline and as a whole paragraph
  (`resolveBlockSubstitutions`).
- The passes after parsing, which resolve references and
  substitutions over the whole document, including those defined
  after their use. pandoc's messages for a missing or circular
  reference are given too.

### Phase 19.3: Directives [done]

- Every directive pandoc handles:
  - `raw`, `container`, `class`, `compound`, `line-block`;
  - `pull-quote`, `epigraph`, `highlights`, `rubric`;
  - `admonition` and the named admonitions, `sidebar`, `topic`;
  - `image` and `figure`, with their options (`:align:` as an
    `align-` class, `:scale:`, `:width:`, `:height:`, ...);
  - `code`/`code-block`/`sourcecode`, `highlight`, `math`, `aafig`;
  - `bibliography`, `replace`, `date`, `unicode`, `role`,
    `default-role`.
- `include`, relative to the including file:
  - the options `start-line`, `end-line`, `literal` and `code`
    (pandoc ignores `tab-width` and `encoding`);
  - read in the includer's state, sharing its roles, substitutions
    and targets;
  - guarded against recursion;
  - pandoc's errors and exit statuses for a missing file.
- An unknown directive becomes a `Div` with its name as a class and
  its options as attributes (pandoc's `SkippedContent`).

### Phase 19.4: Tables [done]

- Grid tables through `PdGridTable`, the same `gridTableWith` the
  markdown reader uses. The tracer reads from `PdMdBase`'s buffer;
  the rST reader shares that buffer, or the tracer takes its text as
  a parameter.
- Simple tables:
  - column boundaries from the `=` borders;
  - continuation lines;
  - column spans marked by `-` underlines;
  - several header rows.
- The `table` directive (caption, `:widths:`),
  `list-table` (`:header-rows:`, `:stub-columns:`, `:widths:`) and
  `csv-table` (inline, `:file:`, `:delim:`, `:quote:`, `:escape:`,
  `:header:`, `:header-rows:`).

### Phase 19.5: Standalone, reporting, the corpus [done]

- Under `-s`:
  - `titleTransform`: a lone top section, and a subtitle under it,
    become `title` and `subtitle`;
  - docinfo field lists become metadata (`author`, `authors`,
    `date`, ...).

  The reader takes `-s` from `PdOptions`, since the AST depends on
  it.
- Reporting what the reader drops (decision 22):
  - `--verbose` prints pandoc's `[INFO]` lines (`Skipped ...`,
    reference not found, ...);
  - a podoc option, proposed as `--unknown=warn|error`, reports every
    unknown directive and role and anything else pandoc skips, with
    file, line and column, as a warning or as an error with status
    64.

  Listed in docs/user/differences.md and documented in
  docs/user/podoc.md.
- The whole corpus:
  - all of the user's pandoc-built rST files match pandoc's JSON;
  - PDFs from a few rST builds (Mini-Six SRD, Red-Planet-Blue-Helmets
    2ER, an Alusia scenario) are compared with pandoc's, as in Phase
    15;
  - podoc builds and passes its tests on the BSDs.
- docs/user/podoc.md: the translation advice for rST is replaced by
  `-f rst`.

## Phase 20: The `%` title block [done]

pandoc markdown's `pandoc_title_block` extension, on by default:
up to three lines starting with `%` at the top of a document give
the title, the authors and the date (`pandocTitleBlock`,
`Readers/Markdown.hs`). The user's documents use YAML instead, but
pandoc's `test/testsuite.txt` starts with one. It was one of two
differences left between podoc's and pandoc's reading of the test
inputs; the other, the raw TeX block (`\begin{tabular}`), remains. This phase does not depend on Phase 19 and can be done
before it.

- **The lines** (`rawTitleBlockLine`):
  - `%`, spaces, then the rest of the line;
  - continuation lines, which start with a space and are not blank,
    joined to it;
  - the whole trimmed.
- **What each line gives:**
  - the first line is the title, read as inlines and trimmed;
  - the second gives the authors, split on `;` (and spaces after it)
    and on line ends, each one read as inlines and trimmed;
  - the third is the date.
- **Empty fields:** each line is optional in turn, and an empty one
  sets nothing. For example, `%` and then `% Only Author` give only
  an `author`.
- **What follows:** blank lines after the block are skipped. The
  block must be at the very start of the input.
- **Metadata:** the result is `title`, `author` (a `MetaList`) and
  `date`. A YAML metadata block in the same document wins over the
  title block for the same key (pandoc 3.10, checked 2026-11-20:
  `% Block Title` and YAML `title: YAML Title` give `YAML Title`).
- **The extension:** `-f markdown-pandoc_title_block` turns it off,
  and the `%` lines are read as a paragraph. Today any reader
  extension but `grid_tables` exits with status 23.
- **Tests:**
  - case tests with expected JSON from pandoc for:
    - all three lines;
    - empty lines;
    - several authors;
    - continuation lines;
    - inline markup in the lines;
    - a title block with a YAML block;
    - the extension off;
    - `-s` and the `ms`, ConTeXt, HTML and markdown writers through
      the templates' `title`, `author` and `date`;
  - `testsuite.txt`'s metadata reading as pandoc reads it (its raw
    TeX block still differs), and `make compare` no worse.
- **Not part of this phase:** writing a `%` title block. pandoc's
  markdown writer does that only under
  `-t markdown-yaml_metadata_block`, a writer extension, already in
  "Later".

## Phase 21: Images in ms output [done]

Decision 23. Today podoc writes what pandoc writes: `.PDFPIC` for
`.pdf`, `.PSPIC` for `.ps` and `.eps`, and for any other image, in a
figure `\" .IMAGE "src" size`, inline `[IMAGE: alt] \" "src" size`
(`Writers/Ms.hs`, checked identical 2026-11-20). `PdPdf.Fetch` copies
images into the temporary directory but converts SVG only for
ConTeXt.

- **Which images:** local files, in a figure or inline, whose
  extension is one to convert: `.svg`, `.png`, `.jpg` and the like,
  ignoring case (`MAP.PNG` is converted). `.pdf`, `.ps` and `.eps`
  are matched exactly, as pandoc does: `fig.PDF` keeps pandoc's
  comment. URLs and `data:` URIs
  keep pandoc's output.
- **Conversion:**
  - SVG with `rsvg-convert -f pdf`, as ConTeXt PDFs do already
    (`PdPdf.ConvertSvg`); `-f pdf1.4` for groff (done so, 2026-11-21);
  - bitmaps (PNG, JPEG, GIF, TIFF and the like) with the first
    converter found, in this order: `img2pdf`, `magick` (or
    ImageMagick 6's `convert`), then `gm convert` (done without `gm`,
    2026-11-21: see decision 23);
  - 96 dpi, pandoc's default `--dpi`, given to the converter for an
    image with no resolution of its own (img2pdf assumes 96, magick
    and gm 72);
  - when no converter is found or a conversion fails, a warning, and
    the image keeps pandoc's output.
- **The ms written:** `.PDFPIC "path.pdf"` with the image's size
  attributes, in place of the comment, in a figure and inline (the
  `[IMAGE: alt]` text goes). `-U` is passed to groff, as it is now
  when the source has `.PDFPIC`. With no width, groff (checked
  2026-11-20, `groff -Tpdf`) scales an image wider than the line
  down to the line's width and prints a narrower one at its PDF
  page size; check `pdfroff` too.
- **Names:** the image's name with `.pdf` (`map.png` gives
  `map.pdf`); a number added when two images would get the same
  name (`map.png` and `map.jpg`, or two `logo.png` from different
  directories).
- **PDF output** (`--pdf-engine=pdfroff` or `groff`): the converted
  files go in podoc's temporary directory, beside the copies it
  makes now, and are removed with it.
- **`--extract-media=DIR`**, a new option, pandoc's: local images
  are copied into `DIR` and the output refers to the copies, as
  pandoc does (checked 2026-11-20 with `-t ms`: `"media/big.png"`);
  for ms, podoc also converts them there and writes `.PDFPIC`. Check
  what pandoc does with it for the other writers and match it.
- **`-t ms` without `--extract-media`:**
  - with `-o out.ms`, the converted images go in `out-media/` beside
    `out.ms`, and the paths written are relative to the output's
    directory: groff finds `.PDFPIC` files from the directory it
    runs in, not the `.ms` file's (checked 2026-11-20);
  - to standard output, the images keep pandoc's output, and podoc
    warns, suggesting `--extract-media`.
- **The converters compared** (2026-11-20, on atla; a JPEG photo, a
  PNG with transparency, a plain PNG):
  - `img2pdf` 0.6.3: embeds the JPEG unchanged (lossless); keeps the
    PNG's transparency as a soft mask; sizes the page from the
    image's resolution (96 dpi when it has none: 800 pixels give
    600 points). Python; bitmaps only.
  - `magick` 7.1.2: re-encodes the JPEG (a small loss); keeps the
    transparency; 72 dpi pages (800 pixels give 800 points). Reads
    nearly every format.
  - `gm` 1.3.45: re-encodes the JPEG; drops the transparency (no
    soft mask); 72 dpi pages.
  - Still to check: which of them the BSDs' packages provide.
- **Tests:** case tests for the ms written with each kind of image
  (they must not need the converters: the conversion is checked by
  a test that is skipped when the tool is missing); a PDF built with
  an SVG, a PNG and a JPEG, each image found in it (`pdfimages
  -list`).

## Phase 22: EPS images in PDF made with groff [done]

Decision 26. `PdImages.PostScript` tells `.eps` and `.ps` images;
`PdImages.Convert` converts them with `gs`; `PdPdf.Fetch` does so when
the engine is not `pdfroff` or `context`. The writer then sees a
`.pdf` and writes `.PDFPIC`, and `PdPdf.Roff` adds `-U`. Without `gs`
or when it fails, podoc warns and the image keeps `.PSPIC`. Tested by
`tools/runimages`' `pdf-eps`: a PDF made with groff from an EPS that
draws the text `EPSMARK`, found in it with `pdftotext`; skipped
without groff, gs and pdftotext.

## Phase 23: mom output and PDF through pdfmom [done]

Scheduled 2026-11-21 by decision 27, which settles the research's
questions (docs/research/pdfmom-backend.md §9). The acceptance
target is the 005-merchant scenario: `-t mom` with `--toc`, the
example statement template and `for-format mom` figures gives a PDF
close to its statement-sized ConTeXt one, with the contents first
and both figures.

pandoc has no mom writer, so there is no oracle. Expected files are
podoc's own, checked by hand and in groff. The checks are:

- groff accepts the output without warnings: `groff -mom -z -ww`;
- the PDF holds the text, the pages, the outline and the links;
- the PDF's text matches the ms PDF made from the same input.

Each subphase passes `make test` under `-O2` and `-OC`.

### Phase 23.1: Shared roff code [done]

- **Change:** move from `PdMs` into a new `PdRoff`:
  - escaping;
  - the font state (`\f[...]` with the font to return to);
  - the tbl table writer;
  - the line breaks that macros need;
  - wrapping at `--columns`.
- **Check:** ms output does not change, and every ms case test
  passes byte for byte.

### Phase 23.2: The mom writer, blocks and inlines [done]

`PdMom`, with `-t mom`, and `.mom` for `-o`. Without `-s` it writes
the body.

- **Blocks:**
  - `.HEADING n NAMED id`;
  - `.PP`;
  - `.LIST`/`.ITEM`/`.LIST OFF` for bullet and ordered lists, nested,
    with their numbering styles and start numbers;
  - definition lists, indented;
  - `.BLOCKQUOTE`;
  - code blocks and line blocks in no-fill;
  - rules;
  - `.FOOTNOTE` notes, or endnotes with
    `--reference-location=document` (decision 27);
  - raw `mom`, passed unchanged; other raw formats dropped;
  - `.PDF_TARGET` for ids on divs and spans.
- **Inlines:**
  - emphasis, strong and code through `PdRoff`'s font state;
  - strikeout, underline and small caps as for ms;
  - `\*[SUP]`;
  - quotes;
  - `.BR`.
- **Links:** `.PDF_LINK` to `#id` and `.PDF_WWW_LINK` otherwise, with
  trailing punctuation as `SUFFIX`.
- **To try in groff first:** the elements marked "to check" in the
  research's §5.2 (code blocks, line blocks, list start numbers).
- **Tests:** case tests `test/cases/<name>.mom`. Each expected file
  is also checked once with `groff -mom -t -z` (mom itself warns
  under `-ww`, so with groff's default warnings), after a
  `.PRINTSTYLE TYPESET` and `.START`.

### Phase 23.3: Tables and figures [done]

- **Tables:** tbl through `PdRoff`, with mom's `.TS` arguments
  (`CAPTION`; `H` for a header row).
- **Figures:** `.PDF_IMAGE -C file w h CAPTION "..." TARGET id`, the
  size from the image's `width` and `height`; a percentage width is
  of the line length (decision 27).
- **Filters:** `for-format mom`; `box` and `keep` for mom in the
  general filter (check mom 2.5_d's `.BOX` first).
- **Inline images:** as the ms writer writes them.
- **Tests:** case tests.

### Phase 23.4: The default template and its variables [done]

- **The template:** podoc's own, under podoc's licence (pandoc has
  none).
- **Title block:**
  - `title`, `subtitle`, `author` and `date`;
  - `abstract` as a block quote.
- **Contents:** `toc` writes `.AUTO_RELOCATE_TOC TOP` before
  `.START` and `.TOC` last, and `toc-title`. `--toc-depth` limits
  the levels.
- **Page and type:**
  - `papersize` → `.PAPER`;
  - the four margins;
  - `fontfamily`, `pointsize` and `lineheight`.
- **mom's own:** `columns`, `printstyle`, `doctype`, `linkcolor`
  and covers (decision 27).
- **Example:** a statement template like the user's `statement.ms`
  (`.PAGE 5.5i 8.5i`, its margins, `fontfamily`, the contents first),
  shipped with podoc and installed beside the docs. Like
  `statement.ms` it has `.special S Symbola`, for ♀, ♂ and other
  symbols the text fonts lack; groff finds Symbola through `-F`,
  given with `--pdf-engine-opt` (checked by hand on 2026-11-21 with
  the scenario: no missing glyphs).
- **The usual three:** `header-includes`, `include-before` and
  `include-after`.
- **Options:** `--number-sections` as `HEADING_STYLE n NUMBER`, and
  `--template` for the user's own mom templates.
- **Tests:** case tests with `-s`.

### Phase 23.5: PDF through pdfmom [done]

- **Engine:** `--pdf-engine=pdfmom`, by base name, the default for
  mom (`PdOptions.PdfWriterAndEngine`).
- **Command:** `PdPdf` runs `pdfmom -t -k -KUTF-8`, with `-e` when
  eqn is used, plus the `--pdf-engine-opt` options, on the source in
  the temporary directory. No `-dpaper`: `.PAPER` sets the size.
- **Images:** converted to PDF as for groff (decisions 23 and 26).
  When the document gives no size, it comes from `pdfinfo`; without
  `pdfinfo`, podoc warns and leaves the image out.
- **Exit statuses:** 47 for no `pdfmom`, 43 for a failure.
- **Tests:** a PDF test in `tools/runimages` or a new
  `tools/runmom`. It checks the text, the page count, the outline and
  an image in the PDF. It skips without `pdfmom` and `pdftotext`.
- **Acceptance:** the 005-merchant scenario, in a copy with
  `for-format mom` figures and a `raw:: mom` `.NEWPAGE`, under groff
  1.23.0 with the user's Optima and Symbola site-fonts (`-F`): the
  contents on the first pages, statement pages, both figures.
- **By hand:** under groff 1.23.0 and 1.25.0, the user's mom
  experiments' features (columns, links, numbered headings, the
  contents first) from a markdown and an rST input.

### Phase 23.6: Documentation and other systems [done]

- **Docs:**
  - docs/user/podoc.md: the writer, the engine, the template's
    variables, and how to write a mom template;
  - docs/user/differences.md: an output pandoc does not have;
  - AGENTS.md and the module list.
- **Other systems:** `make test` on the six BSD VMs; the PDF tests
  skip where groff has no pdfmom.

## Phase 24: Small syntax highlighting [planned]

Scheduled 2026-11-22 at the user's request: the small highlighting
of docs/research/syntax-highlighting-small.md, with vgrind's lessons
(its §12; docs/research/vgrind.md; decisions 30 to 34), for ms, mom
and ConTeXt, and for HTML (decision 46). Code blocks,
and inline code (decision 38), with a known language class get their
reserved words in bold, in two styles:

- *mono*: the monospaced font, reserved words in bold monospace;
- *proportional*: the text font, reserved words in bold, comments in
  italic (decision 30), columns aligned as `--code-align` says
  (decisions 32 and 33).

It is podoc's own: pandoc has nothing like it. With the style `none`,
the default, the output stays byte for byte as it is now.

**Before coding:** the study's questions Q1 to Q11 (§11 and §12.7)
are all decided, as decisions 35 to 45 (2026-11-22).

Each subphase passes `make test` under `-O2` and `-OC`.

### Phase 24.1: `PdCode`, the scanner [done]

- **Change:** a new module `PdCode` scans a code rope into spans:
  plain, reserved word, comment. Language records (case, comments and
  their nesting, line comments, strings and their escapes) with hooks
  (study §5.8, §8). The Oberon family (original, Oberon-2, Oberon-07,
  Component Pascal; decision 41), Modula-2 and C first; built-in
  lists of reserved words only (decision 45), compiled in.
- **Check:** `PdCodeTest`, with vgrind.md §6.2's mistakes as cases:
  nested comments, braces in strings, C's `//`, Modula-2's case rule.
- **Done** 2026-11-22: `src/PdCode.Mod`, `test/PdCodeTest.Mod` (49
  cases). Spans are plain, reserved, comment and string; strings are a
  kind of their own for 24.4 (decision 44). The rules a language needs
  beyond the record are flags for now (C's `#` lines, its digit
  separators, backslash-newline in `//`); hook procedures wait for
  the languages that need them (24.6, 24.7). The lists, from the
  languages' reports: original Oberon 32 words (the 1990/1992
  report), Oberon-07 33 (the 2016 revision: `TRUE` and `FALSE`
  reserved, no `EXIT`, `LOOP`, `WITH`), Component Pascal 40 (the
  2006 report, March 2001 with updates to October 2006); Oberon-2 34,
  Modula-2 46 and C 59 as the study verified. Nothing calls `PdCode`
  yet: the writers come in 24.3.

### Phase 24.2: The ms code font [done]

- **Change:** code blocks in ms written with `\f[CR]`, not `\f[C]`,
  which groff 1.25 cannot open (study §4.1; Q6). A change of its own,
  and a difference from pandoc.
- **Check:** ms case tests updated; `pdffonts` shows Courier.
- **Done** 2026-11-22: `PdMs.CodeBlock` writes `\f[CR]`; the 11 ms
  case tests that had `\f[C]` updated; docs/user/differences.md says
  why. A code block's PDF (`podoc -s -t ms -o x.pdf`, groff 1.25.0)
  now has Courier beside Times-Roman, and groff no longer warns.

### Phase 24.3: The writers, both styles, unaligned [done]

- **Change:** the style option (Q1) and its metadata form; ms, mom
  and ConTeXt in *mono* and *proportional* (study §4, §12.4), with
  alignment `none`; mom's proportional block in roman (Q7) and `"`
  as `\[dq]`; ConTeXt's escaping and `-\kern0pt`.
- **Check:** case tests per writer and style; PDFs from groff and
  ConTeXt looked at; the style `none` leaves every existing case
  test unchanged.
- **Done** 2026-11-22: `--code-style` and the metadata's
  `code-style` (`PdOptions`, `PdShared.SetCodeStyle` and `CodeStyle`;
  a bad value in the metadata is a warning and ignored, on the
  command line an option error, 6). The roff writers share
  `PdRoff.Highlight` and `InlineCode`: ms mono in `\f[CB]`/`\f[CI]`
  inside `\f[CR]`, proportional in `\f[B]`/`\f[I]`; mom with
  `\*[BD]`/`\*[IT]`/`\*[PREV]`, proportional as `.QUOTE` with the
  quote font saved, set to `R` and restored. `"` was already `\(dq`
  in every roff writer. ConTeXt mono as `\starttyping[escape=yes]`
  and `\type[escape=yes]`, proportional as `\startlines[space=on]`
  with `{\bf{}WORD}` (the `{}` because `space=on` makes the space
  after `\bf` count) and `\kern0pt` between any two characters that
  make a TeX ligature (`--`, `''`, ``` `` ```, `,,`, `<<` ...).
  - **A template change, under `$if(code-highlight)$`:** the
    default monospaced family, Latin Modern Typewriter, has no bold
    or italic, so in a PDF `\bf` and `\it` did nothing in code.
    The writer sets `code-highlight` when any code is highlighted,
    and `default.context` then adds Latin Modern Mono's
    `lmmonolt10-bold`, `lmmono10-italic` and `lmmonolt10-boldoblique`
    to the family, unless `monofont` is set. Output without
    highlighting is unchanged. The bold is the light one the study
    (§4.3) found weak, but it is visible.
  - **Left for 24.4:** ConTeXt's proportional style turns `'` into
    ’ (the font's `textcontrol`); only a font defined with a feature
    set without it avoided that in the experiment, which is template
    work. A user's own template gets no bold monospace unless its
    `tt` family has one.
  - **Checked:** 15 case tests (`test/cases/highlight-*`): each
    writer in each style, the metadata's style, a class over the
    command line over the metadata, inline code and a heading, the
    ConTeXt template's font line, and the bad values. PDFs of a
    sample with Oberon, C, no language and `.plain` blocks made with
    `groff -Tpdf` (ms), `pdfmom` and `context`, in both styles, and
    looked at: bold words, italic comments, indentation, `.` at a
    line's start, `--` and `\` as written. `make test` passes under
    `-O2` and `-OC`; no existing case test changed.

### Phase 24.4: Alignment [done]

- **Change:** a new module `PdCodeAlign` (study §12.3): lines into
  indentation and segments, groups, positions for `fixed`, `elastic`
  and `hybrid`. `--code-align` and `code-align` (decision 33). The
  writers write column numbers; the templates set `PdCodeCol` and
  `PdCodeGap` from `code-column` and `code-gap` (decision 32), and
  ConTeXt's template gets `\PdLine`, `\PdSeg` and `\PdMeasure`, all
  inside `$if(...)$` so that unused templates do not change (§12.5).
- **Check:** `PdCodeAlignTest`; the two samples of vgrind.md §8 as
  case tests, rendered in all three formats and compared with the
  experiment's PDFs; decision 32's template lines verified.
- **Done** 2026-11-22: `PdCodeAlign` cuts a block into lines,
  segments (at a run of two or more spaces; a single space stays,
  trailing spaces go, a string is never cut) and pieces of one kind,
  with columns in code points, and finds the groups: a later segment
  joins the group of the segment at its column on the line before,
  and a blank line or a line without that column ends it. Every later
  segment is in a group, a single line's included, so that no
  position is ever measured from `\n[.k]` inside `\w`. Groups are
  numbered in the order of their column, then of their first line,
  which is the order the writers place them in. `--code-align` and
  `code-align` (`PdOptions`, `PdShared.SetCodeStyle`): hybrid by
  default, the command line over the metadata, a bad value an option
  error (6) or, in the metadata, a warning and ignored. `none` keeps
  24.3's unaligned output.
  - **roff** (`PdRoff.AlignedCode`, for ms and mom): indentation as
    `\h'|N*\n[PdCodeCol]u'`; `fixed` as
    `\h'(N*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'`; `elastic` and
    `hybrid` with a number register per group, `PdG<k>`, set before
    the block to the column (`hybrid`) or 0 (`elastic`) and widened by
    each member's `\w'<text before it>'u+\n[PdCodeGap]u`, then
    `\h'|\n[PdG<k>]u'`. Every number in `\h` and `.nr` needs its `u`:
    without it groff scales it as ems and the lines vanished off the
    page. mom's aligned blocks use `\*[BD]`, `\*[IT]` and `\*[ROM]`.
  - **ConTeXt:** `\PdLine`, `\PdSeg{<position>}{<text>}` and
    `\PdMeasure{PdG<k>}{<text>}` (positions with `\setvalue` and
    `\getvalue`), in `\startlines[style=\PdCodeR]`; bold and italic in
    `PdCodeB` and `PdCodeI`. The fonts are `Serif*pdcode`, a feature
    set with `textcontrol=no`, which keeps `'` straight (24.3's
    leftover, now fixed, also for `none`).
  - **A change from the plan:** the macros and fonts are not in
    `default.context` but written by the writer once per document,
    before the first proportional block, inside `\ifdefined\PdSeg`,
    with `\PdColumn` and `\PdGap` defaulted inside `\ifdefined`; and
    each roff block starts with `.if !r PdCodeCol .nr PdCodeCol 0.5m`
    and the same for `PdCodeGap`. So a fragment without `-s`, and a
    user's own template, still work. The templates only set the
    values, when given: `default.ms` and `default.mom`
    `$if(code-column)$.nr PdCodeCol $code-column$m$endif$` (and
    `code-gap`, `PdCodeGap`), `default.context`
    `\newdimen\PdColumn \PdColumn=$code-column$em` and
    `\def\PdGap{$code-gap$em}`, after `\setupbodyfont`. Output that
    sets neither is unchanged. In ms and mom the `m` is the point size
    where the line is read, near the template's top; groff's default
    there is 10 points.
  - **Checked:** `PdCodeAlignTest`, 23 cases (cutting, kinds, groups,
    names). 19 new case tests (`test/cases/align-*`): vgrind.md §8's
    two samples (Oberon, with comments at column 28; C, with
    `#define`s, a wide one, a `struct` and a `switch`) in ms, mom and
    ConTeXt in each alignment, the metadata's `code-align`, the
    command line over it, the template lines with `-s`, and both bad
    values. The samples' PDFs, from `groff -ms -Tpdf`, `pdfmom` and
    `context`, in all four alignments, were looked at: hybrid groups
    move together, fixed's least gap pushes only the wide `#define`,
    elastic aligns only within groups, none keeps the source spaces,
    and ConTeXt matches groff, with straight `'`. With
    `-V code-column=0.4 -V code-gap=2` the columns narrowed and the
    gaps widened in all three. `groff -ww` warns only of ms's
    `pdfsync`; ConTeXt's logs have no overfull box, error or undefined
    control sequence. The 24.3 proportional cases
    (`highlight-proportional`, `highlight-meta`) changed, as the
    default is now `hybrid`; the mono and `none` cases did not.

### Phase 24.5: HTML [done]

- **Change:** `PdHtml` writes code with a style as decision 46 says:
  `<b>` and `<i>` for mono; for proportional, the lines and segments
  from `PdCodeAlign` as positioned `<span>`s, `fixed` only.
  `data/templates/styles.html`, the CSS partial, gets both styles, with
  `code-column`, inside `$if(...)$`; `tools/mktemplates` re-run.
- **Check:** case tests in both styles, inline code among them; the
  case tests without a style unchanged; the vgrind samples viewed in
  a browser, and their text copied out matching the source.
- **Done** (2026-11-22):
  - **Mono:** reserved words in `<b>`, comments in `<i>`, in code
    blocks and inline code with a language; a comment across lines is
    closed at each line's end and reopened. Without a style the output
    is as before.
  - **Proportional:** the `<pre>` gets the class `pd-proportional`
    (on `<pre>`, not `<code>`, so `font-family: inherit` reaches the
    body font), and its `<code>` the class `pd-aligned` unless the
    alignment is `none`, which keeps the source's spaces in the body
    font. `elastic` and `hybrid` give the same output as `fixed`.
  - **A change from decision 46:** segments are not placed at `left:`
    their column, which overlapped the wide `#define` of vgrind.md
    §8's C sample. A line's indentation, and each segment that has a
    next one, are `inline-block`s of `min-width` (the next column
    minus this one) times `code-column`, and a segment has
    `padding-right` `code-gap` with `box-sizing: border-box`: its
    width is the larger of the two, decision 32's least gap, as in
    ms. After a push, the line's later segments are placed after it,
    not back at their columns; groff's fixed returns to the column
    when it can. The widths are `--pd-w` in each span's `style`.
  - **Copying:** the source's spaces stay in the text, in
    `<span class="pd-gap">` of `font-size: 0`, so a copy gives the
    code exactly. `PdCodeAlign` now records them: a segment's `gap`
    (spaces before it, the indentation for the first) and a line's
    `trail` (after its last segment, or all of a blank line's).
  - **CSS:** in `styles.html` inside `$if(code-proportional)$`, a
    variable the writer sets when a proportional block was written,
    with `code-column` (0.5 by default) and `code-gap` (1).
  - **Checked:** `PdCodeAlignTest`, 4 new cases (gaps, indentation,
    trailing spaces, blank lines). 8 new case tests, `.html` beside
    `highlight-mono`, `highlight-proportional`, `highlight-meta`,
    `align-fixed`, `align-elastic`, `align-hybrid`, `align-none` and
    `align-template` (`-s`, the CSS with `code-column` 0.4 and
    `code-gap` 2); the other HTML cases did not change. vgrind.md §8's
    samples, with `-s`, in fixed and none and with
    `-V code-column=0.4 -V code-gap=2`, were rendered with headless
    Chromium and looked at: body font, the comments aligned, the
    wide `#define` pushed and not overlapped, none's spaces kept. The
    text selected over each `<pre>` (`Selection.toString`, through
    `--dump-dom`) equals the source of both blocks, in fixed and none.

### Phase 24.6: Pascal, Ada, C++ [done]

- **Change:** Pascal with a list per mode, plain `pascal` as `fpc`
  (decision 39), Ada's tick, C++'s raw
  strings and digit separators (study §5.3 to §5.6).
- **Check:** `PdCodeTest` cases from each language's corner cases.
- **Done** (2026-11-22):
  - **Pascal:** the classes `pascal` and `fpc` (59 words), `objfpc`
    (67), `delphi` (65), `tp` (54), `macpas` (56) and `iso` (36),
    computed from `compiler/tokens.pas` (a word is reserved in a mode
    when its set meets the mode's switches, as fpc's `is_keyword`
    does) and checked with the installed fpc 3.2.3: in each mode it
    rejects every word of the mode's list as a variable name and
    accepts the other words of the six lists. Two corrections to the
    study's §5.4: the source under `/usr/local/sw/src/lang/Pascal/fpc`
    is trunk (3.3.1), not 3.2.3; and its grouping left out `xor`
    (every mode) and `initialization` and `finalization` (fpc, objfpc,
    delphi). fpc 3.2.3 accepts `inline` as a name in tp, though its
    table gives it to tp, so tp's list leaves it out.
  - **Pascal's rules:** case ignored; `{ }` and `(* *)`, nested in fpc
    and objfpc, each kind in itself (checked with fpc), not in the
    other modes; in iso `{` and `(*` close each other's comments, as
    ISO 7185 and fpc's trunk do (fpc 3.2.3 closes `(*` with `}` but
    not `{` with `*)`); `//` in every mode (checked); strings in `'`
    with `''`; `&begin` a name.
  - **Ada:** `ada`, 74 words (GNAT accepts only `parallel`, as the
    study found); case ignored; `--`; strings in `"` with `""`; `'`
    after a name, `)` or `all` is the tick, and the word after it an
    attribute, never bold (`A'Range`); otherwise `'x'` (UTF-8 too) is a
    character literal; `Character'('a')` gives both.
  - **C++:** `cpp`, 92 words (g++ `-std=c++23` rejects all 92 and
    accepts `final`, `override`, `import`, `module`); C's rules, with
    raw strings `R"d(...)d"` and the prefixes `LR`, `uR`, `UR`,
    `u8R`, kept whole across lines; C's digit separators.
  - **An addition, for C and C++:** after `#include`, `#include_next`
    or `#import`, a header name `<...>` is a string, so `<new>` is not
    bold. No case test changed.
  - **Checked:** `PdCodeTest`, 106 cases, 52 of them new (each mode's
    every word, and the others plain; comments, strings, directives
    and `&` in Pascal; Ada's tick, literals and attributes; C++'s raw
    strings and words; header names). A case test,
    `highlight-languages` (ms and HTML, mono), with objfpc, Ada and
    C++ blocks and inline C++.

### Phase 24.7: sh and bash [done]

- **Change:** command position, here-documents, `case` (study §5.7).
- **Check:** `PdCodeTest` cases, with vgrind.md §6.2's sh mistake.
- **Done** (2026-11-22):
  - **Lists:** `sh`, POSIX's 16 reserved words; `bash`, the 22 of
    bash's `compgen -k` (sh's and `[[ ]] coproc function select
    time`). dash is not installed, so sh's rules were checked with
    bash in its POSIX reading.
  - **Command position:** a word is reserved only where a command
    starts (after a newline, `;`, `&`, `|`, `&&`, `||`, `(`, `{`, a
    reserved word that takes a command, `!`), and only when it is
    literal (no quotes, escapes or expansions). After an assignment
    (`x=1 if`) or a redirection (`>f if`) a word is not reserved:
    checked with bash. vgrind's mistake, keywords bold as arguments
    (`echo if then`), is a test case.
  - **`case`:** the word, `in`, patterns up to `)`, with reserved
    words plain in them; `esac` ends the case only at a pattern's
    start, so `a|esac)` and `(esac)` are patterns (checked with
    bash); `;;`, and bash's `;&` and `;;&`; nested cases.
  - **`for` and `select`:** the name is plain, `in` reserved after it,
    also on the next line; `for a do`.
  - **Here-documents:** `<<` and `<<-`, the delimiter quoted or
    escaped (a quoted one a string), several on a line, the bodies
    plain up to their delimiter lines (`<<-` strips tabs), inside a
    command substitution too; an unclosed one runs to the end.
  - **Words:** comments from `#` at a word's start; strings in `'`,
    `"`, `$'...'` and `$"..."`, across lines, ending at the end of the
    text if unclosed; `$(...)` and backquotes scanned as commands,
    `$((...))`, `${...}`, arrays and bash's extglob skipped; function
    definitions `name ()` and bash's `function name`; bash's `[[ ]]`
    (its operators plain), `((...))`, `<(` and `>(`, `<<<`, `&>`
    and `|&`.
  - **Checked:** `PdCodeTest`, 149 cases, 43 of them new; podoc's
    own 10 sh scripts in `tools/`, as sh and as bash blocks, under
    `-O2` and `-OC` (the same output, read by eye); 3,000 random
    blocks of shell tokens, under both models, without a failure,
    and with the same output.

### Phase 24.8: Users' lists [planned]

- **Change:** reserved-word lists in podoc's own format (decision
  31), from `--keywords=lang:file` and the metadata `keywords`:
  adding, replacing with `#!replace` or `replace: true`, removing
  with `-word` (decision 40).
- **Check:** case tests with a list of each kind; a missing file
  gives pandoc's exit status.

### Phase 24.9: Documentation and other systems [planned]

- **Docs:** docs/user/podoc.md (the options, the variables, the
  languages); docs/user/differences.md (the code font, the styles,
  `--code-align`, HTML's `fixed` only); AGENTS.md and its module list.
- **Other systems:** `make test` on the six BSD VMs.

## Later, not scheduled

- An rST writer, `-t rst` (decision 19).
- Full YAML through polibfyaml, as `make YAML=libfyaml` (decision 2).
- Embedded Lua 5.4 and a `pandoc` module written in Lua (§8), if a
  filter appears that native code does not cover (decision 6).
- JSON filters: a JSON reader for the AST and `--filter prog` over
  standard input and output (§8.4).
- Output wrapping at `--columns` for the HTML writer (Phases 17 and
  18 cover plain, markdown, ms and ConTeXt; decision 16).
- The markdown reader, not needed by the user's documents so far:
  raw TeX blocks, environments, macros and the
  commands pandoc's LaTeX reader reads specially; citations and
  example references; wikilinks and base64 data URIs; table cells
  that hold blank lines.
- Known gaps in the markdown reader: a note referenced twice shares
  its blocks (only the JSON writer reads them so far, so nothing
  shows); compactify runs before implicit figures exist; the
  contents of Strikeout, Quoted and Link are not trimmed again after
  resolving.
- Citations, `--citeproc`.
- rST footnotes as docutils has them (the user's choice, 2026-11-21,
  over leaving them or approximating them; see decision 25). pandoc's
  AST puts a note's text where it is referenced, so its reader, and
  podoc's, copy a footnote referenced twice into two footnotes, drop
  a footnote nothing references, and leave a footnote reference inside
  a footnote (`[2]_`) as a link to `##NOTE##2`. docutils keeps the
  footnotes as one list, each printed once, linked to from each
  reference and back. Doing that would need footnotes held apart from
  the text and cross-references between them in every writer (HTML,
  ms with its `\**` numbering, ConTeXt, markdown, plain), going past
  matching pandoc; a phase of its own, if the user's documents come
  to need it. None of the 73 rST files does (2026-11-21).
- Writer extensions for `-t markdown` (`-raw_html`, `-pipe_tables`,
  ...), and with them the approximate pipe table pandoc writes for a
  table with spans when raw HTML is off.
- Image conversion for ConTeXt beyond SVG.
- The ms writer: TeX math to `eqn` (texmath's `writeEqn`), and
  syntax highlighting.
- Templates: the pipes `left`, `right` and `center` (block layout);
  the `meta-json` variable; `--variable-json`; `--data-dir`; the
  "expecting ..." part of template error messages.
- Memory use (found 2026-11-20; the layout writers' part fixed the
  same day, see docs/developer/memory-use-problem.md). Left:
  - ConTeXt's sections are its top-level blocks, each built whole;
  - the AST itself: 30-45 times the input at 12 MB, for every writer;
  - running out of poc's heap: podoc is built with poc's
    `-trap-heap-exhausted` (2026-11-20), which gives "heap exhausted"
    for its own modules' `NEW`s; a `NEW` in an installed library
    (Ropes, pounicode, ArgParser) still gives NIL and a NIL trap, unless
    the library is built with the option too. Fixed in poc by
    Peaseblossom's enhancement 15, decided 2026-11-20 (65c753c), once
    it is released: then drop `-trap-heap-exhausted` from `POCFLAGS`
    (poc will reject it) and add podoc's hook in the same change.

## State

- 2026-11-19: Research done and recorded in
  `docs/research/podoc-scope.md`; this plan written. No code yet.
- 2026-11-20: The user decided the open questions (Decisions). The
  markdown writer became Phase 10, Lua went to "Later", and
  substitutions moved to YAML metadata. Ropes checked: installed for
  poc under `-O2` and `-OC`; a test program built on it ran under
  both (200,000 appends, 600,003 characters, depth 34, written with
  `WriteFile`, in 0.04 s). Phase 1 next.
- 2026-11-20: Phase 1 done. `PdIO`, `PdSource` and `podoc` (with
  ArgParser: `-o`, `-t`/`-w`, `--tab-stop`, `-p`/`--preserve-tabs`,
  `-v`, `-h`), the GNUmakefile, `tools/runcases`, README, LICENSE and
  `docs/user/differences.md`. ArgParser, Ropes and pounicode are
  installed for both models; pounix and polibfyaml for `-OC` only, so
  Phase 14.1 now plans `Platform.System` rather than pounix. `make
  test` passed under `-O2` and `-OC`: `PdSourceTest` (13 checks: BOM,
  CRs, tabs by characters, final new lines, joining) and the case
  `join.source`. By hand: errors and exit statuses (1 for a missing
  input or an output that cannot be created, 22 for an unknown
  format; 2, not pandoc's 6, for an unknown option, from ArgParser),
  `-ofile` and `-o file`, `-` for standard input, and pandoc 3.10's
  tab expansion (`printf '    \xc3\xa9\tb'` gives a code block of
  `é   b`). Phase 2 next.
- 2026-11-20: Phase 2 done. `PdAst` (every constructor of
  pandoc-types 1.23, with constructors, list building, a sorted
  metadata map and a `Walker` that visits inlines and then blocks,
  bottom up, splicing in what its methods return) and `PdJson`
  (`WriteDoc`; numbers as Haskell's `show` writes a Double, the
  shortest digits that read back, from `RealDigits` and
  `Strings.StrToLongReal`). `make test` passed under `-O2` and `-OC`:
  `PdJsonTest` writes eleven hand-built documents, nineteen numbers
  and a walked document; the documents' lines are pandoc 3.10's `-t
  json` output for the markdown in the test's comments and the
  numbers GHC's `show`, byte for byte, and the walk's line was
  checked by hand. Found on the way, for later phases: pandoc's YAML
  reads `y` in a flow list as `true` (YAML 1.1), a citation's
  `citationNoteNum` counts the notes before it, and `p. 3` in a
  citation suffix gets a no-break space. Ropes decided (Design).
  Phase 3 next.
- 2026-11-20: Phase 3 done. `PdMdBase` (the text, positions and the
  tests every block parser shares: lines, attributes, HTML tags, list
  starts, fences), `PdMdInline` (Str, Space, SoftBreak, LineBreak,
  escapes, numeric and the five XML entities, inline code with
  attributes and raw inlines, identifiers) and `PdMarkdown` (pandoc's
  `block` alternatives, in pandoc's order, with compactify, task
  lists and unique identifiers), and `podoc -t json`. `make test`
  passed under `-O2` and `-OC`, with six new cases (`blocks`,
  `lists`, `edges`, `inline-basic`, `empty`, `nonewline`), whose
  expected JSON is pandoc 3.10's, byte for byte. Differences found
  and left for Phase 4 are listed under Phase 3.3. Phase 4 next.
- 2026-11-20: Phase 4 done. `PdMdInline` reads pandoc's inlines:
  emphasis and strong emphasis, strikeout, superscript and subscript,
  inline and reference links and images, autolinks (pandoc's URI
  schemes, in `PdWords`), bracketed and HTML spans, inline and
  referenced notes, math, raw HTML and the general form of raw TeX,
  smart quotes, dashes and ellipses, the abbreviations after which a
  space is non-breaking (`PdWords`), every HTML5 named entity
  (`PdEntities`), and identifiers with Unicode letters. `PdMarkdown`
  adds reference keys, notes, implicit figures, pipe, simple and
  multiline tables (with captions), and resolves references and notes
  once the document is read; task list items are converted after
  that, as pandoc does. `tools/mkwords` and `tools/mkentities` write
  `PdWords` and `PdEntities`. `make test` passed under `-O2` and
  `-OC`, with three new cases (`links`, `inlines`, `tables`) whose
  expected JSON is pandoc 3.10's. Acceptance: of the 54 markdown files
  of Lost-Worlds and Galactic-Bounty-Hunters, 49 give pandoc's JSON
  byte for byte; the other five start with YAML metadata, and their
  blocks match pandoc's with `-yaml_metadata_block` byte for byte.
  Simple and multiline tables were brought forward from Later because
  the acceptance needs them (Phase 4.6); grid tables stay there. What
  the reader still lacks is listed in Later. Phase 5 next.
- 2026-11-20: Phase 5 done. `PdYaml` reads the YAML subset (block
  maps and sequences, flow collections, plain, quoted, literal and
  folded scalars with chomping and indentation indicators, comments,
  YAML 1.1 booleans and nulls, numbers as pandoc's YAML library reads
  them, duplicate-key warnings); anchors, aliases, tags, directives
  and complex keys are errors naming the construct. `PdMarkdown`
  reads YAML metadata blocks where pandoc's `yamlMetaBlock` does
  (after fenced code), later blocks winning key by key; strings are
  read as markdown and become `MetaBlocks` or, through
  `blocksToInlines`, `MetaInlines`; keys ending in `_` are dropped; a
  block that is not a mapping is read as other blocks. A parse error
  ends podoc with status 64, naming the file and line as pandoc does
  (inside a block quote, `f.md_chunk`); duplicate keys are warned of
  as pandoc does. `podoc` adds `-M`/`--metadata` (booleans as
  pandoc's `readMetaValue`, repeated keys as lists) and
  `--metadata-file` (missing: status 98; not a mapping: status 64);
  the metadata is the files', then the document's, then `-M`'s.
  `tools/runcases` checks `<name>.status`. `make test` passed under
  `-O2` and `-OC`: `PdYamlTest` (99 checks) and 21 new `meta-*` cases
  whose expected JSON is pandoc 3.10's, with expected standard error
  for the error and warning cases. Acceptance: all 54 markdown files
  of Lost-Worlds and Galactic-Bounty-Hunters give pandoc's JSON byte
  for byte, with nothing on standard error; 15 further YAML probes
  gave pandoc's JSON, and standard error and exit statuses matched
  pandoc's apart from the wording of YAML parse messages after their
  location line. Phase 6 next.
- 2026-11-20: Phase 6 done. `PdLayout` (doclayout's `Doc`: text,
  breaking spaces, new lines, blank lines, prefixes, nesting, hanging,
  `nowrap`, `chomp`, rendered at a width or unwrapped) and
  `PdTemplate` (the doctemplates language, parsed as doctemplates'
  Parsec parser does, with its error positions: variables, fields,
  conditionals with `elseif`, loops with separators, `it`, nesting
  with `$^$`, reflow with `$~$`, comments, partials and partials
  applied to values, and every pipe but `left`, `right` and `center`,
  which are compile errors). `PdContext`: `-V` as pandoc's
  `setVariable`, metadata in the context through a writer's block and
  inline procedures (a metadata string as `Builder.text` makes it),
  variables over metadata, `defField` and `resetField`, and templates
  and partials found as pandoc finds them (a file, the user data
  directory, then built in), with the format's extension tried for a
  name without one. `data/templates` holds pandoc 3.10's
  `default.html5`, `styles.html`, `styles.citations.html`,
  `default.ms`, `default.context` and `default.markdown`;
  `tools/mktemplates` builds them into `PdDefaults`. `podoc` adds
  `-s`, `--template`, `-V`, `-H`, `-B` and `-A`, and sets
  `sourcefile`, `outputfile`, `pandoc-version`, `include-before`,
  `include-after`, `header-includes` and `curdir` as pandoc's
  `outputSettings` does; no writer uses a template until Phase 7, so
  with `-t json` only a template's errors show. `make test` passed
  under `-O2` and `-OC`: `PdLayoutTest` (33 renderings, compared
  with the expected output), `PdTemplateTest` (doctemplates'
  21 golden tests that fit, pad.test left out and pipes.test adapted,
  and 12 more checks, among them error positions inside partials, as
  doctemplates gives them), `PdContextTest` (18 checks) and three
  cases for a missing template (97), a template that does not compile
  (5) and a missing `-H` file (99), with pandoc's messages but for its
  data directory path. Phase 7 next.
- 2026-11-20: Phase 7 done. `PdHtml` writes pandoc's HTML5: every
  block and inline, escaping, attributes (`data-` for unknown keys),
  section divs, task lists, ordered list types and starts, definition
  lists, figures, tables with column widths, alignment, `colgroup`,
  heads and feet, footnotes with back links, images with dimensions,
  `video`, `audio` and `embed` by media type (`PdMime`, from
  `data/mime-types.txt` through `tools/mkmime`), and raw `html`
  passed through. With `-s` it fills the default `html5` template:
  title, authors, date, keywords, `pagetitle` falling back to the
  input's name, `--css`, `--toc` and `--toc-depth`, `-N`. `podoc`
  adds `--wrap`, `--id-prefix`, `-N`, `--toc`, `--toc-depth` and
  `-c`/`--css`; `-s -t json` now ends without a new line, as
  pandoc's does. Reader fix: a paragraph followed by `: caption` and
  a table is no longer read as a definition list. `tools/compare`
  (`make compare`) runs pandoc and podoc side by side on the case
  inputs and the files in `test/compare.txt`. `make test` passed
  under `-O2` and `-OC`: 47 of 47 cases, among them 13 new `.html`
  expected files (pandoc's `--wrap=none --syntax-highlighting=none`
  output, except `inlines.html` and `tables.html`, which are podoc's
  because of TeX math). Acceptance: with `PANDOC=~/.cabal/bin/pandoc
  make compare`, 263 of 267 comparisons were the same; the four that
  differ are TeX math in the `inlines` and `tables` cases
  (docs/user/differences.md). All 49 markdown files of Lost-Worlds and
  Galactic-Bounty-Hunters gave pandoc's HTML byte for byte, without
  and with `-s`, and with `-s --toc -N`. Phase 8 next.
- 2026-11-20: Phase 8 done. `PdMs` writes pandoc's ms: escapes,
  fonts (`\f[...]` from the features on), small caps, smart
  punctuation, links and anchors as `.pdfhref` when `pdf-engine` is
  set, headings (`.SH`/`.NH`, PDF bookmarks, `.XS`/`.XE` entries for
  `--toc`), lists with pandoc's markers and indents, definition
  lists, block quotes, line blocks, code blocks, notes (`.FS`/`.FE`),
  images and figures (`.PSPIC`, `.PDFPIC`, sizes in points), CSL
  entries, and tables through `tbl`, as pandoc's `toLegacyTable` sees
  them, with column widths. `PdLayout` gains `SplitSentences`;
  `PdShared` takes `DocMeta`, `DocAuthors` and `NumUnit` from
  `PdHtml`; `PdAscii` (made by `tools/mkascii`) is pandoc's
  `toAsciiChar`. `podoc` adds `-t ms`, the default `ms` template
  under `-s`, and `--pdf-engine` (sets the variable, as pandoc does
  when the output is not PDF). `make test` passed under `-O2` and
  `-OC`: 126 checks, among them 16 new `.ms` expected files, three
  for the new cases `ms-features`, `ms-pdf` and `ms-standalone`
  (pandoc's output byte for byte); `blocks.ms`, `inline-basic.ms`,
  `inlines.ms` and `tables.ms` are podoc's, because of highlighting
  and TeX math (docs/user/differences.md), and the rest pandoc's.
  Acceptance: `tools/compare` with `ms` gave 168 of 178 the same, the
  ten that differ being highlighting and math; and all markdown files
  of Lost-Worlds, Galactic-Bounty-Hunters and the cases, each with
  `--pdf-engine=pdfroff`, `--pdf-engine=groff -N --toc`, `-s
  --template=tkb.ms -N --toc --pdf-engine=pdfroff`, `-s
  --template=statement.ms` and `-s --pdf-engine=groff -N --toc
  --toc-depth=2`, gave pandoc's ms byte for byte (330 runs), except
  the same highlighting and math. json and html still compare as
  after Phase 7. Phase 9 next.
- 2026-11-20: Phase 9 done. `PdConTeXt` writes pandoc's ConTeXt:
  escapes and ligatures, `toLabel` references, sections as
  `\startsectionlevel` (unnumbered, unlisted), emphasis and the other
  font commands, `\type` with pandoc's delimiter choice, math, raw
  `context` and `tex`, line breaks with struts, links (`\goto`) and
  autolinks (`\useURL`, numbered from the metadata on), images with
  their dimensions, notes (with `\startbuffer` when they hold code),
  spans and divs with `lang`, `dir` and ids, `refs`, block quotes,
  line blocks, itemize, enumerate (styles, start, stoppers, nesting),
  descriptions, rules, figures, and tables as `xtable`, with column
  spans clipped as pandoc annotates them. Standalone, the context
  fields: `toc`, `placelist`, `layout` from the margins, `context-lang`
  (`fromBCP47`), `papersize` (`a5` -> `A5`), `pdfa`, `context-dir` and
  the rest. `PdShared` takes `StripZeros`, `ShowFl` from `PdHtml`,
  `JoinLines`, `BlocksToInlines` from `PdMs`, `Fixed` (generalized
  from `Fixed1`) and `IsTightList`. `podoc` adds `-t context` and the
  default `context` template under `-s`; `tools/compare` runs every
  format but json also with `-s`, and `make compare` includes
  context. `make test` passed under `-O2` and `-OC`: 81 of 81 cases,
  among them 18 new `.context` expected files, two for the new cases
  `context-features` and `context-standalone`; all are pandoc's
  output byte for byte except `blocks.context`, podoc's because of
  highlighting (docs/user/differences.md). Acceptance: `make compare`
  gave 640 of 658 the same, the 18 that differ being math (html, ms)
  and highlighting (ms, context); and all markdown files of
  Lost-Worlds and Galactic-Bounty-Hunters, each with `-s -H cstyle.tex
  --include-in-header=header-includes.context`, `-s
  --template=tkb.context`, `-s --template=statement.context` and `-s
  --toc -N -V papersize=a4 -M lang=en-US`, gave pandoc's ConTeXt byte
  for byte (112 runs) except the four of `CLAUDE.md`, highlighting.
  The filters these builds use come in Phase 13. Phase 10 next.
- 2026-11-20: Phase 10 done. `PdMdWriter` writes pandoc's markdown
  (pandoc 3.10's default extensions, unwrapped, or with
  `--wrap=preserve` the input's line breaks): escapes where pandoc
  escapes, attributes, every inline (autolinks, reference-free links
  and images, notes, spans, code, math, raw), ATX headings with
  pandoc's identifier checks, fenced and indented code, fenced divs,
  block quotes, the lists with pandoc's markers, indents and
  `<!-- -->` separators, task lists, definition lists, line blocks,
  figures, simple and multiline tables (widths as doclayout's
  `realLength`), the HTML fallback for other tables, and notes at the
  end. Under `-s`: the metadata as a YAML block, the default markdown
  template, `--toc` and `-N`. Reader fixes: a paragraph that is only
  an indented HTML block no longer leaves an empty Plain; C1 controls
  and the soft hyphen have width 0 in tables, in the reader and in
  `PdLayout`. `tools/roundtrip` (in `make test`) writes each case
  named in `test/roundtrip.txt` with `-s --wrap=preserve -t markdown`
  and reads it again; the JSON must be the same. `make test` passed
  under `-O2` and `-OC`: 123 of 123 cases, among them 40 new
  `.markdown` expected files (pandoc's `--wrap=none -t markdown`
  output, byte for byte) and the new case `roundtrip`, and 23 of 23
  round trips. Acceptance: `make compare` gave 831 of 855 the same,
  json and markdown everywhere; the 24 that differ are math (html, ms)
  and highlighting (ms, context). pandoc's `testsuite.txt` and
  `tables.txt` give pandoc's markdown except where the reader does not
  read the `%` title block and raw TeX. On the user's 49 documents the
  round trip gives the same AST for 40; the other 9 read back exactly
  as pandoc's own round trip does (simple tables' alignments, curly
  quotes). For every case, podoc's markdown read back by podoc gives
  what pandoc gives for it, except for raw TeX blocks; where the
  round trip fails it fails in pandoc too
  (docs/user/differences.md). Phase 11 next.
- 2026-11-20: Phase 11 done. `PdOptions` holds the command line (with
  ArgParser) and works out the formats as pandoc 3.10's
  `OutputSettings` and `formatFromFilePaths` do: the input format from
  `-f`/`-r` or the inputs' extensions, the output format from `-t`/`-w`
  or `-o`'s extension (html by default), with pandoc's "Could not
  deduce format" warnings; PDF output from `-o *.pdf` or `-t pdf`, the
  writer and engine as `pdfWriterAndProg` chooses them, standalone,
  and the `pdf-engine` variable set after `pandoc-version`. New
  options: `-f`/`-r`, `--pdf-engine-opt`, `--lua-filter`,
  `-F`/`--filter`. `--wrap` and `--pdf-engine` errors now exit with 6,
  as pandoc's. `podoc.Mod` keeps only running. `make test` passed
  under `-O2` and `-OC`: the new `PdOptionsTest` (35 checks: file
  names, formats from names, PDF writers and engines), 131 of 131
  cases (8 new: errors for PDF from json, `-f rst`, `-f
  markdown+smart`, `--wrap=bad`, `--pdf-engine=xyz`, an unknown and a
  not yet built-in filter, and the mermaid filter ignored) and 23 of
  23 round trips. By hand, against pandoc: the same statuses and
  messages for format deduction (`.zz`, `/dev/null`, `-o x.zz`, `-o
  x.ms`), `markdown+foo` (23), PDF from json and context-with-html
  (4), `--wrap=bad` (6), `--pdf-engine=xyz` and a path (6, podoc
  listing only its engines) and unknown filters (83, podoc's second
  line). `make compare` gave 870 of 927 the same: the 24 differences
  of Phase 10, and 33 from the new cases where podoc deliberately
  differs (docs/user/differences.md). Phase 12 next.
- 2026-11-20: Phase 12 done. `PdInclude` runs for `-F pandoc-include`:
  `!include` and `$include` lines, `incrementSection`, globs (`PdGlob`,
  Python's `glob` and `fnmatch` with natsort's order; its C part,
  `PdGlob.c`, reads directories), recursion relative to the including
  file, the working directory as fallback, metadata merged with the
  outer keys winning, relative image paths rewritten, and cycles ended
  with status 83. The other keys end podoc with 83; unknown keys warn
  as pandoc-include does. `PdHtml` writes headers below level 1 as
  paragraphs, as pandoc. `make test` passed under `-O2` and `-OC`: the
  new `PdGlobTest` (23 matches against Python 3.14's `fnmatchcase`, 7
  orderings against natsort's), 146 of 146 cases (11 new `inc-*`
  cases) and 23 of 23 round trips. Against pandoc with
  pandoc-include 1.4.4: the JSON of the 5 user documents that include
  (Lost-Worlds' 001 and 002, Galactic-Bounty-Hunters' one-shot,
  pre-made characters and villains) is byte for byte pandoc's, and
  their markdown is `pandoc --wrap=none`'s (the `-whole.md`
  acceptance), both models. `inc-glob` (`*`, `**`, `?`, a hidden file,
  natural order, a bracket set) is byte for byte pandoc's. `make
  compare` gave 942 of 1017 the same: 48 of Phase 11's 57 (its
  other 9, `opt-filter-later`'s, now match pandoc), and 27 from `inc-cycle`, `inc-self` and
  `inc-option`, where podoc deliberately differs
  (docs/user/differences.md). Phase 13 next.
- 2026-11-20: Phase 13 done. `PdFilters` runs `subs`,
  `strip-comments`, `general`, `toc-columns` and `combine-docs` in
  place of the user's Lua filters; `-L` added; `tools/subs2yaml`
  converts `substitutions.lua`. `make test` passed under `-O2` and
  `-OC`: 166 of 166 case tests (20 new, from 13 new `filter-*` inputs;
  `opt-filter-later` renamed `filter-subs-missing`) and 23 of 23 round trips. The new
  cases' outputs and messages are pandoc 3.10's, byte for byte, run
  with copies of the user's filters (general's standard-output
  messages moved to standard error), and general's output and
  messages were the same as pandoc's for json, html, ms, context and
  markdown. Acceptance: the Lost-Worlds GNUmakefile's commands (gen.html,
  ms, ctx and digest-ctx for its 12 documents, and the combined
  digest), with the substitutions converted by `tools/subs2yaml`, gave
  49 of 49 outputs byte for byte pandoc's, with the same statuses, under
  both models; podoc wrote nothing on standard error. `FILTERDIR=...
  make compare` gave 1015 of 1134 the same: Phase 12's 75, and 44
  where podoc deliberately differs (`general`'s messages,
  `filter-subs-missing`; docs/user/differences.md). Phase 14 next.
- 2026-11-20: Phase 14 done. `PdRun` runs programs through
  `/bin/sh` and `Platform.System`; `PdPdf` makes PDF with pdfroff,
  groff and context. `make test` passed under `-O2` and `-OC`: the new
  `PdRunTest` (12 checks: quoting, exit statuses, signals, finding
  programs, the temporary directory), 168 of 168 case tests (new:
  `pdf-engine-missing`, `pdf-image-missing`, whose messages and
  statuses are pandoc's) and 23 of 23 round trips. By hand, against
  pandoc 3.10: the same `pdftotext` for pdfroff and groff (with
  `papersize=a4l` and a PDF image), and for context (Unicode dashes
  and quotes, a PNG, an SVG, a missing image); the same messages and
  statuses for a groff failure and a TeX error (43), a missing engine
  (47), and PDF to a terminal (4); `-t pdf -o -` to standard output.
  Acceptance, under both models: Lost-Worlds' 27 PDF targets (12 ctx,
  12 digest-ctx, 2 ms, the combined digest) and Galactic-Bounty-Hunters'
  6 (ctx, the one-shot with its JPEG and SVG maps) gave `pdftotext`
  output the same as pandoc's; podoc's standard error had only groff's
  own warnings, which pandoc's has too. No temporary directories were
  left. `FILTERDIR=... make compare` gave 1037 of 1152 the same.
  Phase 15 next.
- 2026-11-20: Phase 15 done; the proof of concept is finished. podoc
  built, and `make test` passed under `-O2` and `-OC` (the unit
  tests, 168 of 168 case tests, 23 of 23 round trips), on FreeBSD 15.1
  (alerik) and NetBSD 11.0 (artos), amd64, with poc 0.15.0, as on
  Fedora (atla). On NetBSD, `--pdf-engine=groff` failed with the base
  groff 1.19.2 (`invalid option -- k`, status 43) and `pdfroff` was not
  found (47). `make install` and `make uninstall` checked with a
  `DESTDIR` and `PREFIX=/usr/local`. docs/user/podoc.md written; README
  and AGENTS.md updated.
- 2026-11-20: podoc on yishana (NetBSD 11.0, i386, the first 32-bit
  machine), with poc 0.15.0 and pkgsrc's groff 1.24.1 in
  `/usr/pkg/bin` (the base groff 1.19.2 in `/usr/bin` comes first on
  its PATH, so `/usr/pkg/bin` was put first). ArgParser, Ropes and
  pounicode installed there; podoc built, and `make test` passed under
  `-O2` and `-OC` (168 of 168 case tests, 23 of 23 round trips).
  `--pdf-engine=groff` made 14 PDFs (ms-features, ms-pdf,
  ms-standalone, inlines, lists and tables with `-s -N --toc`, and
  ms-features with `-V papersize=a4l`, under each model), all with
  status 0; `-O2` and `-OC` gave the same `pdftotext`, and its words
  were the same as those of podoc's PDFs made on atla with groff
  1.23.0. Only the layout differed: pkgsrc's groff defaults to A4,
  and 1.24 spaces table-of-contents leaders differently; it also warns
  that font `C` is deprecated and of an unbalanced `.RE`. pkgsrc's
  groff has no `pdfroff`, so `--pdf-engine=pdfroff` there ends with 47.
  Found on the way: display math that pandoc cannot convert to `eqn`
  is written as `.RS 3`, the TeX, then `.RE` with the following text
  on the same line, which groff drops; podoc, which never converts
  math, always writes this fallback, byte for byte pandoc's, so the
  text after display math is lost in ms PDF as in pandoc's. Left as
  pandoc does it; the user's documents use no display math.
- 2026-11-20: podoc on terhali (NetBSD 11.0, amd64) and erekose
  (OpenBSD 7.9, i386, the first OpenBSD), after upgrading both to poc
  0.15.0 and rebuilding their installed libraries with it (on erekose,
  pofltk needs `FLTK_CONFIG=/usr/local/sw/versions/fltk/1.4.5/bin/fltk-config`,
  since the `fltk-config` on its PATH is OpenBSD's FLTK 1.3.9).
  pounicode installed on both; podoc built from a clean `git archive`,
  and `make test` passed under `-O2` and `-OC` on each (382 `ok`
  lines, no `FAIL`, 23 of 23 round trips). PDF output was not tried there.
- 2026-11-20: PDF output on erekose and terhali. podoc built from a
  clean `git archive` under both models; each document of the ms test
  cases made with `--pdf-engine=pdfroff` and `--pdf-engine=groff`; the
  `-O2` and `-OC` PDFs were the same, and no temporary directories were
  left.
  - erekose, groff 1.22.4 (OpenBSD package): 26 of 26 runs ended with
    status 0. Against podoc's PDFs on atla (groff 1.23.0), 12 of 24
    have the same words; the other 12 (`-s -N --toc`) differ only in
    the contents page's number, "1" for 1.22.4, "i" for 1.23.0.
    Warnings: an unbalanced `RE` (the display-math fallback) and
    missing glyphs U+2610, U+2612 and U+2082. `-t context` ends with
    47: no ConTeXt there.
  - terhali, base groff 1.19.2: `groff` ends with 43 (`invalid option
    -- k`), `pdfroff` and `context` with 47 (pkgsrc's tex-context has
    `mtxrun` but no `context`). Its groff 1.23.0 under
    `/usr/local/sw/versions` is broken: `preconv` cannot find
    `libiconv.so.2`; `groff` ends with 43 and `pdfroff` makes empty
    PDFs.
  - groff 1.25.0 on both (configure found Ghostscript, 10.08.0 on
    terhali, 10.07.1 on erekose): `--pdf-engine=groff`, 14 of 14 runs
    ended with status 0 on each host, and `-V papersize=a4l` gives A4.
    inlines, lists and tables have atla's words. But in ms-features,
    ms-pdf and ms-standalone each heading is followed by a stray line,
    `.pdfbookmark "1" "Plain heading" Plain heading Plain heading`:
    1.25's `s.tmac` diverts the heading (`box @NHpdf`) and makes the
    bookmark itself, so the `.pdfhref O` pandoc and podoc put after
    the heading text runs inside the diversion and is printed. pandoc
    3.10's ms has the same `.pdfhref O`. Fixed by decision 9's `.br`,
    below.
  - groff 1.25.0 does not ship `pdfroff` or `pdfmark.tmac` (its NEWS:
    the pdfmark package is now maintained separately, as
    groff-pdfmark; 1.24.2, below, does not ship them either). terhali: `pdfroff` ends with 47. erekose: 1.22.4's
    `/usr/local/bin/pdfroff` is found instead, cannot load `pdfmark`
    with 1.25's troff, exits 0 and leaves an empty PDF, which podoc
    cannot tell from a good one.
  - `groff -ms -Tutf8` on podoc's standalone ms-features ran over two
    minutes on terhali without finishing; podoc does not use `-Tutf8`.
- 2026-11-20: groff 1.24.2 (`/usr/local/sw/versions/groff/1.24.2/bin`
  first in the PATH) on atla, terhali and erekose, with the same runs
  as for 1.25.0 (podoc from a clean `git archive`, both models).
  - `--pdf-engine=groff`: 14 of 14 runs ended with status 0 on each
    host. All 12 PDFs on each have the same words as podoc's on atla
    with groff 1.23.0, the contents page numbered "i"; no stray
    `.pdfbookmark` line, so that problem is new in 1.25. The bookmarks
    are made (checked with `mutool show ... outline` on atla's ms-pdf),
    and better than 1.23.0's: "H₂O" and the curly quotes are kept.
    `-O2` and `-OC` gave the same PDFs; `-V papersize=a4l` gives A4; no
    temporary directories left. Warnings as with 1.23.0: an unbalanced
    `.RE`, U+2610 and U+2612 undefined, font name `C` deprecated.
  - 1.24.2 has no `pdfroff` either: the pdfmark package left groff
    in 1.24, not 1.25. terhali: `--pdf-engine=pdfroff` ends with 47.
    atla and erekose: an older `pdfroff` later in the PATH (1.23.0's,
    1.22.4's) cannot load `pdfmark` with 1.24.2's troff, exits 0 and
    leaves an empty 2.4 KB PDF (12 of 24 runs on each).
  - So the stray heading line is new in groff 1.25.
- 2026-11-20: the `.br` of decision 9. On atla, groff 1.25.0 by hand
  on ms-pdf's ms: without `-r PDFFEAT=1` (which podoc does not pass;
  1.25's NEWS calls ms's own PDF features opt-in for now), podoc's
  ms as it was gave no bookmarks at all and the stray lines; with the
  `.br`, podoc's bookmarks, correct titles, internal links and their
  targets, and no stray lines; with `-r PDFFEAT=1` each heading gets
  two bookmarks, ms's and podoc's. Moving the `.pdfhref` lines before
  `.SH` instead left a stray line and lost the second bookmark.
  `make test` passed under both models (382 `ok`, no `FAIL`, 23 of 23
  round trips; ms-pdf.ms and ms-standalone.ms gained their `.br`).
  Then the PDF runs (6 documents, `pdfroff` and `groff`, `-O2` and
  `-OC`) from the working tree on atla, terhali and erekose, each with
  groff 1.23.0, 1.24.2 and 1.25.0 first in the PATH:
  - 1.23.0, both engines, all hosts: every run ended with status 0;
    all 12 `-OC` PDFs on terhali and erekose have the same words as
    atla's, with bookmarks. (terhali's 1.23.0 works now; it did not
    earlier today.)
  - `--pdf-engine=groff` with 1.24.2 and 1.25.0, all hosts: every run
    ended with status 0; no stray lines; ms-pdf and ms-standalone have
    their bookmarks (H₂O and curly quotes kept). 1.24.2 has 1.23.0's
    words; 1.25.0 differs only in ms-features, ms-pdf and ms-standalone,
    where a footnote mark in an `.IP` label is 3, where 1.23.0 and
    1.24.2 say 4 (1.25.0's is the right number).
  - `--pdf-engine=pdfroff` with 1.24.2 and 1.25.0: 47 on terhali; on
    atla and erekose the older `pdfroff` exits 0 and leaves 6 empty
    PDFs of 12, as before.
  - `-O2` and `-OC` gave the same words everywhere; no temporary
    directories left.
- 2026-11-20: a reStructuredText document through markdown. The
  Minimal OpenD6 SRD (`~/current/RPG/Mini-Six/SRD`, 5,090 lines of
  reST, raw ms and ConTeXt blocks, grid and simple tables, line
  blocks) translated with `pandoc -s -r rst -w markdown-grid_tables
  --columns=110` (grid tables become multiline tables; the wider
  columns keep a 107-column grid table's proportions). podoc's JSON
  from it is byte for byte pandoc 3.10's. Its makefile's
  `.stmt.ms.pdf` options with `-r markdown` (template `statement`,
  `-L general.lua`, `--pdf-engine-opt=-P-p8.5i,5.5i`), with groff
  1.23.0 on atla, made 83 pages, as the existing PDF (pandoc from the
  reST, groff 1.23.0) has; `pdftotext` gives the same text but one
  quote (the source's `”Contributors”`, which the translation makes
  `“Contributors”`). At 50 dpi 75 pages are pixel-identical; 6 differ
  in a few table column widths (a multiline table's widths come from
  its dashes, and cannot hold reST's exact widths or `:widths:`), one
  in the quote, one (66) in a sentence space. pandoc's `--wrap=none`
  ms from the same markdown is byte for byte podoc's; its default
  wrapping ends a line after `Speck!”`, where groff adds sentence
  space, which is page 66's difference. The SRD's files were not
  changed.
- 2026-11-20: the SRD's markdown on erekose and terhali, with groff
  1.25.0 first in the PATH, and on atla the same way: a clean archive
  of HEAD, `gmake build/OC/podoc`, then the `.stmt.ms.pdf` options.
  Every build and podoc run ended with status 0; each PDF has 83
  pages and 301 bookmarks and no stray lines, and the three give the
  same `pdftotext` text. Against atla's groff 1.23.0 PDF, 1.25.0
  repeats a word in each of three headings that wrap to a second
  line ("Minimal OpenD6 OpenD6 &", "Ideas? Ideas?", "from from").
  That is groff 1.25.0's ms: `.nr LL 3i`, an `.SH 1` (or `.NH 1`)
  with "Converting Between Minimal OpenD6 & Traditional OpenD6", and
  `.LP` give, with no podoc output and no template, a spaced-out
  first line and "Traditional Traditional OpenD6", under `-Tpdf` and
  `-Tps`; 1.23.0 and 1.24.2 set it correctly. Its `.SH` and `.NH`
  box the heading and end the box with a trap one line down
  (`dt 1v @NH-end`), which springs while the second line is being
  filled. pandoc's ms is hit the same way; podoc does nothing about
  it. The template's `.special S Symbola` fails under 1.25.0 on all
  three hosts (Symbola is installed only for atla's 1.23.0); it does
  no harm, as the 1.23.0 PDF uses only Palatino and Symbol. 1.25.0's
  tables are also a little narrower in places. Temporary directories
  removed on all three hosts.
- 2026-11-20: the same heading on atla under groff 1.25.0's terminal
  devices. `-Tascii`, `-Tutf8` and `-Tlatin1` all give "Converting
  Between Minimal", then a spaced-out "OpenD6 OpenD6 & Traditional",
  then "OpenD6" on a third line; 1.24.2 gives "Converting Between
  Minimal" and "OpenD6 & Traditional OpenD6". The wider characters
  break the first line sooner than under `-Tpdf`, so the repeated
  word is a different one, but it is again the word at the start of
  the second line. So the bug is in ms, not in a device.
- 2026-11-20: the SRD's markdown on atla, erekose and terhali with
  groff 1.24.2 first in the PATH, built as for 1.25.0. Every build
  and podoc run ended with status 0; each PDF has 83 pages and 301
  bookmarks, and the three PDFs are the same. Against atla's groff
  1.23.0 PDF the words are the same (no repeated heading words), and
  every word but the page number is within 0.02 pt of its place
  (`pdftotext -bbox`), so lines and pages break the same. The page
  number sets 12 pt (one vee) higher on every page: 1.24's ms
  subtracts one vee from the footer trap that `FM` gives (its NEWS);
  `statement.ms` sets `FM` to 0.75i. 1.24.2's gropdf subsets the
  fonts (209 KB against 737 KB), so `pdftotext` splits "−5" into two
  words on seven pages and spaces the scale table's columns
  differently, though the glyphs have not moved. The Symbola error is
  as under 1.25.0. Temporary directories removed on all three hosts.
- 2026-11-20: Phase 16.1 done. `-t plain` and `-s` with pandoc
  3.10's `default.plain` (`PdOptions`, `podoc`, `PdDefaults` through
  `tools/mktemplates`). `PdMdWriter` has a plain mode (`SetPlain`)
  that follows each `PlainText` branch of pandoc's markdown writer:
  Str unescaped; emphasis, strong, underline and spans as their
  contents; small caps in capitals, notes inside them too; curly
  quotes; code as its text; superscripts and subscripts in Unicode
  where every inline converts, else the rendered text through
  `toSuperscript`, else `^(...)` or `_(...)`; links as their text or
  autolinks as the URL; images as `[alt]`; notes `[n]`; headings,
  divs and figures with attributes as their contents; code blocks
  indented; block quotes indented two spaces; line blocks as their
  lines; definitions indented two spaces; raw content kept only for
  `plain`; no task-list boxes; `Plain []` as the list separator; the
  title, authors and date as the title block; a final `refs` div
  kept. pandoc 3.10 gives no warning for dropped raw content (it is
  INFO), so podoc gives none. TeX math is written as texmath's
  fallback, `$...$` and `$$...$$`: none of the user's documents has
  math, so no subset of texmath was ported (docs/user/differences.md).
  Tables pandoc writes as grid tables are `[TABLE]` until 16.3.
  `make test` passed under `-O2` and `-OC`: 212 case tests (44 new
  `.plain` files: pandoc's `--wrap=none -t plain` output for the 41
  markdown-writer cases whose output is the same, podoc's for the
  three with TeX math; a new `plain-features` case, `-s`, the same
  as pandoc's; and `filter-general-plain`, whose body is pandoc's,
  its filter messages on standard error) and 23 round trips. `make
  compare` with `plain` (now in `COMPARE_FORMATS`): all 98
  comparisons of the user's documents the same; the case differences
  are TeX math and the known filter, include and option cases.
  pandoc's `test/testsuite.txt` by hand: the same but for the `%`
  title block and the raw TeX table, which podoc's reader does not
  read, and math; it was not added as a case. `--wrap=preserve` the
  same as pandoc's on `plain-features`. There is no `tools/mkcase`.
  Phase 16.2 next.
- 2026-11-20: Phase 16.2 done. `PdGridTable` follows the
  `gridtables` package (the character grid, `toCharGrid` with a
  zero-width character absorbing the next, the outline, `=` header
  and footer separators, `:` alignments, row and column spans) and
  `PdMarkdown` pandoc's `Parsing/GridTable.hs` (cells parsed as
  blocks, widths from the dashes against 72 columns, captions,
  indented tables). Character widths for all tables are now
  doclayout 0.5.0.3's (`PdWidth`, written by the new `tools/mkwidth`
  from doclayout's `unicodeWidth.inc` with `updateMatchStateNarrow`'s
  shortcut ranges laid over it: 797 ranges; the shortcuts differ from
  the table on 22 characters), with a combining character first in a
  cell counting 1 as in `realLength`. `grid_tables` is the one
  extension `-f markdown±grid_tables` turns on or off (`PdOptions`);
  every other one still ends podoc with 23. A table's lookahead
  (`TableAt`) now restores header identifiers and implicit header
  keys, which cells had registered twice. The ms writer now places
  spanned cells as pandoc's `toLegacyTable` does (`PdShared.LegacyRows`,
  `placeCutCells`), for 16.3's writers too. Two reader fixes from
  pandoc's `many1Till`, found through the SRD's tables: `$$$` is text,
  not math, and `"""`, `'''`, `""a"` and the like give pandoc's
  quotes. New cases: `grid-tables` (samples of its own and the grid tables of
  pandoc's `test/markdown-reader-more.txt`; `.json` pandoc's, `.html`,
  `.ms` and `.context` the same as pandoc's `--wrap=none`),
  `grid-tables-off`, `opt-from-ext2`, `math-dollars` and
  `quotes-empty`. `make test` passed under `-O2` and `-OC`: 220 case
  tests and 23 round trips. The 8 `test/command/*.md` with grid tables
  that podoc reads: JSON the same as pandoc's, byte for byte, both
  models. `make compare`: the same 193 differences as before the width
  change. Acceptance: `pandoc -r rst -w markdown` writes the Minimal
  OpenD6 SRD's tables as multiline tables at both 72 and 110 columns,
  so its JSON (the same as pandoc's on both models) has no grid
  tables; the SRD's 12 grid tables were taken from the reST into a
  markdown file instead, and give pandoc's JSON byte for byte on both
  models. Phase 16.3 next.
- 2026-11-20: Phase 16.3 done. `PdMdWriter` writes grid tables
  (pandoc's `gridTable`: `GridSection`, `AddDummies`, `RedoWidths`,
  `FormatBorder`, `FormatRow`) and pipe tables (`PipeTable`), choosing
  among simple, multiline, grid, pipe, HTML and `[TABLE]` in pandoc's
  order. A row of empty cells is now one line, as in doclayout, in
  multiline and simple tables too. Checked against `pandoc --wrap=none`,
  byte for byte, under both models, in markdown and plain:
  `test/cases/grid-tables.md`, a grid table with an empty row and a
  footer, pandoc's `test/tables.markdown`, and pipe-table input of 10
  columns (which pandoc writes as simple and multiline tables). The
  markdown round trip gives the same JSON as pandoc's own round trip on
  all of them; neither is exact (pipe tables' default alignments
  become left, column widths change). pandoc's markdown reader never
  gives a table whose writer output is a pipe table (a lone Para in a
  grid cell becomes Plain, `plainify`; other tables' cells are
  Plain), so `PipeTable` is unreachable from podoc's input; it was
  checked with a scratch build without `plainify`, against
  `pandoc -f json` on that build's JSON: alignments, a caption, `\|`
  in a cell, a headless table, dashes from relative widths past 72
  columns, both models, the same byte for byte. The approximate pipe
  table for spans without raw HTML went to Later. New cases:
  `pipe-tables`, `grid-tables-foot`; `grid-tables` gained `.markdown`
  and `.plain`. `make test` passed under `-O2` and `-OC`: 228 case
  tests and 23 round trips. `make compare`, run with the podoc of HEAD
  (a12d530) and with this one on the same inputs: 218 and 210
  differences of 1507; the 8 fewer are the grid tables in markdown and
  plain, and none is new. (The 193 recorded for 16.2 was counted
  before inputs added since.)
- 2026-11-20: Phase 16.4 done. `-t plain+gutenberg`: emphasis between
  underscores, strong and level-1 headings in capitals (the writer's
  existing upper-case mapping, as for small caps, walking into notes),
  level-1 headings with three blank lines before and two after,
  level-2 headings with two before. `PdOptions` splits `-t` into the
  format and its extensions: `plain` takes `gutenberg`, `markdown`
  takes it without effect, every other writer and every other writer
  extension ends podoc with 23 (pandoc's message for `gutenberg`,
  podoc's for others); `-f markdown+gutenberg` is accepted. Fixed a
  16.2 bug: an extension both enabled and disabled is on, whatever the
  order, as pandoc's `(default \ disabled) ∪ enabled` (it was the
  last one). Checked against pandoc 3.10, byte for byte, under both
  models: `plain+gutenberg` with and without `-s`,
  `markdown+gutenberg`, `plain-gutenberg`, `plain+gutenberg-gutenberg`
  and the reverse; exit statuses and messages for `html`, `html5`,
  `ms`, `context` and `json` `+gutenberg` (23), `foo+gutenberg` (22),
  `ms+gutenberg -o x.pdf` (23), `plain+gutenberg -o x.pdf` (4), and
  the three orders of `grid_tables`. New cases: `gutenberg`,
  `gutenberg-markdown`, `gutenberg-html`, `opt-from-ext3`. `make test`
  passed under `-O2` and `-OC`: 232 case tests and 23 round trips.
  Phase 17.1 next.
- 2026-11-20: Phase 17.1 done. `--columns` (`PdOptions`; 72 by
  default; exit 6 with pandoc's message for a value that is not a
  number greater than 0, spaces around it allowed). `-t plain` with
  `--wrap=auto` wraps at it. `--columns` is also the reader's
  `readerColumns`, as in pandoc: it sets the relative widths of
  multiline, simple, pipe and grid tables, so the JSON changes with it
  (checked against pandoc at 10, 30, 50 and 100 columns). In the
  writer: table widths from `--columns`; cells laid out as doclayout's
  `block` does (rendered at the column width, then chopped,
  `PdLayout.Chop`); multiline and simple tables' widths from the
  cells' minimal widths when wrapping (`PdLayout.Offset`, `MinOffset`)
  and grid tables' as `gridTable` (`RedoWidths`); pandoc's
  `avoidBadWraps` (`PdLayout.AvoidBadWraps`, with
  `isOrderedListMarker` in list items); attributes' parts separated
  by breaking spaces, as `attrsToMarkdown`'s `hsep`; a table row's
  missing lines not padded. Checked against pandoc 3.10, byte for
  byte, `-t plain` at 10, 20, 30, 72 and 100 columns, with
  `--wrap=none` and `--wrap=preserve`, and `plain+gutenberg` at 72 and
  30, on every case without format or wrap arguments and pandoc's
  `testsuite.txt` and `tables.markdown`: the same but for math (as
  recorded) and, in `testsuite.txt`, the `%` title block and raw TeX
  the reader does not read. On the user's 54 markdown documents, at
  40, 72 and 100 columns, under `-O2` and `-OC`: all the same. Long
  words, URLs, East Asian text, nested lists and quotes, definition
  lists, notes, pipe tables, line breaks and code at 72, 25 and 12
  columns: the same. `PdLayoutTest` gained `Offset`, `MinOffset`,
  `Chop` and `AvoidBadWraps` tests, their expected output computed
  with pandoc's `pandoc.layout` (doclayout). The 17 `plain` cases
  without `--wrap` now expect wrapped output, each checked against
  pandoc with its arguments first; new cases `plain-wrap`,
  `plain-columns` (12 columns) and `columns-error`. `-t markdown` is
  not wrapped yet. `make test` passed under `-O2` and `-OC`: 235
  case tests and 23 round trips. `tools/compare` now runs podoc with
  `--wrap=none` too, as it runs pandoc, now that wrapping is podoc's
  default. `make compare` (with an 8G memory cap: pandoc-include's
  endless recursion on `inc-cycle` passes 4G within its 10 seconds,
  and the scope is killed): 1374 of 1584 the same; with HEAD's podoc,
  1352, its 22 extra differences all `--columns` cases; no new
  difference. Phase 17.2 next.
- 2026-11-20: Phase 17.2 done, and with it Phase 17. `-t markdown`
  wraps at `--columns` under `--wrap=auto`, the default (`podoc.Mod`
  passes it to `PdMdWriter.SetWrapping`; the writer needed nothing
  more). Checked against pandoc 3.10, byte for byte: every case
  through `tools/compare` changed to wrap, at 72 and 40 columns (the
  same differences as unwrapped, all earlier ones: filters pandoc
  does not find, `-f` extensions); a file of markdown-only constructs
  (YAML metadata, heading, span, code, image and div attributes,
  notes, line blocks, quotes, definition lists, bad wraps, rules,
  reference links) at 12, 20, 30, 50, 72 and 100 columns, with and
  without `-s`, and with `--wrap=preserve`; pandoc's `tables.markdown`
  at 72 and 20; `testsuite.txt`, the same but for the `%` title block
  and raw TeX the reader does not read. On the user's 54 markdown
  documents at 40, 72 and 100 columns, with and without `-s`: 324
  runs each under `-O2` and `-OC`, all the same, so the `-whole.md`
  targets come out as pandoc writes them. The 18 `markdown` cases
  without `--wrap` now expect wrapped output, each checked against
  pandoc with its arguments first (`filter-general-markdown`: the same
  but for `general.lua`'s messages, as before); `plain-wrap` and
  `plain-columns` gained `markdown` expected files, the same as
  pandoc's. `tools/roundtrip` also writes each case wrapped at 20
  columns and checks that, read and written with `--wrap=none`, it is
  the case written with `--wrap=none`: all 23 pass; at 8 and 10
  columns, all but `roundtrip`, whose task list item's `[x]` wraps
  away from its marker and reads back as text, in pandoc too
  (recorded in docs/user/differences.md). `make test` passed
  under `-O2` and `-OC`: 237 case tests and 23 round trips.
- 2026-11-20: Phase 18.1 done. `-t ms` wraps at `--columns` under
  `--wrap=auto` (`PdMs.SetWidth`, set by `podoc.Mod`; the writer's
  `afterBreak "\\&"` and `nowrap`s were already pandoc's). Checked
  against pandoc 3.10: every case through `tools/compare` changed to
  wrap, at 72 and 30 columns: 236 of 288 the same, the same
  differences as unwrapped. A file of ms edge cases (lines that would
  start with `.` or `'`, title, authors and abstract, a heading,
  inlines, links, notes, a quote, lists, a definition list, a line
  block, a table, a figure, a hard break, a rule) at 10, 20, 30, 50, 72 and 100 columns, plain,
  with `-s`, with `--toc -N -s`, with `--wrap=preserve` and with
  `--pdf-engine=groff -s`: the same but for the documented `.br`
  after a heading. `tables.markdown` at 20 and 72, plain, `-s` and
  `--wrap=preserve`: the same; `testsuite.txt`: the known differences
  only (the `%` title block, now wrapped too; eqn math; raw TeX). The
  user's 54 documents at 40, 72 and 100 columns, with and without
  `-s`, under `-O2` and `-OC`: 648 runs, all the same but the 12 of
  Galactic-Bounty-Hunters' CLAUDE.md, whose difference is highlighted
  code, as unwrapped. The six `ms` cases whose expected files changed
  were checked against pandoc with their arguments first (the
  differences: highlighting, eqn math, the `.br`, `general.lua`'s
  messages); `plain-wrap` and `plain-columns` gained `ms` expected
  files, the same as pandoc's. A wrapped document (`plain-columns`,
  `--columns=20 -s --toc -N`) makes PDFs through `pdfroff` and
  `groff -Tpdf`, with the same words as unwrapped. Found on the way,
  as in pandoc: display math that is not converted to eqn ends with
  `.RE` and the next text on the same line (`.RE and more`), so groff
  drops that text; podoc does as pandoc does. `make test` passed under
  `-O2` and `-OC`: 239 case tests and 23 round trips. `make compare`:
  1374 of 1584 the same, as before; the `ms` differences are the
  unwrapped ones.
- 2026-11-20: Phase 18.2 done, and with it Phase 18. `-t context`
  wraps at `--columns` under `--wrap=auto` (`PdConTeXt.SetWidth`,
  set by `podoc.Mod`; pandoc's ConTeXt writer keeps nothing from
  wrapping). Checked against pandoc 3.10: the ms edge-case file of
  18.1 at 10, 20, 30, 50, 72 and 100 columns, plain, with `-s`, with
  `--toc -N -s` and with `--wrap=preserve`: all the same.
  `tables.markdown` at 20 and 72, plain, `-s` and `--wrap=preserve`:
  the same; `testsuite.txt`: the known differences only (the `%`
  title block and raw TeX, now wrapped). The user's 54 documents at
  40, 72 and 100 columns, with and without `-s`, under `-O2` and
  `-OC`: 648 runs, all the same but the 12 of Galactic-Bounty-Hunters'
  CLAUDE.md (highlighted code, as unwrapped) and 8 at 40 columns, of
  `galactic_bounty_hunters_one_shot.md` and its `-whole.md`: a
  heading starting `🏛️` (U+1F3DB U+FE0F) wraps one word later,
  because `PdWidth` counts the emoji and its variation selector as
  one column where doclayout counts two (the emoji-sequence entry in
  "Later"; recorded in docs/user/differences.md). The 16 `context`
  cases whose expected files changed were checked against pandoc with
  their arguments first: the same, but for `filter-general-context`
  (`general.lua`'s messages, as before) and `filter-combine`, whose
  filters pandoc does not find here; its wrapped output has the
  expected file's words. `plain-wrap` and `plain-columns` gained
  `context` expected files, the same as pandoc's. The edge file makes
  PDFs through `context` wrapped (`--columns=20 -s --toc -N`) and
  unwrapped, with the same words; as in pandoc, the wrapped line
  block's lines break in the PDF too, since `\startlines` keeps line
  breaks (the user's documents have no line blocks). `make test`
  passed under `-O2` and `-OC`: 241 case tests and 23 round trips.
  `make compare`: 1374 of 1584 the same, the same differences as
  before.
- 2026-11-20: Phase 18.3 done. `PdWidth` joins emoji sequences as
  doclayout's `realLength` does (`PdWidth.State`, generated by
  `tools/mkwidth` from doclayout 0.5.0.3 and emojis 0.1.5, the
  versions pandoc 3.10 was built with: 1438 emoji start characters,
  the keycap bases `#`, `*` and `0`..`9` among them), used for
  `PdLayout`'s widths, the reader's table widths and the grid table
  reader's grid width; the character ranges are unchanged. Checked
  against pandoc 3.10, under `-O2` and `-OC`: a file of 30 sequences
  (emoji with U+FE0F, skin tones, ZWJ sequences, keycaps, flags,
  each modifier alone, after a letter and at a line's start) in
  paragraphs, pipe and simple tables, as `json`, `context`,
  `markdown`, `plain` and `ms` at 20, 40 and 72 columns: all 30 runs
  the same; grid tables with sequences in their cells, in all five
  formats: the same (before, the grid of one was a column wider
  than pandoc's). The user's 54 documents as `context`, `ms`,
  `markdown` and `plain` at 40, 72 and 100 columns, with and without
  `-s`: 1296 runs per model, all the same but the 12 of
  Galactic-Bounty-Hunters' CLAUDE.md (highlighted code); the one-shot
  heading's difference is gone. New: `PdWidthTest` (19 widths, by
  doclayout's rules) and the case `emoji-widths` (`--columns=40`,
  expected files pandoc's, the same as podoc's). `make test` passed
  under `-O2` and `-OC`: 246 case tests and 23 round trips.
  `make compare`: 1385 of 1595 the same, the 11 new comparisons all
  the same and the differences as before.
- 2026-11-20: research on reading reStructuredText,
  docs/research/rst-implementation.md; the user's decisions 18 to 22.
  The JSON writer now writes U+0008 and U+000C as `\u0008` and
  `\u000c`, as pandoc's aeson does, where it wrote `\b` and `\f`
  (found by reading the user's rST, translated to markdown, in podoc
  and pandoc: two files with form feeds). New case `json-control-chars`
  (expected JSON pandoc's). `make test` passed under `-O2` and `-OC`:
  247 case tests and 23 round trips.
- 2026-11-20: performance fixes found by comparing podoc with pandoc
  on pandoc 3.10's `MANUAL.txt` repeated 1 to 40 times (300 KB to
  12 MB), on atla.
  - `PdLayout.Chomp` recursed once per part down a document's right
    spine and overflowed the 8 MB stack: `-t ms`, `context` and
    `markdown` crashed (SIGSEGV) from ×4 on. `Chomp` and
    `RemoveFinalNl` are now loops with an explicit stack, and
    `MapText`, `AllText` and `HasNewlines` work on `Unfold`'s parts.
    All five writers now run at ×10 under `-O2` and `-OC`.
  - The reader looked header identifiers and reference keys up in
    linear lists with `Ropes.Equal`, which allocates on every call:
    quadratic time, most of it in the collector. Now they go through
    hash tables (`Ropes.Hash`, 4096 buckets). The lists are kept, so
    that `TableAt` can still undo a table's identifiers, and the hash
    tables are undone with them. `-t json` at ×10 went from 2.41 s to
    0.30 s; ×40 takes 1.53 s; the collector's share is 45-52% from ×1
    to ×40, no longer growing.
  - What first looked like the collector slowing was this, not poc.
  - Output was the same before and after: JSON at ×1, ×4 and ×10;
    `ms`, `context` and `markdown` at ×1 and ×2 (the old build crashed
    at ×4); `plain` and `html` at ×4.
  - New in `PdLayoutTest`: right and left spines of 1,000,000 parts
    through `Chomp`, `RemoveFinalNl`, `MapText`, `AllText` and
    `HasNewlines`; the old `PdLayout` fails it with SIGSEGV.
  - `make test` passed under `-O2` and `-OC`, 23 round trips.
    `make compare`: 1396 of 1606 the same; 210 differ, as many as
    before.
- 2026-11-20: the layout writers' memory use fixed; see
  `docs/developer/memory-use-problem.md`.
  - `Chomp` and `RemoveFinalNl` keep the nodes they don't change;
    `Doc` nodes are smaller and the breaks shared; `PdLayout` renders
    as it walks the tree, with no flattened copy; `PdMs.EscapeStr` and
    `Literal` no longer copy words that need no change; without a
    template, ms, ConTeXt, markdown and plain lay the body out a block
    at a time (`PdLayout.Open`, `Put`, `PutAbove`, `Close`).
  - The markdown writer's header identifiers (`Used`, `Use`) are a
    hash table, not a linear list: markdown and plain at ×40 went
    from 15 s to 2.8 s.
  - MANUAL ×10, `-OC`: ms 453 to 140 MB peak RSS, ConTeXt 341 to
    142 MB, markdown 367 to 140 MB, plain 364 to 140 MB, each about
    twice as fast. At ×40 every writer finishes, within 550 MB; ms and
    markdown used to run out of the 1 GB heap.
  - Output unchanged: the build before these changes against the new
    one on 35,910 runs (test/cases, pandoc's testsuite, tables,
    `MANUAL.txt` and test/command, Lost-Worlds and
    Galactic-Bounty-Hunters; ms, context, markdown, plain, gfm and
    commonmark; `--wrap=none`, `auto`, `preserve`, `auto
    --columns=30` and `-s`), byte for byte: none differed.
  - `make test` passed under `-O2` and `-OC`: 540 ok, 0 FAIL, 23
    round trips. `tools/bench convert` rerun; its results are in
    `docs/developer/performance.md`.
- 2026-11-20: Phase 21, images in ms output (decision 23), planned.
  podoc's ms output for `.pdf`, `.svg` with a width, `.png` and
  `.eps` images was checked identical to pandoc 3.10's; neither
  converts images for ms. img2pdf, magick and gm compared on a JPEG
  and two PNGs (Phase 21).
- 2026-11-20: With a template (`-s`), the ms, ConTeXt, markdown and
  plain writers lay the body out a block at a time too.
  - `PdTemplate.Slot` finds a template's one top-level `$body$`. It
    must have no pipes, `body` must be used nowhere else, and nothing
    after it may nest. `RenderBefore` and `RenderAfter` render the
    parts either side of it.
  - `PdLayout.OpenWhole` writes what `Write` writes, unchomped.
    `BeginSlot` and `EndSlot` take the body's blocks as one value with
    its final new line removed.
  - Some fields depend on writing the body: ms `has-inline-math`, and
    ConTeXt `csl-refs` and `csl-hanging-indent`. The writer guesses
    them from a walk of the AST and holds the output in memory (text,
    not a `Doc`). If a guess proves wrong, the output is discarded and
    the body is built whole, as before: math in an image's alt text,
    for one, is not math the ms writer writes.
  - Any other case also builds the body whole, as before: no
    top-level `$body$`, or `body` set by `-V` or the metadata.
  - MANUAL ×10, `-s --wrap=none`, `-OC`, peak RSS from HEAD (1d71259)
    to now:
    - ms: 221 to 144 MB;
    - ConTeXt: 196 to 149 MB;
    - markdown: 255 to 140 MB;
    - plain: 194 to 140 MB.
    Each is also 0.1–0.2 s faster.
  - Output unchanged: 1d71259 against the new build on 186,960 runs,
    byte for byte (stdout, stderr and exit status); none differed.
    - Inputs: test/cases, pandoc's testsuite, tables, `MANUAL.txt`
      and test/command, Lost-Worlds and Galactic-Bounty-Hunters, and
      edge cases (an empty file, math in metadata or alt text, a
      `refs` Div, `body` in the metadata).
    - Formats: ms, context, markdown, plain, gfm and commonmark.
    - Templates: the default, at four wrap settings; nine edge-case
      templates (`$body$` first, inline, in a conditional, with a
      pipe, before a nested part, before and after blank lines, and
      around the guessed fields); `-V body=`; the user's ms and
      ConTeXt templates.
  - Both fallbacks were checked to run and to give the same output.
  - `make test` passed under `-O2` and `-OC`: 247 case tests and 23
    round trips under each.
  - `tools/bench convert build` and `pdf` were rerun, and
    docs/developer/performance.md updated from them. With `-s` on
    MANUAL, podoc now takes 18.8–23.3 MiB, at most 1.4 MiB more than
    without it. The Lost-Worlds ConTeXt build went from 12.5 to
    8.2 MiB, and the digest from 20.6 to 13.5 MiB.
- 2026-11-20: podoc is built with poc's `-trap-heap-exhausted`
  (`POCFLAGS` in the GNUmakefile), and docs/developer/memory-use-problem.md
  corrected: poc had the option all along.
  - The option is compiled into each `NEW`. A test program with a 4 MB
    heap limit (`GarbageCollectedHeap.SetHeapLimit`) gave "heap
    exhausted: NEW cannot allocate the block" for its own `NEW`, but
    "NIL pointer dereference" for a `NEW` in the installed Ropes;
    Ropes compiled from source with the option gave the message.
  - podoc with the option on MANUAL ×150 (45 MB, `-t json`, `-OC`):
    the message and exit status 11, after 6 min 15 s.
  - `make test` passed under `-O2` and `-OC` after `make clean`: 247
    case tests and 23 round trips under each.
  - Recorded for poc as Peaseblossom's "Ongoing implementation
    enhancements" 15 (2cdad0b): a program-wide form, a flag set in the program's entry
    point before any module body runs, so that `Allocate` itself traps
    and libraries built without the option are covered too. Superseded
    the same day by the decided form (see the entry after decision 24).
- 2026-11-20: Decision 24, `PODOC_HEAP_LIMIT`, done (podoc.Mod's
  `SetHeapLimit`), and documented in docs/user/podoc.md ("Memory",
  exit statuses).
  - MANUAL ×150 (45 MB), which stops at the default limit after
    6 minutes, finishes with `PODOC_HEAP_LIMIT=3072`: `-t json` in
    9.6 s (1.6 GB) under `-OC` and `-O2`, `-t ms` in 14.4–14.7 s
    (1.9–2.0 GB). pandoc: 34 s, 2.9 GiB (json); 46 s, 4.6 GiB (ms).
    With 4 GB, html, context and markdown took 14–18 s at 2.0 GB.
  - Checked under both models: `abc`, `12x`, `0`, `-5` and ` 64` end
    podoc with status 6 and a message; a 26-digit number is taken as
    the most; empty, unset and `1024` give the same output.
  - With 30–60 MB on MANUAL ×10, podoc stops with "heap exhausted" or,
    when a library's `NEW` fails, "NIL pointer dereference"
    (Peaseblossom's enhancement 15).
  - `make test` passed under `-O2` and `-OC`: 247 case tests and 23
    round trips under each.
- 2026-11-20: Peaseblossom's "Ongoing implementation enhancements" 15
  decided with the user (65c753c, pushed; settled in 245b86e),
  replacing the flag of 2cdad0b. Not yet implemented in poc; nothing
  changes in podoc until a poc release has it.
  - `GarbageCollectedHeap.Allocate` will trap 11 itself in every
    program when it finds no memory, so a `NEW` in Ropes, pounicode or
    ArgParser traps too, instead of leaving NIL.
  - `AddOutOfMemoryHook` and `RemoveOutOfMemoryHook` keep a list of
    hooks, called newest first before the trap; one answering TRUE has
    `Allocate` collect and retry. Hooks must not allocate.
  - The trap message will carry the failing `NEW`'s address, for
    `addr2line`; under `-g`, a breakpoint on the trap procedure gives
    the backtrace.
  - `-trap-heap-exhausted` goes away; poc will reject it. podoc then
    drops it from the GNUmakefile's `POCFLAGS` (and AGENTS.md's note)
    and adds a hook that writes "podoc: out of memory; set
    PODOC_HEAP_LIMIT (megabytes) higher" and exits 11, in one change.
- 2026-11-21: Phase 21 done (decision 23): images in ms output.
  - `PdImages` (new): the document's local images collected, copied
    for `--extract-media=DIR` (a new option, pandoc's), converted to
    PDF for ms and pointed at the copies and PDFs. `PdSha1` (new) for
    the names pandoc gives by SHA-1; `PdMime.Canonical`, from
    `data/mime-canonical.txt` (`tools/mkmimecanon`, from pandoc's
    MIME table and mime-types 0.1.2.2's), for their extensions.
    `PdPdf` uses `PdImages` and now converts every image groff cannot
    show for `pdfroff` and `groff`.
  - The converter chain is `rsvg-convert` (PDF 1.4 for groff), then
    `img2pdf`, then `magick` or `convert`; `gm` was dropped (decision
    23, changed, and confirmed by the user the same day). magick is given 96 dpi
    when `identify` reports no resolution: a 100x75 PNG gives a
    75x56.25 pt page, as with img2pdf.
  - Checked against pandoc 3.10: `--extract-media=media` with `-t
    json`, `html` and `markdown` gives pandoc's files and output (on a
    document with images in a subdirectory, a `../` path named by its
    SHA-1, a missing image, an SVG used twice and a PDF), apart from
    URLs, which pandoc fetches and podoc leaves (differences.md); for
    `-t ms`, only the `.PDFPIC` lines and the PDFs beside the copies
    differ.
  - PDFs from test/images's document with `--pdf-engine=groff` and
    `pdfroff` (groff 1.23.0) hold all four bitmaps (`pdfimages
    -list`), and the SVG; `-o out/doc.ms` then `groff -ms -Tpdf -U`
    in `out/` works too, apart from the `.pdf` image, whose path
    pandoc writes relative to the working directory. A width in
    percent gives `0p`, as pandoc writes, and groff skips the image
    (podoc.md).
  - `tools/runimages` (new, in `make test`): `--extract-media` with
    json, html and ms, ms to standard output and to a file, with a
    PATH holding no converters; and a conversion test, skipped
    without them.
  - `make test` passed under `-O2` and `-OC`: the unit tests with
    `PdSha1Test`, 247 case tests, 23 round trips and 6 image tests
    under each.
  - Still to check: which converters the BSDs' packages provide.
- 2026-11-21: Phase 19.1 done: the rST reader's blocks.
  - `PdRst` (new) reads `-f rst` (and `.rst` inputs with no `-f`):
    sections with their adornment levels and `auto_identifiers`
    (`-f rst-auto_identifiers` too), paragraphs, transitions,
    comments, literal blocks (`::` in its three forms, quoted, and
    indented), block quotes, bullet, enumerated (every style, `#`) and
    definition lists, field lists, option lists, line blocks, and
    `rst+lhs` (`literate_haskell`). Doctest blocks, attributions and
    classifiers stay text, as in pandoc. `PdRstInline` (new) holds the
    inline parser, which 19.2 completes.
  - Brought forward from 19.2: reference targets (named, anonymous,
    chained, multi-line names), internal targets before headers and
    other blocks, footnotes (`[1]`, `[#]`, `[*]`, `[#name]`), citations
    and their `citations` Div, and the pass after parsing that
    resolves them, with pandoc's "Reference not found" and "Circular
    reference" warnings at its position.
  - `PdOptions`: `rst` takes `auto_identifiers`, `literate_haskell`
    and `lhs`; any other extension (`+smart` too) ends podoc with 23.
    `opt-from-rst` became `opt-from-latex`.
  - `tools/runcases` reads `test/cases/*.rst`; ten rST cases (JSON
    from pandoc 3.10, warnings with podoc's prefix) are byte for byte
    pandoc's under both models.
  - `make test` passed under `-O2` and `-OC`: 257 case tests, 23
    round trips and 6 image tests under each.
  - Not yet: substitutions, roles and the rest of 19.2, directives
    (19.3), tables (19.4), `-s` (19.5); rST's `smart`,
    `ascii_identifiers`, `east_asian_line_breaks` and
    `gfm_auto_identifiers` extensions.
- 2026-11-21: Phase 19.2 done: rST roles, substitutions and the
  directive framework.
  - `PdRst`: directives are read as pandoc's `directive'` does (the
    label, the top lines, the field list, the body). `role` (with a
    base role and `format`, `language`, `class`), `default-role`,
    `highlight`, `replace`, `unicode`, `date` (a strftime subset, in
    UTC, from `SOURCE_DATE_EPOCH` or the clock; poDateTime is not
    used), `image` (`:alt:`, `:class:`, `:align:`, `:target:`) and
    `raw` are done; any other directive is, for now, a `Div` with its
    name as a class, as pandoc gives an unknown one.
  - Substitution definitions (`.. |name| directive::`), with image
    substitutions taking the name as `alt`, and their resolution
    after parsing: a paragraph that is only a substitution becomes its
    block (or a `Div` of its blocks), and an inline one becomes its
    inlines or a `Span`; a missing one warns "Reference not found",
    as pandoc does.
  - New cases `rst-roles` and `rst-directives` (JSON from pandoc
    3.10). `$T/r/d3.rst` (dates, every format letter) matched pandoc
    at five `SOURCE_DATE_EPOCH` values, including leap days, under
    both models.
  - `make test` passed under `-O2` and `-OC`: 259 case tests, 23
    round trips and the image tests under each.
  - Not yet: image `:width:`, `:height:` and `:scale:` and the other
    directives (19.3).
- 2026-11-21: Phase 19.3 done: every directive pandoc's rST reader
  handles.
  - `PdRst`: `image` with `:width:`, `:height:` and `:scale:` (pixels
    rounded as Haskell's `round`, other units with pandoc's
    `showFl`); `figure` (caption and legend); `container`, `compound`,
    `pull-quote`, `epigraph`, `highlights`, `rubric`, the admonitions
    and `admonition`, `sidebar`, `topic`, `code`/`code-block`/
    `sourcecode` (`:number-lines:`), `aafig`, `math` (an `aligned`
    environment for several lines), `bibliography`, `class` (on its
    body, or on the next block, merged into a lone header's
    attribute), `line-block`; any other directive is a `Div` with its
    name as a class and its fields as attributes.
  - `include`: relative to the including file's directory, as pandoc
    names nested files; `start-line`, `end-line` (negative from the
    end), `start-after`, `end-before`, `literal` and `code` (a
    `CodeBlock`, with pandoc's untrimmed attributes); parsed in the
    includer's state; a missing file warns "Could not load include
    file" and gives nothing; a loop ends podoc with "Include file loop
    at ..." and status 64, at pandoc's position. `raw` with `:file:`
    reads the file, or gives nothing if it is missing.
  - New cases `rst-directives2`, `rst-images`, `rst-figures`,
    `rst-include` (its files in `test/cases/rst-include`),
    `rst-include-loop` and `rst-raw-file`, with JSON from pandoc 3.10;
    each matched pandoc, with its warnings and status.
  - `make test` passed under `-O2` and `-OC`: 265 case tests, 23
    round trips and the 6 image tests under each.
  - Not yet: tables and the table directives (19.4). Not checked:
    `raw` with both `:file:` and an indented body.
- 2026-11-21: Phase 19.4 done: tables.
  - `PdRst`: grid tables through `PdGridTable` (`G.Trace` on the
    shared buffer; fractional widths from `--columns`, which
    `podoc` passes as `PdRst.columns`); simple tables (column
    boundaries from the `=` borders, continuation lines, spans marked
    by `-` underlines, several header rows, headless tables); the
    `table` directive (title caption; `:widths:` `auto`, `grid` or
    numbers divided by `columns` less the column count),
    `list-table` (`:header-rows:`, only the first row a header, as
    pandoc; `:widths:` normalised) and `csv-table` (inline,
    `:file:`/`:url:` relative to the working directory, `:delim:`,
    `:quote:`, `:escape:`, `:keepspace:`, `:header:`,
    `:header-rows:`, `:widths:`), parsing CSV as pandoc's
    `Text.Pandoc.CSV`, with its parse errors (status 64) and "File
    ... not found in resource path" (status 99). `:stub-columns:` is
    ignored, as in pandoc. `EmptyCell` and `PlaceRows` moved from
    `PdMarkdown` to `PdShared`.
  - Fixed: section titles register their reference keys (`` `Title`_
    `` links to the header's identifier), missed in 19.1; a lone `\`
    cell gives no `Plain`.
  - New cases `rst-grid-tables`, `rst-simple-tables`,
    `rst-table-directives` (with `test/cases/rst-tables/data.csv`),
    `rst-csv-error` and `rst-csv-missing`, with JSON, messages and
    statuses from pandoc 3.10; each matched pandoc.
  - The corpus files `minimal-opend6-srd.rst` and
    `return-005-merchant.rst` give pandoc's JSON byte for byte, under
    `-O2` and `-OC`.
  - `make test` passed under `-O2` and `-OC`: 270 case tests, 23
    round trips and the 6 image tests under each.
  - Differences: `csv-table`'s single-character options are ASCII
    only, `:url:` is a local file, and some CSV error messages differ
    (docs/user/differences.md).
- 2026-11-21: Phase 19.5 done: standalone rST, reporting, the corpus.
  Phase 19 is finished.
  - `PdRst`, under `-s` (`PdRst.standalone`): pandoc's
    `titleTransform` (a lone top section to `title`, a lone
    subsection under it to `subtitle`, the rest promoted) and the
    first field list as metadata (`author` and `authors` split on
    `;` or `,` as pandoc does, `authors` winning; the first of a
    repeated key wins; one paragraph is `MetaInlines`, anything else
    `MetaBlocks`). Checked against pandoc on five small files.
  - Reporting (decision 22): `--verbose` (`PdIO.verbose`,
    `PdIO.Info`) prints pandoc's `[INFO] Skipped ...` lines for
    unknown directives, substitution definitions with an unknown
    directive, table directives with no table, and the role options
    pandoc skips (`:format:`/`:language:` with the wrong parent,
    unknown options, options after the first). The name
    `--unknown=warn|error` was kept: it reports these, and unknown
    roles, at their start, as warnings or as a parse error (status
    64) at the first; a bad value gives status 6. Positions are
    found through origins recorded for each nested parse
    (`PdRstInline.SetOrigin`): exact in directive bodies and
    included files, the enclosing block's start elsewhere.
  - New cases `rst-standalone`, `rst-standalone-authors`,
    `rst-verbose`, `rst-unknown-warn` and `rst-unknown-error`; JSON
    and `[INFO]` lines are pandoc 3.10's.
  - The corpus: all 73 `.rst` files under Red-Planet-Blue-Helmets,
    Alusia's 005-merchant `rst-version` and Mini-Six's SRD give
    pandoc's JSON and messages byte for byte, with and without `-s`,
    under `-OC`; the six largest also under `-O2`.
  - Builds, with the projects' own options (`-s`, `general.lua`,
    `--template=statement` or `tkb`): the ms for
    `minimal-opend6-srd.rst`, `red-planet-blue-helmets.rst` and
    `return-005-merchant.rst` is byte-identical to pandoc's, and so is
    the ConTeXt; their groff PDFs (81, 12 and 26 pages) have the same
    text but for the names of the temporary image directories, which
    groff prints for EPS images it cannot place. The HTML is the
    same with `--wrap=none` (podoc does not wrap HTML).
  - `make test` passed under `-O2` and `-OC` on atla (275 case
    tests, 23 round trips, 6 image tests) and on alerik (FreeBSD
    15.1) and artos (NetBSD 11.0), amd64, where the conversion image
    test is skipped for want of converters. terhali and erekose
    were not reachable.
  - Differences listed in docs/user/differences.md: `--unknown`,
    `--verbose` reporting what pandoc loses in list items,
    substitution definitions and notes, the positions in nested text,
    and an anonymous reference with no target (a warning; pandoc
    fails with status 64). docs/user/podoc.md documents `-f rst`,
    `--verbose` and `--unknown`, and the translation advice is gone.
- 2026-11-21: Phase 20 done: the `%` title block.
  - `PdMarkdown.TitleBlock` reads the block at the very start of the
    input: the title, the authors (split on a top-level `;` and the
    white space after it, or on a line end, empty ones kept as pandoc
    keeps them) and the date, with continuation lines; a YAML block
    wins over it. `-f markdown-pandoc_title_block` turns it off
    (`PdOptions`; `gutenberg` names it as well as `grid_tables`).
  - Checked against pandoc 3.10 on 27 inputs (empty lines, `%` alone,
    `A;;B;`, continuations, markup, YAML, the extension off and on
    and off together), JSON byte for byte under `-O2` and `-OC`;
    `testsuite.txt`'s metadata is now pandoc's, and only its raw TeX
    block differs.
  - The HTML writer's `dcterms.date` had missed every date in
    October, November and December (the month table was misaligned)
    and dates with smart typing's no-break space (`Dec. 3, 2026`):
    both fixed in `PdHtml`, and checked against pandoc on ten date
    forms.
  - New cases `title-block`, `title-block-empty`, `title-block-yaml`,
    `title-block-off`, `title-block-standalone` (`-s` with the html,
    ms, context, markdown and plain writers) and `html-date-abbrev`,
    pandoc's output.
  - `make test` passed under `-O2` and `-OC` on atla (285 case tests,
    23 round trips, 6 image tests). `make compare`: 1462 of 1672 the
    same; the 210 that differ are those of 2026-11-21's earlier
    entry. Not run on the BSDs: the change is portable Oberon only.
  - docs/user/podoc.md and differences.md no longer list the title
    block as unread, and name `pandoc_title_block`.
- 2026-11-21: Decision 25: hyperlink references and substitutions in
  rST footnotes are resolved, where pandoc leaves its placeholders.
  - `PdRst.Resolve` walks each footnote's text after the rest of the
    document, so the main text, with its anonymous references, stays
    pandoc's; a footnote reference inside a footnote is left as pandoc
    leaves it.
  - New case `rst-note-links` (podoc's output, differing from
    pandoc's only in the three resolved references);
    `rst-references2.json` now has the note's link resolved.
  - The user's 73 rST files still give pandoc's JSON byte for byte
    (`-OC`). `make test` passed under `-O2` and `-OC` on atla (286
    case tests, 23 round trips, 6 image tests). Recorded in
    docs/user/differences.md.
- 2026-11-21: Three approximations in the rST reader replaced by
  pandoc's rules (the user's request; no decision needed, since each
  now matches pandoc).
  - Option lists: `PdRst.IsAlnumAt` is Haskell's `isAlphaNum` (it took
    every non-ASCII byte as a letter), `optArg` starts with `isAlpha`,
    and the option parser steps by character, not byte, so `-日` is an
    option and `-→` is not.
  - The "Reference not found" warning prints the name as pandoc's
    `tshow` does (`'"caf\233"'`), with `PdRst.CatShow`.
  - The `date` directive's format and the image and figure `:width:`
    and `:height:` drop Haskell's `isSpace` characters (U+00A0,
    U+3000 and the rest; not U+2028), with `PdRst.SpaceLen` and
    `StripBuf`.
  - Checked against pandoc 3.10 under `-O2` and `-OC`: eleven option
    lists, five substitution names, four date formats and five
    widths and heights. New cases `rst-unicode` and `rst-subst-show`
    (pandoc's output and warning). The user's 73 rST files still give
    pandoc's JSON byte for byte (`-OC`). `make test` passed under
    `-O2` and `-OC` on atla (288 case tests, 23 round trips, 6 image
    tests).
- 2026-11-21: The user confirmed decision 23's change: `gm` stays out
  of the image converter chain (`img2pdf`, then `magick` or
  `convert`), since gropdf cannot read GraphicsMagick 1.3.45's PDFs.
  The code already did without it; only PLAN.md changed.
- 2026-11-21: All six BSD VMs on atla (FreeBSD 15.1 amd64 and arm64,
  NetBSD 11.0 amd64 and i386, OpenBSD 7.9 amd64 and i386) built
  5e2f6e4 and passed `make test` under `-O2` and `-OC`: 288 case
  tests, 23 round trips, the image tests (conversions skipped where
  no converter is installed). First runs on arm64 (rackhir) and
  OpenBSD amd64 (jherek).
- 2026-11-21: reStructuredText in the performance tests (the user's
  request). `tools/bench rst` times pandoc's `rst-reader.rst` and
  `tables.rst`, the Mini Six SRD, the SRD ×10, the merchant scenario
  and five generated stress inputs of 12,000 items; results in
  docs/developer/performance.md, "reStructuredText".
  - Found and fixed: anonymous references, substitutions, footnotes
    and citations were quadratic in PdRst and PdRstInline, and
    repeated section titles cubic (12,000 took 397.73 s). Now a heap
    for the anonymous keys, hash tables, citations merge-sorted once,
    and identifier suffixes resumed from the last tried. The markdown
    reader's suffixes are resumed too (cleared when `TableAt` takes
    identifiers out). Both readers stop at `-60000` as pandoc's
    `uniqueIdent` does. Every hash table has 4,093 buckets, a prime,
    since `Ropes.Hash` modulo 4,096 left most buckets empty.
  - A bug fixed: past 9,999 anonymous targets, the keys (`_` and the
    count modulo 10,000) collided; they are pandoc's `_%04d` now.
  - podoc is 3.2–28× faster than pandoc on every rST input, in 3–26×
    less memory; the stress inputs are 4.8–17× faster.
  - Checked: the stress inputs, a duplicate-citation and repeated-title
    case and 60,005 identical titles (rST and markdown) give pandoc's
    JSON under `-O2` and `-OC`; the user's 73 rST files give pandoc's
    JSON and messages byte for byte, with and without `-s`, under both
    models (292 runs); `make test` passed under `-O2` and `-OC` on
    atla (288 case tests, 23 round trips, 6 image tests).
  - The six BSD VMs then built 3a97233 and passed `make test` under
    `-O2` and `-OC`, as at 5e2f6e4 (288 case tests, 23 round trips,
    5 image tests; the conversion test skipped, with no converters
    installed).
- 2026-11-21: Phase 22 done (decision 26): EPS and PostScript images
  converted to PDF with Ghostscript for PDF made with `groff`.
  - Checked on atla: the 005-merchant scenario's statement PDF, built
    from its directory with its Makefile's arguments and
    `--pdf-engine=groff`, under groff 1.25.0 and 1.23.0 and podoc
    `-O2` and `-OC`: 26 pages of 5.5×8.5 in, both figures in it, on
    pages 8 and 26 at the resolution of the `pdfroff` PDF (115 and
    200 ppi), the lizardman figure matching it by eye; 452 KB with
    1.25.0 (whose gropdf subsets fonts), 4.3 MB with 1.23.0. Before
    the change neither figure was in it.
  - By hand: `pdfroff` still shows the EPS through `.PSPIC`; with no
    `gs` on the PATH, podoc warns ("check that gs is in path") and
    the PDF is made without the image.
  - `make test` passed under `-O2` and `-OC` (288 case tests, 23
    round trips, 7 image tests with the new `pdf-eps`).
  - The six BSD VMs then built b2a0751 and passed `make test` under
    `-O2` and `-OC` (288 case tests, 23 round trips, 5 image tests;
    `convert` and `pdf-eps` skipped: no converters, and no
    `pdftotext` on any of them).
- 2026-11-21: Research on a mom writer and PDF through `pdfmom`,
  recorded in `docs/research/pdfmom-backend.md`; Phase 23 proposed,
  waiting on the user's answers to its §9. Checked on atla: a small
  mom document (title, `NAMED` heading, footnote, `PDF_LINK`, list,
  tbl table, `.TOC`) builds with `pdfmom -t` under groff 1.23.0 and
  1.25.0, with an outline and links in both; `.AUTO_RELOCATE_TOC TOP`
  moves the contents to page 1 only when it comes before `.START`.
- 2026-11-21: The user answered the research's questions: decision
  27 schedules Phase 23 [planned], with the 005-merchant scenario's
  statement-sized PDF as its acceptance target. Nothing implemented
  yet.
- 2026-11-21: Phase 23.1 done: `PdRoff` holds what the roff writers
  share, moved from `PdMs`: the escapes (`EscapeStr`, `ToSmallCaps`,
  `ToAscii`, `EscapePDFString`, `EscapeUri`), the font state
  (`Fonts`, `Toggle`, `FontChange`), the plain text for bookmarks,
  `Points`, `Roman`, `Extension`, `Height`, and the tbl table's parts
  (`TableParts`, with the writer's `Blocks` for the cells). Wrapping
  stays in `PdLayout`, which both writers use. `make test` passed
  under `-O2` and `-OC` (288 case tests, 23 round trips, 7 image
  tests), every ms case byte for byte; the 005-merchant scenario's
  `-s -t ms --toc` output is the same as the installed podoc's.
- 2026-11-21: Phase 23.2 done. `PdMom`, the mom writer, with `-t mom`
  (and `.mom` for `-o`) and `--reference-location`. What was tried in
  groff 1.23 first, and what came of it:
  - definition lists: mom's paragraph indent is saved in `pd:pi`, set
    to 0, and the definitions indented with `.IL 2m`;
  - a rule is `.DRH` then `.SP 1v`, since mom draws it at the next
    line's baseline;
  - block quotes do not nest in mom (the inner one's text is lost), so
    a quote directly in a quote ends the outer one and the outer one
    resumes after it; one further in is written as its blocks;
  - groff 1.23's tbl restores the hyphenation margin and space in ems
    that it saved in basic units, so mom's values grow with each table
    until the second gives "numeric overflow" (fixed in 1.24); the
    writer saves and restores them around each table;
  - `.ENDNOTES` then `.TOC` needs `.if \n[.vpt]=0 .vpt` between them on
    1.23 (for the template, 23.4);
  - subscripts are `\v'.3m'\s[-2]`...: mom 2.5_d has no SUB, and
    `\s-22` is size −22.
  `make test` passed under `-O2` and `-OC` (298 case tests, 10 of them
  `.mom`: the general blocks, edges, inlines, links, lists, tables and
  grid tables cases, and `mom-features` and `mom-endnotes`); each
  `.mom` file checked with `groff -mom -t -z` gives only missing-glyph
  and "cannot adjust line" warnings in narrow table cells, as ms
  does. `mom-features` with footnotes and with endnotes, and the
  merchant scenario on statement paper with a contents page, were made
  into PDFs with `pdfmom` and looked at.
- 2026-11-21: Phase 23.3 done. Tables are `.TS H` with `.TH` after
  the header rows when there is a header, and `CAPTION "..."` in place
  of the caption paragraph. Images are `.PDF_IMAGE`: a figure of one
  image `-C` with `CAPTION` and `TARGET`, an image in text `-L`; the
  size from `width`/`height` (a percentage width is
  `\n[.l]/100*N/100`) or else from `pdfinfo`'s page size
  (`PdImages.PageSize`), scaled to the line length when wider; a depth
  from a width is `W/1000*R`, as `W*h/w` overflows groff's
  arithmetic. Not-PDF images and images of unknown size are left out
  with a warning; the figure keeps its caption, the inline image its
  description. EPS and PostScript are converted for mom as for ms
  (`PdImages.ConvertPostScript`). Filters: `box` is `.BOX OUTLINED
  black INSET 4p` and `keep` is `.FLOAT FORCE` for mom, and the
  general filter's span escapes (small caps, colour and the rest) are
  written for mom as for ms: my extension, as mom takes roff escapes
  (the `.color` note stays ms's). Tried in groff 1.23: captions go
  below images only with `.CAPTION_AFTER_LABEL IMG` (for the template,
  23.4); a table that ends exactly at a page's foot leaves a stray
  header on the next page, in 1.23, 1.24 and 1.25 alike, so mom's
  doing; a caption is set no wider than its table. As for ms, a
  converted image's path is relative to the output's directory and an
  unconverted PDF's to the working directory, which differ when `-o`
  is elsewhere. `tools/runcases` now also takes `<name>.<ext>.errors`
  (links.md's image warnings are mom's alone). `make test` passed
  under `-O2` and `-OC` (300 case tests, with `mom-images` and
  `filter-general-mom` new; 9 image tests, with `mom-eps`, which
  renders its output with `pdfmom` when groff 1.23 or later is
  present). `mom-images` and `filter-general-mom`, rendered with
  `pdfmom -t` (1.23.0), gave only a "cannot break line" warning for a
  word in the narrow table's caption; figures, captions, percentage
  widths, inline images, repeated table headers, boxes and keeps were
  looked at in PDFs.
- 2026-11-21: Phase 23.4 done. `data/templates/default.mom`, podoc's
  own, is built into `PdDefaults` by `tools/mktemplates`; the example
  `data/examples/statement.mom` is installed in `$(DOCDIR)/examples`.
  Tried in groff 1.23.0 and settled in the template: `.PAPER` must
  come before `.PRINTSTYLE` (otherwise the contents page keeps letter
  width); `.AUTO_RELOCATE_TOC` with no argument relocates only when
  there are covers, so it is `TOP` without them; mom's docheader has
  no date, so `date` (`.MISC`) shows only on covers; `.COLUMNS`
  requires a gutter, so there is a new variable `column-gutter`, 1.5P
  by default; `title-meta`, the plain title, is `.PDF_TITLE`.
  `--toc-depth`: mom has no depth, so a heading below it is written
  with `HD_TO_TOC` redefined, for that heading only, to pop the
  environment `HEADING` pushed. An unnumbered heading under `-N` is
  written between `.rr #NUMBER_HEAD_n` and `.nr #NUMBER_HEAD_n 1`.
  Both use mom's internals. New case tests `mom-standalone` (title
  block, authors, abstract, `--toc`, `--toc-depth`, `-N` with an
  unnumbered heading, `columns`, `linkcolor`, `papersize`,
  `printstyle`) and `mom-covers` (`covers`, `doctype`, `toc-title`);
  both, and `mom-standalone` with `statement.mom`, rendered with
  `pdfmom -t` without warnings and looked at. The merchant scenario
  (a copy, its `for-format ms` containers given `mom` too), with
  `--lua-filter=general.lua`, `statement.mom`, `--toc` and
  `-V fontfamily=Optima`: 26 pages, contents first, images once, no
  groff warnings. `make test` passed under `-O2` and `-OC`.
- 2026-11-21: Phase 23.5 done. `--pdf-engine=pdfmom` (by base name;
  `PdOptions.PdfWriterAndEngine` pairs it with mom, and it is mom's
  default); `PdPdf.Mom` runs `pdfmom -t -k -KUTF-8` (`-e` when the
  source has `.EQ`) with `--pdf-engine-opt` on `input.mom` in the
  temporary directory, by its path, as pdfmom reads its input more
  than once. Images are converted as for groff, so the image path
  problem of 23.3 does not arise for PDF. Checked: 47 for a missing
  pdfmom, 43 when pdfmom fails (groff 1.25.0); pdfmom 1.23.0 exits 0
  when mom aborts, so podoc writes the PDF it made (recorded in
  differences.md). Tests: `PdOptionsTest` (five pairings),
  `pdf-engine-missing-mom`, `opt-engine-bad` with pdfmom, and
  `tools/runimages`' `mom-pdf` (contents first, two pages, an outline,
  the EPS's text, no files left beside the document; skipped without
  pdfmom of groff 1.23 or later, gs, pdfinfo or pdftotext).
  Acceptance: the merchant scenario (a copy, with `for-format ms mom`
  figures and a `raw:: mom` `.NEWPAGE` before the map), `-s -t mom
  --lua-filter=general.lua --template=statement.mom --toc -V
  fontfamily=Optima --pdf-engine-opt=-F<1.23.0's site-font>`: groff
  1.23.0, 26 pages, 1.25.0, 28 pages; statement pages, the contents
  first, both figures, the map on its own page, no groff warnings
  (1.25.0's site-font directory is empty here, so 1.23.0's was used).
  `mom-standalone` made into PDF under both. `make test` passed under
  `-O2` and `-OC` (303 case tests, 10 image tests).
- 2026-11-21: Phase 23.6 done, and with it Phase 23. docs/user/podoc.md
  has a "mom" section (the writer, `pdfmom`, the template's variables,
  how to write a mom template, `statement.mom`), and mom in its
  needs, options, templates, filters and PDF output; README.md and
  AGENTS.md name the mom writer and pdfmom. `make test` passed under
  `-O2` and `-OC` on alerik and rackhir (FreeBSD 15.1, amd64 and
  arm64), artos and yishana (NetBSD 11.0, amd64 and i386), jherek and
  cymoril (OpenBSD 7.9, amd64 and i386): 303 case tests, 23 round
  trips, 5 image tests; `mom-eps` and `mom-pdf` skipped on all (only
  yishana has groff 1.23 or later, 1.24.1 with pdfmom and gs, but no
  pdfinfo or pdftotext).
- 2026-11-22: Research on a LaTeX writer and PDF through TeX, in
  docs/research/latex-backend.md. Its findings:
  - pandoc 3.10's LaTeX writer is the oracle; it is 2,594 lines of
    Haskell.
  - The user's only pandoc LaTeX build, Breachworld `003-Arena`
    (xelatex, eisvogel), fails on atla for a missing
    `footnotebackref.sty`, in pandoc too.
  - Timings for the merchant scenario with `--toc`:
    - xelatex 3.2 s, lualatex 5.4 s, four runs each;
    - pdflatex stops on ♂;
    - podoc's ms takes 1.4 s.
  - None of the six BSD VMs has a TeX engine.

  The user decided the same day not to add a LaTeX backend
  (decision 28). The plan proposed for it, first written here as
  Phase 24, was moved to the research's §10, renumbered L1. No code.
- 2026-11-22: Research on syntax highlighting for ms, mom and
  ConTeXt, in docs/research/syntax-highlighting-big.md. Its findings:
  - The user's built documents have no code with a skylighting
    language.
  - pandoc 3.10's default ms output drops highlighted code (the
    token macros are never defined), and its default ConTeXt output
    stops `context` with an undefined control sequence. Both are 3.8
    regressions, reportedly fixed in 3.11 (#11829, unchecked).
  - Porting skylighting means a KDE regex engine, the tokenizer and
    164 syntax files, about 4,000 lines of Oberon plus megabytes of
    data, and 84 of the syntax files are GPL or LGPL.

  The user decided the same day that this port is too big and will
  not be done (decision 29). No code.
- 2026-11-22: Research on small syntax highlighting, written from
  scratch, in docs/research/syntax-highlighting-small.md: reserved words
  in bold, in a mono or a proportional style, for ms, mom and ConTeXt;
  sh, bash, Oberon-2, Modula-2, Ada, Pascal (FreePascal's modes), C and
  C++; user lists of reserved words. Its findings:
  - Both styles were rendered by hand in each writer. Problems found:
    mom's `.QUOTE` is italic, and ConTeXt's default mono bold is too
    light to see.
  - The reserved-word lists were checked against poc, gm2, GNAT, gcc,
    g++, bash and FreePascal's `tokens.pas`.
  - Estimated at 1,500 to 2,300 lines, mostly one new module.
  - A bug found on the way: under groff 1.25.0, ms code blocks are set
    in Times-Roman, because `\f[C]` is no longer a font. pandoc 3.14
    writes the same.
  - pandoc 3.14 no longer has the 3.10 highlighting regressions.

  Questions Q1 to Q8 are open for the user. No code.
- 2026-11-22: Research on vgrind's highlighting, in
  docs/research/vgrind.md. vgrind 5.7 (the 4.4BSD sources, from the
  user's stored Debian package) was built and run on Oberon and C
  samples and rendered with groff 1.25.0. Its findings:
  - It sets code in roman, reserved words in bold and comments in
    italic, and puts tabs at absolute positions (`\h'|Nn'`) so that
    columns align in a proportional font.
  - Its languages are a 1980s termcap-style database, with no Ada or
    Oberon and dated, partly wrong entries.
  - It cannot be used from podoc: it has its own page layout, its
    filter mode does not work with ms, and it has no ConTeXt form.
  - NetBSD 11.0 ships it; FreeBSD 15.1 and OpenBSD 7.9 do not.

  It supports the small design's proportional style, and suggests
  absolute positions for runs of spaces. Questions V1 to V3 are open.
  No code.
- 2026-11-22: The user decided vgrind.md's V1 (comments in italic in
  the proportional style, decision 30) and V3 (reserved-word lists in
  podoc's own format only, decision 31). For V2, the alignment
  experiment is in vgrind.md §8: a throwaway awk script wrote ms, mom
  and ConTeXt for an Oberon and a C sample, in four forms (mono,
  fixed, elastic, hybrid), rendered with groff 1.25.0 (`-ms`,
  `pdfmom`) and ConTeXt LMTX and looked at. All forms worked in all
  three formats; ConTeXt needs three macros. Recommended: hybrid,
  0.5 em per column, 1 em gap (question V4, open). No podoc code.
- 2026-11-22: The user decided V4's part 2 (decision 32): 0.5 em per
  column and a 1 em gap by default, both changeable. V4's part 1, the
  form of alignment, is open.
- 2026-11-22: Decision 32 extended: the widths are template variables,
  `code-column` and `code-gap`, in ems, and the writer writes column
  numbers. V4's part 1 remains open.
- 2026-11-22: Decision 33: `--code-align=none|fixed|elastic|hybrid`
  or `code-align` in the metadata, default `hybrid`. V4 is settled;
  vgrind.md's questions are all answered. No podoc code.
- 2026-11-22: Decision 34: `.QUOTE_INDENT`, from the new mom
  template variable `code-indent` (0 by default), in `default.mom` and
  `statement.mom`; `src/PdDefaults.Mod` regenerated with
  tools/mktemplates; expected `mom-covers.mom` and `mom-standalone.mom`
  updated (two lines each). Checked: code at the margin by default and
  at 2m with `-V code-indent=2m`, through `--pdf-engine=pdfmom`, and
  with statement.mom; `make test` passes under -O2 and -OC.
- 2026-11-22: Phase 24 planned at the user's request: the small
  syntax highlighting with vgrind's lessons, recorded as
  docs/research/syntax-highlighting-small.md §12 (three steps: scan,
  lay out, write; templates unchanged unless used) and as Phases 24.1
  to 24.8 above. Three new questions, Q9 to Q11, join Q1 to Q8; all
  are open. No code.
- 2026-11-22: Decisions 35 to 37, on the small highlighting study's
  Q1 (in part: `--code-style` and `code-style`), Q6 (`\f[CR]` for ms
  code) and Q7 (mom's `.QUOTE_FONT R`). No code.
- 2026-11-22: Decision 35 completed (default `none`, a class overrides
  it per block) and decisions 38 to 44, on the small highlighting
  study's Q2, Q4, Q5 (in part), Q8, Q9, Q10 and Q11. Open: Q3, plain
  `pascal`'s mode, replace or add for users' lists, the Oberon class
  names. No code.
- 2026-11-22: Decision 45 (Q3: reserved words only), and the open
  points of 39 to 41 settled: plain `pascal` is `fpc`; users' lists
  add, or replace with `#!replace`, and `-word` removes; the Oberon
  classes. All of the study's questions are decided. No code.
- 2026-11-22: Decision 46, HTML output for the small highlighting,
  scheduled as Phase 24.5; the later subphases renumbered 24.6 to
  24.9. No code.
- 2026-11-22: Phase 24.1 done: `PdCode`, the scanner, with the Oberon
  family, Modula-2 and C. `make test` passes under `-O2` and `-OC`
  (the unit tests with `PdCodeTest`'s 49 cases, 303 case tests, 23
  round trips, 10 image tests).
- 2026-11-22: Phase 24.2 done: ms code blocks in `\f[CR]`. `make
  test` passes under `-O2` and `-OC` (303 case tests, 23 round trips,
  10 image tests, the unit tests). A `make -j4 test` failed once in
  clang (an assertion in its `.ll` lexer, building PdLayoutTest under
  `-O2`) and passed when run again without `-j`: the unit tests share
  `build/<model>/test/` and its module files, so parallel builds may
  race. Not yet looked into.
- 2026-11-22: Phase 24.3 done: `--code-style` and `code-style`, ms,
  mom and ConTeXt in the mono and proportional styles, and
  `default.context`'s monospaced bold and italic under
  `$if(code-highlight)$`. `make test` passes under `-O2` and `-OC`
  (318 case tests, 15 of them new, the round trips, the image tests,
  the unit tests). ConTeXt's `'` as ’ in the proportional style is
  left for 24.4.
- 2026-11-22: Phase 24.4 done: `PdCodeAlign`, `--code-align` and
  `code-align`, aligned proportional code in ms, mom and ConTeXt
  (fixed, elastic, hybrid), and `code-column` and `code-gap` in the
  templates. `make test` passes under `-O2` and `-OC` (337 case
  tests, 19 of them new, 23 round trips, 10 image tests, the unit
  tests with `PdCodeAlignTest`'s 23 cases). The writer, not the
  template, holds ConTeXt's macros (24.4's Done says why).
- 2026-11-22: Phase 24.5 done: highlighted code in HTML, mono with
  `<b>` and `<i>`, proportional in the body font with fixed alignment
  by `min-width` inline-blocks (a change from decision 46's `left:`,
  in 24.5's Done), the CSS in `styles.html` inside
  `$if(code-proportional)$`. `make test` passes under `-O2` and
  `-OC` (345 case tests, 8 of them new, the round trips, the image
  tests, the unit tests with `PdCodeAlignTest`'s 27 cases).
- 2026-11-22: Phase 24.6 done: Pascal's six FreePascal modes, Ada and
  C++ in `PdCode`, the lists checked with fpc 3.2.3, GNAT and g++.
  `make test` passes under `-O2` and `-OC` (347 case tests, 2 of them
  new, the round trips, the image tests, the unit tests with
  `PdCodeTest`'s 106 cases).
- 2026-11-22: Phase 24.7 done: sh and bash in `PdCode`, reserved
  words only in command position, `case`, `for`, here-documents and
  substitutions. `make test` passes under `-O2` and `-OC` (347 case
  tests, the round trips, the image tests, the unit tests with
  `PdCodeTest`'s 149 cases).
