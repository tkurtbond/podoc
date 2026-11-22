# podoc and LaTeX: scope, possibilities and risks of a LaTeX writer

Research done 2026-11-22. The question is whether podoc should write
LaTeX (`-t latex`) and make PDF from it with pandoc's TeX engines
(`--pdf-engine=pdflatex|xelatex|lualatex|latexmk|tectonic`). It
covers what that would take, what it would give, and what could go
wrong. podoc makes PDF today in three ways: from ms with `groff -Tpdf`
or `pdfroff`, from ConTeXt with `context`, and from mom with `pdfmom`
(Phase 23, docs/research/pdfmom-backend.md). LaTeX would be a fourth
way, and the first of pandoc's own defaults: pandoc's `-o x.pdf` with
no `-t` uses LaTeX and pdflatex.

**Outcome:** on 2026-11-22 the user decided not to add a LaTeX
backend (PLAN.md's decision 28). The plan that was proposed is kept
in §10, numbered L1.

Sources:

- pandoc 3.10's source (`/usr/local/sw/src/lang/Haskell/pandoc/pandoc-3.10`):
  - `src/Text/Pandoc/Writers/LaTeX.hs` and `Writers/LaTeX/*.hs`;
  - `src/Text/Pandoc/PDF.hs`;
  - `data/templates/default.latex` and its partials;
  - `test/writer.latex`, `test/tables.latex`,
    `test/writers-lang-and-dir.latex` and `test/command/*.md`.
- The installed pandoc 3.10 (`~/.cabal/bin/pandoc`), run as the
  oracle.
- TeX Live 2026 as Fedora packages it (314 `texlive-*` packages,
  656 MB in `/usr/share/texlive`): pdfTeX 1.40.29, XeTeX, LuaTeX and
  latexmk. tectonic is not installed.
- podoc at 9df4fd7.
- The user's GNUmakefiles under `~/Repos/RPG` and `~/current/RPG`,
  `~/.pandoc/filters/general.lua` and
  `~/.pandoc/templates/eisvogel.latex`. These were only read.

Section 4 lists the experiments. They were run in
`/usr/local/sw/tmp/claude-podoc-latex`, which has since been removed.

## 1. Summary

- **pandoc has a LaTeX writer, so there is an oracle.** This is
  unlike mom. `pandoc -t latex` is the reference, byte for byte, as
  for ms and ConTeXt since Phase 18. pandoc's own fixtures serve as
  tests too:
  - `writer.latex`, 973 lines;
  - `tables.latex`, 149 lines;
  - `writers-lang-and-dir.latex`, 149 lines;
  - the 87 command tests that write LaTeX (11 of them beamer).

  Decision 3 applies as it is written.
- **The user's builds barely use LaTeX** (§3):
  - One pandoc build target writes LaTeX: Breachworld's
    `003-Arena`, whose `%.ltx.pdf` rule runs
    `-r rst -w latex --lua-filter=general.lua --pdf-engine=xelatex
    --template=eisvogel`. It is not a default target (`ms` and `ctx`
    are), and it fails on this machine today. eisvogel needs
    `footnotebackref.sty`, which Fedora's TeX Live does not have
    (§4).
  - The other LaTeX builds use docutils' `rst2latex` (`Campaigns/Possible`,
    `WVHTCF/4e-Harrison`). Decision 21 keeps those out of podoc.
  - `general.lua` has a `latex` branch for every span class except
    `file` and `cmd`. It has none for `box` or `keep`.
- **The writer is the biggest podoc would have.** pandoc's LaTeX
  writer is 2,594 lines of Haskell, against 812 for ms and roff and
  839 for ConTeXt (§5). Leaving out citations and beamer leaves about
  2,100. By the ratio of podoc's ConTeXt and ms writers to pandoc's,
  that is 2,500–3,000 lines of Oberon in three or four modules. The
  default template and its partials add 620 lines, but those are
  pandoc's own, embedded by `tools/mktemplates` as the others are.
- **Most of what it needs, podoc already has:**
  - the AST and both readers;
  - `PdLayout`, for wrapping at 72 columns as doclayout does;
  - `PdTemplate`, with partials, which `default.latex` uses for
    `common.latex()`, `fonts.latex()` and the rest;
  - `PdShared`, `PdImages` (`rsvg-convert` for SVG, as pandoc uses);
  - `PdRun`, `PdPdf`'s temporary directory, and the engine pairing in
    `PdOptions.PdfWriterAndEngine`, which already names pdflatex.
- **What is new** (§5, §6):
  - TeX escaping, which differs from ConTeXt's;
  - `longtable` tables with relative column widths, `\multicolumn` and
    `\multirow`;
  - figures with `\pandocbounded`;
  - babel and polyglossia names for `lang` (`Lang.hs`, a 152-line
    table; the merchant scenario sets `lang: en-US`);
  - about 47 template variables the writer sets from what the document
    holds (`tables`, `graphics`, `strikeout`, `csquotes`,
    `highlighting-macros` and others), which the template tests to
    load packages;
  - a PDF driver that reruns the engine until no "Rerun" warning is
    left, at most four times. It always runs four times when there
    is a contents (§4).
- **Code highlighting is the one part podoc cannot match.** pandoc
  highlights a code block that names a language through skylighting
  (`\begin{Shaded}` and `\DataTypeTok{...}`). podoc highlights for no
  writer and would write `verbatim`, as
  `--syntax-highlighting=none` does. That is a listed difference, as
  for HTML, ms and ConTeXt. There is a cheap alternative:
  `--syntax-highlighting=idiomatic` (pandoc's `--listings`) leaves
  highlighting to LaTeX's `listings` package. podoc could support it
  without skylighting (§9, Q4).
- **What LaTeX would give the user** (§7):
  - pandoc's default PDF route, so `podoc -o x.pdf` would work as
    `pandoc -o x.pdf` does;
  - the eisvogel build;
  - `.tex` files to hand to journals, collaborators or Overleaf;
  - math typeset by TeX itself, which no other podoc route does
    (ms has no `eqn` conversion);
  - LaTeX's packages and classes through templates.
- **The main risks** (§8):
  - TeX is large: 656 MB here. None of the six BSD VMs has any TeX
    engine. This works against podoc's purpose of building where
    pandoc cannot. `-t latex` itself needs no TeX, but PDF does.
  - LaTeX PDFs depend on which packages a TeX installation has, as
    eisvogel's failure shows.
  - The writer is the largest single piece of work since the rST
    reader.
  - Unicode under pdflatex: the merchant scenario fails with "Unicode
    character ♂ (U+2642) not set up for use with LaTeX". It needs
    xelatex or lualatex and a font that has the symbols. That is
    pandoc's behaviour too, but users will meet it.

## 2. LaTeX in pandoc 3.10

### 2.1 The writer

| Module | Lines | What it does |
|---|---:|---|
| `Writers/LaTeX.hs` | 1,511 | blocks, inlines, headings, lists, figures, links, notes, math, raw, beamer frames, the template's variables |
| `LaTeX/Table.hs` | 434 | `longtable`: column specs and widths, head, foot, captions, `\multicolumn`, `\multirow` |
| `LaTeX/Util.hs` | 287 | `stringToLaTeX` (escaping, ligatures, `--ascii`), `toLabel`, `inCmd`, wrapping helpers |
| `LaTeX/Citation.hs` | 209 | natbib and biblatex citations |
| `LaTeX/Lang.hs` | 152 | BCP 47 to babel and polyglossia names |
| `LaTeX/Types.hs` | 108 | the writer's state (34 fields) |
| `LaTeX/Caption.hs` | 58 | captions, with notes moved out of them |
| `LaTeX/Notes.hs` | 34 | notes inside minipages and table cells |

The writer's state has two kinds of field:

- **Context**, which changes the output: in a note, in a heading, in
  `\item[...]`, in a figure, in a minipage, in a caption, inside a
  soul command such as `\ul`.
- **Flags** for what the document uses: tables, graphics, SVG,
  strikeout, URLs, subfigures, multirow, csquotes, highlighting,
  verbatim in a note, `\cancel`, a ZWNJ character. Each sets a
  template variable, and the template loads the matching package
  only when the variable is set.

An identifier on a div or span becomes `\protect\phantomsection\label{id}`.
In a heading it becomes `\protect\hypertarget{id}{}` instead (#9209).
The writer collects the internal link targets into
`stInternalLinks`, but nothing reads that list in 3.10.

These writer options change the output:

- `--top-level-division=section|chapter|part`;
- `--syntax-highlighting` (`none`, `default`, `idiomatic` or a style),
  with its older forms `--no-highlight`, `--listings` and
  `--highlight-style`;
- `--number-sections`, `--toc`, `--toc-depth`;
- `--lof` and `--lot` (lists of figures and tables);
- `--table-caption-position` and `--figure-caption-position`;
- `--ascii` (`writerPreferAscii`);
- `--wrap` and `--columns`;
- `--incremental` and `--slide-level` (beamer only).

Of these, podoc has `--toc`, `--toc-depth`, `-N`, `--wrap` and
`--columns` today. ArgParser rejects the others (status 2).

### 2.2 The template

`default.latex` (148 lines) includes seven partials:
`document-metadata.latex`, `passoptions.latex`, `fonts.latex`,
`font-settings.latex`, `common.latex` (263 lines),
`after-header-includes.latex` and `hypersetup.latex`. Together that
is 620 lines. They test many variables:

- **Page and class:** `documentclass`, `classoption`, `papersize`,
  `geometry`, `margin-left` and the other margins, `fontsize`,
  `linestretch`, `indent`.
- **Fonts:** `fontfamily`, `mainfont`, `sansfont`, `monofont`,
  `mathfont`, `CJKmainfont`, `fontenc`, `microtypeoptions`.
- **Language:** `lang` (→ `babel-lang`, `polyglossia-lang`), `dir`.
- **Links:** `colorlinks`, `linkcolor`, `urlcolor`, `toccolor`,
  `citecolor`.
- **Document:** `title`, `subtitle`, `author`, `date`, `abstract`,
  `thanks`, `keywords`, `subject`, `toc-title`, `lof`, `lot`.
- **The usual three:** `header-includes`, `include-before` and
  `include-after`.

Most of the template is plain text that `PdTemplate` already
handles. pandoc's template licence (BSD-3-Clause) already covers
podoc's embedded copies (`data/templates/README`).

### 2.3 The engines

From `PDF.hs`:

- **Which engines:** `pdflatex`, `xelatex`, `lualatex`, `latexmk`
  (with `-pdf`), and `tectonic`, plus the `-dev` variants of the
  first and third.
- **How they are run:** in a temporary directory, on `input.tex`,
  with `-halt-on-error -interaction nonstopmode -output-directory
  <tmp>`. latexmk gets `-interaction=batchmode -halt-on-error -pdf
  -quiet -outdir=<tmp>` instead. `TEXINPUTS` is set to the temporary
  directory followed by the user's value, and `TEXMFOUTPUT` to the
  output directory.
- **Reruns:** after each run, pandoc reads `input.log`. It runs
  again while a line holds both `Warning:` and `Rerun`, or while
  `input.toc` exists, up to four runs.
- **Errors:** the error is taken from the log (`extractMsg`). After an
  `inputenc` error pandoc suggests xelatex. On success it reports the
  log's `Missing character:` lines as warnings.
- **tectonic** is run on standard input with `--outdir`, so that
  `\include` reads from the working directory. It makes its own
  passes.
- **Images** (`convertImages`):
  - PNG, JPEG, PDF and EPS are left alone (pdflatex converts EPS
    with `epstopdf`);
  - SVG is converted to PDF with `rsvg-convert`;
  - other bitmaps are converted to PNG in-process, with JuicyPixels.

podoc's `PdOptions.PdfWriterAndEngine` already pairs `latex` with
`pdflatex`, and with no `-t` and no engine it picks `latex` and
`pdflatex`, as pandoc does. It then stops with status 4: "podoc
makes PDF only with -t ms (groff, pdfroff), -t context (context) or
-t mom (pdfmom), not with pdflatex".

## 3. The user's use of LaTeX

A search of every `GNUmakefile` and `Makefile` under `~/Repos/RPG`
and `~/current/RPG` for `latex`, `xelatex`, `lualatex`, `eisvogel`
and `.tex` found:

- **pandoc to LaTeX:** only `Breachworld/.../Adventures/003-Arena`
  (two copies, under `~/Repos/RPG` and `~/current/RPG`). Its
  `%.ltx.pdf` and `%.ltx` rules use rST, `general.lua`, xelatex and
  the eisvogel template. `003-Arena.rst` is a 1.7 KB stub.
- **docutils to LaTeX:** `Campaigns/Possible` (`rst2latex.py`, then
  `pdflatex`) and `WVHTCF/4e-Harrison` (`rst2latex`, `pdflatex
  -file-line-error -interaction batchmode`). These are out of scope
  by decision 21. podoc could offer pandoc-style LaTeX for those
  files, but not docutils' LaTeX.
- **Leftovers:** clean rules in `Alusia/Return`, `Harrison/Mini-Six/
  Star-Wars` and `Troubled-Waters/PCs` remove `*.fdb_latexmk`,
  `*.xdv` and `*.ltx`. These suggest older LaTeX builds, which their
  current rules no longer run.
- **The ConTeXt builds** (`Lost-Worlds`, `Galactic-Bounty-Hunters`,
  `OVA-Farscape`, `Star-Legion`) use `cstyle.tex`. That file is
  ConTeXt, not LaTeX.

`~/.pandoc/templates/eisvogel.latex` is the 2020 eisvogel (1,034
lines, copyright 2017–2020). `general.lua`'s `latex` branches are:

| Class(es) | LaTeX |
|---|---|
| `title-ref`, `skill`, `att`, `spell`, `power`, `edge` | `\textit{...}` |
| `name`, `place`, `money`, `room`, `item` | `\textbf{...}` |
| `bi` | `\textbf{\emph{...}}` |
| `app` | `\textbf{\textit{...}}` |
| `red`, `green`, `blue` | `\textcolor{red}{...}` and so on |
| `file`, `cmd` | (message: unimplemented) |
| Div `box`, `keep` | nothing |
| `for-format` | kept when its classes include `latex` |

`PdFilters` would need these branches to match `general.lua` under
`-t latex`, as it has for ms, ConTeXt, HTML and mom.

None of the user's markdown or rST sets `lang` except the merchant
scenario's YAML (`lang: en-US`), and eight files may hold math (`$$`, `\(`, `:math:` or `.. math`).

## 4. Experiments

Run on atla, 2026-11-22, under a 4 GB `systemd-run` cap, with pandoc
3.10 and TeX Live 2026:

1. **The Arena build as written** (`--pdf-engine=xelatex
   --template=eisvogel`): fails, status 43, `! LaTeX Error: File
   'footnotebackref.sty' not found`. The user's only pandoc LaTeX
   build does not work on this machine today, with pandoc either. The
   cause is the TeX installation, not pandoc.
2. **The Arena stub with the default template:**

   | Engine | Wall | Peak RSS |
   |---|---:|---:|
   | pdflatex | 0.43 s | 122 MB |
   | latexmk | 0.50 s | 122 MB |
   | xelatex | 1.10 s | 186 MB |
   | lualatex | 9.19 s | 214 MB |

   The lualatex time includes building luaotfload's font cache on
   first use.
3. **The merchant scenario** (47 KB rST, `--toc`,
   `--lua-filter=general.lua`, `lang: en-US`), compared with the
   routes podoc has:

   | Route | Wall | Peak RSS | Result |
   |---|---:|---:|---|
   | pandoc, pdflatex | 0.92 s | 134 MB | fails: ♂ (U+2642) not set up for LaTeX |
   | pandoc, xelatex | 3.20 s | 191 MB | 27 pages; ♀, ♂, 🂡 and ⅓ missing from Latin Modern |
   | pandoc, lualatex | 5.35 s | 216 MB | 27 pages; the same missing characters |
   | pandoc, context | 1.76 s | 132 MB | |
   | podoc, ms (groff) | 1.38 s | 70 MB | |

   Each LaTeX engine ran four times (`--verbose`: "LaTeX run number
   4"). The contents file makes pandoc rerun until its limit. The
   missing characters need `mainfont` or a fallback font, as
   `statement.ms` uses Symbola.
4. **Writer output** for a small document (a C code block, a pipe
   table with a note, a figure at 50% width, emphasis, code, math,
   quotes, small caps, every TeX special character, a heading with an
   id, a `box` div):
   - The code block becomes `Shaded`/`Highlighting` with `\DataTypeTok`
     and the other token macros. With `--syntax-highlighting=none` it
     becomes `verbatim`.
   - The table becomes `{\def\LTcaptype{none} ... \begin{longtable}[]{@{}lr@{}}
     \toprule\noalign{} ... \endhead ... \endlastfoot ...}`. The note
     in a cell becomes a plain `\footnote`.
   - The figure becomes `\includegraphics[width=0.5\linewidth,height=\textheight,keepaspectratio,alt={cap}]`
     inside `figure`, with `\centering` and `\caption`.
   - Escapes: `\#`, `\$`, `\%`, `\&`, `\_`, `\{`, `\}`,
     `\textasciitilde{}`, `\^{}`, `\textless{}`, `\textgreater{}`,
     `\textbar{}`. Quotes are ``` `` ``` and `''`; `--` is kept as is.
   - The heading becomes `\section{Head}\label{h1}`, the math
     `\(x^2\)`, and the paragraph is wrapped at 72 columns.
   - The `box` div gives its contents with no frame. The LaTeX writer
     drops a div's classes.
   - `-M lang=de` and `-M lang=en-US` load babel with `bidi` and
     `shorthands=off` and set `pdflang`.
5. **podoc today:** `--syntax-highlighting`, `--listings`,
   `--top-level-division` and `--lof` are unknown options (status 2).
   `-o x.pdf` with no `-t` stops with status 4.
6. **The BSD VMs:** none of alerik, rackhir, artos, yishana, jherek or
   cymoril has pdflatex, xelatex, lualatex, latexmk or tectonic.

## 5. The writer

### 5.1 Shape

The proposed modules are:

| Module | From | Size (estimate) |
|---|---|---:|
| `PdTeX` | `LaTeX/Util.hs`: escaping, `toLabel`, the language table from `Lang.hs` | 500–600 |
| `PdLaTeX` | `LaTeX.hs`, `Caption.hs`, `Notes.hs`: blocks, inlines, the state, the template's variables | 1,500–1,800 |
| `PdLaTeXTable` | `LaTeX/Table.hs` | 450–550 |

The writer would build `PdLayout` documents, as `PdMs` and
`PdConTeXt` do since Phase 18, so that `--wrap=auto` at 72 columns
matches pandoc byte for byte. The rest is wiring:

- `PdPdf` and `PdOptions`: about 150 lines;
- `tools/mktemplates`, to embed the seven partials;
- the `latex` branch of `PdFilters`.

### 5.2 From pandoc's AST to LaTeX

| Element | LaTeX | Notes |
|---|---|---|
| Header | `\section` ... `\subparagraph`, `\label{id}` | `--top-level-division` shifts it to `\chapter` or `\part`; class `unnumbered` gives the `*` form and `\addcontentsline`; `\texorpdfstring` when the text holds math or a note |
| Para, Plain | text, wrapped | |
| BulletList | `itemize`, `\tightlist` when tight | |
| OrderedList | `enumerate`, with `\def\labelenumi{...}` and `\setcounter` for the style, delimiter and start | nested to four levels (`stOLLevel`) |
| DefinitionList | `description`, `\item[term]` | `stInItem`: notes and some commands change inside `[...]` |
| BlockQuote | `quote` | |
| CodeBlock | `verbatim`; `Shaded` when highlighted; `lstlisting` when idiomatic | `\VerbatimFootnotes` when a note holds verbatim |
| LineBlock | one paragraph, lines joined with `\\` (`linesToPara`) | leading spaces become no-break spaces |
| HorizontalRule | `\begin{center}\rule{0.5\linewidth}{0.5pt}\end{center}` | |
| Table | `longtable`, from `Table.hs` | relative widths as `p{(\linewidth - n\tabcolsep) * \real{w}}`; spans; caption on top or bottom |
| Figure | `figure`, `\centering`, the image, `\caption`, `\label` | subfigures; `latex-placement` attribute |
| Div | its contents; `\begin{otherlanguage}` for `lang`; `\protect\phantomsection\label` for an id | classes dropped; `refs` for citeproc |
| RawBlock, RawInline | kept for `latex` and `tex` | |
| Emph, Strong | `\emph`, `\textbf` | |
| Underline, Strikeout, SmallCaps | `\ul`, `\st` (soul), `\textsc` | `stInSoulCommand` changes escaping inside |
| Superscript, Subscript | `\textsuperscript`, `\textsubscript` | |
| Code | `\texttt{...}` with escapes; `\lstinline` when idiomatic | |
| Quoted | ``` `` ``` and `''`, or `\enquote` with csquotes | |
| Math | `\(...\)`, `\[...\]` | passed through |
| Link | `\href`, `\url`, `\hyperref[id]{...}` for internal ones | `\nolinkurl` for a link whose text is its address |
| Image | `\includegraphics`, inside `\pandocbounded` when it has no `width` or `height` | percentages of `\linewidth` or `\textheight`; `keepaspectratio` when only one is given |
| Note | `\footnote`; `\footnotemark` and `\footnotetext` in minipages and captions | |
| Span | its contents; `\foreignlanguage` for `lang` | |
| Cite | out of scope (no citations in podoc) | |

### 5.3 Metadata and the template

- **Variables the writer sets:** `tables`, `graphics`, `svg`,
  `strikeout`, `url`, `csquotes`, `numbersections`, `secnumdepth`,
  `toc`, `lof`, `lot`, `lang`, `babel-lang`, `babel-otherlangs`,
  `polyglossia-lang`, `highlighting-macros` (when highlighted),
  `listings`, `has-chapters`, `verbatim-in-note`, `subfigure`,
  `multirow`, `cancel`, `zwnj` and others. That is 47 calls to
  `defField` and `setField` in `LaTeX.hs`.
- **`documentclass`:** pandoc chooses `book` when
  `--top-level-division` is `chapter` or `part`, and `article`
  otherwise.
- **`--template`:** the user's own templates, eisvogel included.
  eisvogel 2020 predates pandoc 3.2.1's `\pandocbounded`. pandoc's
  changelog for 3.2.1 says custom templates without it raise "an
  error ... because of the undefined macro", so an image with no
  size fails under eisvogel 2020 in pandoc too. podoc would behave
  the same, and that is not a podoc problem.

### 5.4 The built-in filters

- **`general`:** add the `latex` column of §3's table. `box` and
  `keep` do nothing, as in `general.lua`, unless the user decides
  otherwise (§9, Q6).
- **`for-format latex`:** kept for `latex` (and for `beamer`, if it
  is ever added).
- **`toc-columns`:** writes raw ConTeXt only (`Lost-Worlds/toc-columns.lua`),
  so LaTeX needs nothing.

## 6. PDF through LaTeX engines

`PdPdf.LaTeX` would do what `tex2pdf` and `runTeXProgram` do:

- **Engines:** pdflatex, xelatex, lualatex and latexmk, matched by
  base name as for the other engines. tectonic is a question (§9, Q3).
- **Running:**
  - write `input.tex` in the temporary directory;
  - set `TEXINPUTS=<tmp>:` (followed by the user's value) and
    `TEXMFOUTPUT=<tmp>`;
  - run the engine with pandoc's arguments and the
    `--pdf-engine-opt` options.
- **The rerun loop:** podoc reads `input.log` itself and runs again
  while a line holds `Warning:` and `Rerun`, or while `input.toc`
  exists, at most four runs. `Platform.System` with redirection, as
  `PdRun` does, is enough. No process library is needed.
- **Messages:**
  - status 47 when the engine is missing;
  - status 43 with the log's `!` message when a run fails, adding
    pandoc's "Try running pandoc with --pdf-engine=xelatex" hint
    (worded for podoc) after an `inputenc` error;
  - the `Missing character:` lines as warnings.
- **Images:**
  - SVG with `rsvg-convert`, which `PdImages` already uses;
  - PNG, JPEG, PDF and EPS untouched;
  - other bitmaps to PNG, where pandoc converts in-process. podoc has
    no image library, so these would go to PDF with `img2pdf` or
    `magick`, through `PdImages.Convert`. This is a small difference,
    to be listed.
- **The default:** with the writer in place, `-o x.pdf` with no `-t`
  makes PDF with LaTeX and pdflatex, as pandoc does. Today it is an
  error.

## 7. What LaTeX would give podoc's users

- **pandoc's default PDF route.** `make PANDOC=podoc` would work for
  any rule that relies on pandoc's default (`pandoc -o x.pdf`), and
  for the Arena rules once their TeX packages are installed.
- **`.tex` output** that collaborators, journals and services such as
  Overleaf take. ms, ConTeXt and mom do not travel that way.
- **Math.** TeX typesets pandoc's math as written. ConTeXt does too,
  but ms has no `eqn` conversion (in "Later") and mom none either.
- **LaTeX's packages and classes** through templates: `memoir`,
  KOMA-Script, `tcolorbox` frames for `box` divs, `multicol`.
- **The docutils builds**, possibly. `Possible` and `4e-Harrison`
  could move from `rst2latex` to podoc's rST reader and LaTeX writer.
  That would be the user's choice, at the cost of their docutils
  LaTeX style (`style.tex`, `tkbstyle.tex`). Decision 21 does not
  ask for it.

What it would not give: anything for systems without TeX. On the
small and less common systems podoc is for, groff, which needs only
Perl for gropdf, is the PDF route.

## 8. Risks

1. **TeX's size and availability.** Fedora's TeX Live, as installed
   here, is 656 MB, and none of the six BSD VMs has an engine. pkgsrc,
   FreeBSD ports and OpenBSD packages do carry TeX Live, at a similar
   size. podoc's reason to exist is to build documents where pandoc is
   too big; LaTeX PDF needs something bigger than pandoc. `-t latex`
   to a file is unaffected. The PDF tests would skip almost
   everywhere except atla.
2. **TeX installations differ.** The user's own LaTeX build fails
   here for a missing package (§4). A LaTeX template or document
   works only where its packages are installed, which podoc cannot
   check or fix. podoc can at most report the log's error clearly.
3. **The size of the work.** At 2,500–3,000 lines the writer is more
   than `PdMs`, `PdRoff` and `PdMom` together, and close to `PdRst`.
   pandoc's tests are a strong oracle, but its LaTeX output has many
   context-dependent cases:
   - notes in captions, minipages and table cells;
   - soul commands, which change what may appear inside them;
   - `\item[...]` contents;
   - `\texorpdfstring` in headings;
   - fragile commands in moving arguments.

   Each of these needs its own tests.
4. **Highlighting.** pandoc's default LaTeX output highlights code
   that names a language, and the template then defines the token
   macros (`highlighting-macros`). podoc writes `verbatim`. The PDF
   differs in colour, not text, and that is listed. The `listings`
   route (Q4) narrows the gap but is not what pandoc does by default.
5. **Unicode and fonts.** Under pdflatex, any character outside
   `inputenc`'s set stops the run, as ♂ does in the merchant scenario.
   Under xelatex and lualatex, characters missing from the font
   vanish with only a log warning. The user's documents use ♀, ♂, 🂡
   and ⅓. podoc can only repeat pandoc's warnings and document
   `mainfont`.
6. **Run time.** Four engine runs whenever there is a contents: 3.2 s
   with xelatex and 5.4 s with lualatex for the merchant scenario,
   against 1.4 s for podoc's ms. That is pandoc's behaviour, and
   matching it is the point, but it makes LaTeX the slowest route.
7. **Template drift.** `default.latex` and its partials change often
   between pandoc releases: `\pandocbounded` arrived in 3.2.1, and the
   template was split into partials in 3.5 (pandoc 3.1.11.1 has
   neither). Because podoc embeds
   pandoc 3.10's copies, it is pinned, as for HTML, ms and ConTeXt.
   User templates written for other pandoc versions (eisvogel 2020)
   may not fit the writer's output in either program.
8. **Beamer.** `-t beamer` is the same writer with frames,
   overlays and `--incremental`. Leaving it out keeps the work bounded.
   Adding it later means about 250 more lines, a second template
   (`default.beamer`) and slide-level splitting, which podoc does not
   have for any writer.

## 9. Questions for the user

- **Q1. Schedule it?** The oracle is strong, but the user's builds
  use LaTeX in one non-default rule, and TeX is absent from every
  system but atla. Options:
  - schedule it all (the plan in §10);
  - schedule `-t latex` only (L1.1 to L1.5) and leave PDF through TeX
    in "Later";
  - leave it all in "Later".

  The user decided on 2026-11-22 not to add a LaTeX backend at all
  (PLAN.md's decision 28), so Q2 to Q8 are moot.
- **Q2. Beamer.** Out, to "Later" (recommended), or in?
- **Q3. Engines.**
  - pdflatex, xelatex, lualatex and latexmk (recommended), matched by
    base name. The `-dev` variants come almost free.
  - tectonic too? It is one self-contained binary that fetches
    packages on demand, so it is the TeX most likely to exist on a
    small system. But it is not installed here, so it would go
    untested unless installed.
- **Q4. Highlighting.**
  - (a) none: `verbatim`, as `--syntax-highlighting=none`, the
    difference listed (recommended as the start);
  - (b) (a) plus `--syntax-highlighting=idiomatic` and `--listings`,
    giving `lstlisting` and `\lstinline` as pandoc does, so that LaTeX
    highlights;
  - (c) skylighting-equivalent highlighting: out of proportion.
- **Q5. New options.** `--top-level-division`, `--lof`/`--lot`,
  `--table-caption-position`, `--figure-caption-position`, `--ascii`
  and `--syntax-highlighting`/`--no-highlight`. Add all of them, as
  the writer reads them (recommended)? Or only the ones the user's
  builds pass, which is none?
- **Q6. The general filter.** Match `general.lua` exactly: nothing for
  `box`, `keep`, `file` and `cmd` (recommended). Or give LaTeX a frame
  for `box` (`\fbox`/`mdframed`/`tcolorbox`, which needs a package) and
  something for the rest, as decision 27 did for mom?
- **Q7. Images.** Bitmaps other than PNG and JPEG converted to PDF
  with `PdImages`' converters, instead of pandoc's in-process PNG
  conversion (recommended, a listed difference). Or left unconverted,
  with a warning?
- **Q8. `-o x.pdf` with no `-t`.** Once LaTeX exists, follow pandoc
  (latex and pdflatex, recommended)? Or keep today's error and make
  the user name an engine?

## 10. The plan, not adopted

On 2026-11-22 the user decided not to add a LaTeX backend (PLAN.md's
decision 28). This is the plan that was proposed for it in PLAN.md,
kept here in case the question comes back. Its phases are numbered
L1 (for LaTeX), and it assumed these answers to §9's questions:

- `-t latex`, with no beamer;
- pdflatex, xelatex, lualatex and latexmk, with no tectonic;
- no highlighting (`verbatim`);
- all the options the writer reads;
- the general filter exactly as `general.lua`;
- other bitmaps converted to PDF;
- `-o x.pdf` with no `-t` made with LaTeX, as in pandoc.

Had the answer to Q1 been "`-t latex` only", L1 would have ended
after L1.5, and L1.6 would have gone to "Later".

pandoc 3.10 is the oracle, as for ms and ConTeXt. Expected files are
`pandoc -t latex` output, byte for byte, with default wrapping. They
may differ only where differences.md lists a difference, the first
being highlighting. pandoc's `test/writer.latex`, `test/tables.latex`
and `test/writers-lang-and-dir.latex`, and the command tests that
write LaTeX (not beamer), become case tests as their parts are built.
Each subphase passes `make test` under `-O2` and `-OC`.

### L1.1: TeX text

`PdTeX`, from `Writers/LaTeX/Util.hs` and `Lang.hs`.

- **Escaping:** `stringToLaTeX` in each of its contexts:
  - text;
  - code (`--` kept apart, `\textquotesingle`);
  - URLs;
  - inside soul commands;
  - with `--ascii`.
- **Labels:** `toLabel`, `labelFor` and `hypertarget`, with the
  heading form.
- **Languages:** BCP 47 to babel and polyglossia names, the whole
  `Lang.hs` table.
- **Tests:** `test/PdTeXTest.Mod`: strings with every special
  character, accents, quotes, dashes and non-ASCII text, and the
  language table. Each expected line comes from pandoc 3.10.

### L1.2: The writer, blocks and inlines

`PdLaTeX`, with `-t latex`. `-o` already maps `.tex`, `.latex` and
`.ltx` to latex. The writer builds `PdLayout` documents, wrapping at
`--columns` as `PdMs` and `PdConTeXt` do. Without `-s` it writes the
body.

- **Blocks:**
  - headings to `\subparagraph`, with `\label`, `unnumbered` and
    `\texorpdfstring`;
  - `itemize` and `\tightlist`;
  - `enumerate` with its style, delimiter and start, nested four
    deep;
  - `description`;
  - `quote`;
  - `verbatim` (with `\VerbatimFootnotes`);
  - line blocks;
  - rules;
  - divs and spans with `lang` (`otherlanguage`, `\foreignlanguage`)
    and ids;
  - raw `latex` and `tex`.
- **Inlines:**
  - `\emph`, `\textbf`, `\ul`, `\st`, `\textsc`, `\textsuperscript`,
    `\textsubscript`;
  - `\texttt`;
  - quotes, plain or with csquotes;
  - `\(...\)` and `\[...\]`;
  - `\href`, `\url`, `\hyperref` and `\nolinkurl`;
  - `\footnote`, with notes inside `\item[...]` and headings.
- **Writer state:** the context fields and the flags of
  `LaTeX/Types.hs` that this subphase needs. The flags are read by
  L1.4's template variables.
- **Tests:**
  - case tests `test/cases/<name>.latex` from podoc's markdown and rST
    cases, regenerated with pandoc;
  - `writer.latex`'s body, without tables and figures;
  - the command tests for these elements.

### L1.3: Tables and figures

`PdLaTeXTable`, from `LaTeX/Table.hs`, and the rest of figures and
notes.

- **Tables:**
  - `longtable` with `\toprule`, `\midrule` and `\bottomrule`;
  - head and foot;
  - relative widths as `p{(\linewidth - n\tabcolsep) * \real{w}}`;
  - `\multicolumn` and `\multirow`;
  - captions, with `\LTcaptype`;
  - notes in cells.
- **Figures:**
  - `figure`, `\centering`, `\caption` and `\label`;
  - subfigures;
  - `latex-placement`;
  - captions with notes moved out (`Caption.hs`, `Notes.hs`).
- **Images:** `\includegraphics` with `width` and `height`;
  `\pandocbounded` when neither is given; `keepaspectratio`; `alt`.
- **Options:** `--table-caption-position` and
  `--figure-caption-position`.
- **Tests:** `tables.latex`, the grid and pipe table cases, and the
  user's Mini-Six SRD tables (the largest rST file), compared with
  pandoc.

### L1.4: Standalone LaTeX

- **The template:** pandoc 3.10's `default.latex` and its seven
  partials, embedded by `tools/mktemplates` into `PdDefaults`, under
  the BSD licence already in `data/templates/README`.
- **Variables the writer sets:** about 47, from `LaTeX.hs`'s
  `defField` and `setField`:
  - `tables`, `graphics`, `svg`, `strikeout`, `url` and the other
    flags;
  - `documentclass` (`book` for chapters and parts);
  - `numbersections` and `secnumdepth`;
  - `toc`, `lof` and `lot`;
  - `lang`, `babel-lang`, `babel-otherlangs` and `polyglossia-lang`;
  - `has-chapters`.
- **Options:**
  - `--top-level-division`;
  - `--lof`/`--list-of-figures` and `--lot`/`--list-of-tables`;
  - `--ascii`;
  - `--syntax-highlighting`, `--no-highlight` and `--listings`,
    accepted, with every value but `idiomatic` giving `verbatim`
    (§9, Q4).
- **Tests:**
  - `writer.latex` and `writers-lang-and-dir.latex` whole;
  - cases with `-s`, `--toc`, `-N`, `lang` and `documentclass`;
  - a user template (`--template`) through partials.

### L1.5: The built-in filters and the user's files

- **`general`:** the `latex` branch of `general.lua` (research §3):
  - `\textit`, `\textbf`, `\textbf{\emph{...}}` and
    `\textbf{\textit{...}}`;
  - `\textcolor`;
  - the "unimplemented" messages for `file` and `cmd`;
  - nothing for `box` and `keep`.
- **`for-format latex`.**
- **Tests:** cases with `--lua-filter=general.lua`, against pandoc
  with the user's `general.lua`.
- **Acceptance:** `-s -t latex`, byte for byte against pandoc, for:
  - the Arena file, with the default template and with
    `--template=eisvogel`;
  - the merchant scenario, `--toc --lua-filter=general.lua`;
  - all 73 rST files of the corpus;
  - the Lost-Worlds markdown.

### L1.6: PDF through TeX

- **Engines:** pdflatex, xelatex, lualatex, latexmk and their `-dev`
  variants, by base name (`PdOptions.PdfWriterAndEngine`, which
  already pairs latex with pdflatex). With no `-t`, `-o x.pdf` makes
  PDF with latex and pdflatex, as pandoc does (Q8).
- **`PdPdf.LaTeX`:**
  - `input.tex` in the temporary directory;
  - `TEXINPUTS` and `TEXMFOUTPUT` set as pandoc sets them;
  - pandoc's arguments (`-halt-on-error -interaction nonstopmode
    -output-directory`, or latexmk's), then `--pdf-engine-opt`;
  - the rerun loop: read `input.log` and run again while it holds a
    `Warning:` ... `Rerun` line or `input.toc` exists, at most four
    runs.
- **Messages:**
  - 47 when the engine is missing;
  - 43 with the log's `!` error, and the xelatex hint after an
    `inputenc` error;
  - `Missing character:` lines as warnings.
- **Images:**
  - SVG to PDF with `rsvg-convert`;
  - PNG, JPEG, PDF and EPS untouched;
  - other bitmaps to PDF through `PdImages.Convert` (Q7; a listed
    difference).
- **Tests:** `tools/runlatex`, or cases in `tools/runimages`:
  - text, page count and outline (`pdftotext`, `pdfinfo`);
  - a `--toc` document run four times;
  - an SVG image;
  - a missing engine (47) and a failing document (43);
  - every test skips when its engine is missing.
- **Acceptance:** the merchant scenario with xelatex and lualatex and
  a `mainfont` that has ♀, ♂, 🂡 and ⅓. It should give pandoc's page
  count (27 with the default fonts) and no missing-character warnings.
  The Arena stub should work with each engine.

### L1.7: Documentation and other systems

- **Docs:**
  - docs/user/podoc.md: the writer, the engines, the new options, the
    template's variables, and fonts for Unicode;
  - docs/user/differences.md: highlighting, image conversion, and
    anything L1.2 to L1.6 found;
  - README.md, AGENTS.md and the module list;
  - `tools/bench`: a LaTeX row.
- **Other systems:** `make test` on the six BSD VMs. None has TeX
  (2026-11-22), so the PDF tests skip there; `-t latex` is tested
  everywhere.
