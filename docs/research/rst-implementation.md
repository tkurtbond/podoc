# podoc and reStructuredText: scope, possibilities and risks

Research done 2026-11-20 on whether podoc should read
reStructuredText (rST) as pandoc's `-f rst` reads it, and whether it
should write rST (`-t rst`). podoc reads only pandoc markdown today.
PLAN.md lists "other input formats, reStructuredText included" as out
of scope. docs/user/podoc.md tells the user to translate rST to
markdown once with pandoc. This document asks whether that should
change.

The measurements below were run on 2026-11-20 with pandoc 3.10
(`~/.cabal/bin/pandoc`), podoc at 53c1d65 (`build/OC/podoc`), and the
pandoc 3.10 source in `/usr/local/sw/src/lang/Haskell/pandoc/pandoc-3.10`.
The user's projects were only read, never changed.

## 1. Summary

- **rST is the user's main pandoc input, not a side case.**
  - 50 GNUmakefiles run pandoc on rST: `-r rst`, used 290 times.
  - About 30 run it on markdown.
  - The rST builds read 526 source files, 92,763 lines, outside
    `build/` directories.
  - The builds are still in active use: 8 of their makefiles changed
    in 2026-11.
  - podoc covers the markdown side. Without rST it covers a minority
    of the user's pandoc builds (§2).
- **Translating to markdown with pandoc is not a real substitute.**
  - The round trip `pandoc -f rst -t markdown`, then reading that
    markdown back, gives pandoc's own AST for only 69 of the 525
    files pandoc reads. Even with `--wrap=preserve` it fails for 298.
  - The losses come from pandoc's markdown, not from podoc:
    - smart quotes and dashes appear that the rST never had;
    - table column widths and alignments change;
    - autolinks gain a `uri` class.
  - podoc read that markdown exactly as pandoc did in 516 of the 525
    files (§5).
  - Translating also leaves the user writing rST while building from
    markdown. The user's generators emit rST too, for example the
    `*-gen.rst` files the Breachworld adventures include.
- **A reader is feasible, and smaller than the markdown reader.**
  - pandoc's `Readers/RST.hs` is 1,876 lines of Haskell. `Markdown.hs`
    is 2,375 lines, and podoc's markdown reader is 5,506 lines of
    Oberon.
  - The estimate is 3,500 to 4,500 lines of Oberon in two or three
    new modules (§8).
  - Everything after the reader is reused unchanged: the AST, all six
    writers, templates, the built-in `general.lua` and PDF output.
  - Grid tables use the same `gridTableWith` code as markdown, which
    podoc already has (`PdGridTable`).
- **Recommendation: a reader, yes; a writer, no.**
  - No makefile writes rST with pandoc (`-w rst`, `-t rst`, `--to rst`:
    0 uses).
  - A writer would be 990 lines of Haskell, about 2,000 lines of
    Oberon, and nothing the user builds needs it. It belongs in
    PLAN.md's "Later" (§7).
- **Recommendation: cover what the user's files use, not all of rST.**
  - The user's files use 15 of the 30-odd directives pandoc knows.
    `raw`, `container`, `include`, `role`, `image` and `figure` make
    up 90% of them (§3).
  - The goal is pandoc's JSON, byte for byte, for all 525 files, as
    the markdown reader was held to the user's markdown.
- **The main risks:**
  - rST's grammar depends on indentation;
  - pandoc's rST reader resolves references, substitutions and notes
    after parsing, so podoc needs a second pass;
  - `-s` changes the AST: the title is promoted and the docinfo
    becomes metadata;
  - pandoc's quirks, where it differs from docutils (§9).
- **Decided 2026-11-20:** a reader, all of pandoc's; no writer for
  now; the rST of the docutils and Nikola projects too. PLAN.md's
  decisions 18 to 22 (§11).

## 2. How the user uses rST

### 2.1 Where

The rST files were found under `~/Repos/RPG`, `~/current/RPG`,
`~/Repos/tkb-notes` and `~/Repos/tkurtbond.github.io`. There are
3,349 `.rst` files in all, but many are generated into build
directories:

| Directory | Generated `.rst` files |
|---|---|
| `current/RPG/Tools/BESM/build` | 627 |
| `Repos/RPG/Tools/ova_fmt/build` | 144 |
| `Red-Planet-Blue-Helmets/2ER/build/Entities` | not counted |

Three toolchains read them:

- **pandoc:** 50 GNUmakefiles, at depth 6 or less, run pandoc on rST
  (`-r rst` or `-f rst`).
- **docutils:** a few older projects (`Campaigns/Possible`,
  `WVHTCF/4e-Harrison`, `WVHTCF/Pete-DnD`) use docutils' `rst2xml.py`,
  `rst2latex.py` and `html.py` with a `docutils.conf`. No makefile
  uses both pandoc and docutils.
- **Nikola:** `tkurtbond.github.io` is a Nikola site (`conf.py`,
  `themes/`, `posts/`, `pages/`). Nikola renders rST through docutils.

The docutils projects and the Nikola site are out of scope: podoc
replaces pandoc, not docutils.

The rST that pandoc builds is the source of the 50 makefiles' own
directories, outside `build/`. That is 526 files and 92,763 lines. The
largest are `Online/Eldritch-Byzantium/acks.rst` (5,970 lines),
`Mini-Six/SRD-Adjacent/minimal-opend6-srd.rst` (5,625) and
`Mini-Six/SRD/output/minimal-opend6-srd.rst` (5,090). By area:

| Files | Area |
|---|---|
| 118 | `current/RPG/Campaigns` (Alusia and others) |
| 100 | `current/RPG/Kids` (Mini-Six, Star Wars) |
| 109 | Breachworld (`current/RPG` 59, `Repos/RPG` 50) |
| 38 | `current/RPG/Mini-Six` |
| 33 | `current/RPG/WVHTCF` |
| 25 | `current/RPG/Online` |
| 24 | `current/RPG/Harrison` |
| 8, 7, 7, 7 | tkb-notes/Health, Red-Planet-Blue-Helmets, Tools, AFF2e |

### 2.2 How pandoc is called

These counts come from the 50 makefiles. The patterns are rough, so
the numbers are approximate.

| Option | Uses |
|---|---|
| `-r rst` | 290 |
| `-s` | about 300 |
| `-w ms` | 177 |
| `-w context` | 98 |
| `-w html` | 48 |
| `-w native` | 8 |
| `-w latex` | 6 |
| `-w odt` | 5 |
| `-w epub` | 3 |
| `-w docx`, `-w rtf`, `-w gfm`, `-w markdown` | 1 each |
| `-w rst` | 0 |
| `--lua-filter=general.lua` | 231 |
| `--template=tkb` | 112 |
| `--template=statement` | 65 |
| `--template=$(PANDOCMSTEMPLATE)` | 40 |
| `--template=digest` | 36 |
| `--template=digest2` | 26 |
| `--template=eisvogel` | 6 |
| `--variable`, `-V` | about 90 |
| `--toc` | 6 |
| `--pdf-engine=xelatex` | 6 |
| `-N` | 2 |
| `--metadata-file=*.yaml` | 3 |

The `-F $(SHEET_FONTS)` that also turns up is groff's font directory,
not a pandoc filter. No rST build uses a JSON filter.

Apart from `-r rst`, these options are the markdown builds' options,
all of which podoc already handles:

- the ms, ConTeXt and HTML writers;
- the `tkb`, `statement` and `digest` templates;
- `general.lua`;
- `-V` variables such as `twocolumns`, `fontfamily`, `pointsize`,
  `lineheight` and `usegrowps`;
- `--toc`, `-N` and `--metadata-file`.

The latex, odt, epub and docx outputs are outside podoc's scope
whatever it reads.

### 2.3 What the files use

These counts cover the 526 source files. A line-start pattern
(`.. name::`) counts the directives.

| Directive | Uses | Notes |
|---|---|---|
| `raw` | 341 | ms 251, context 46, html 23, latex 21 |
| `container` | 221 | `character` 82, `box` 54, `for-format ms/context/html` 51, `spell`, `keep`, `weapon` |
| `include` | 174 | in 51 files; mostly generated `*-gen.rst` |
| `role` | 120 | `skill`, `spell`, `name`, `att`, `room`, `money`, `comment`; `ss(emphasis)` |
| `image` | 72 | `:alt:`, `:width:`, `:height:`, `:align:` |
| `figure` | 45 | |
| `note`, `Note`, `NOTE` | 42 | |
| `table` | 30 | `:widths:` 22 |
| `code` | 6 | |
| `rubric` | 5 | |
| `admonition` | 3 | |
| `list-table` | 2 | `:header-rows:` |
| `warning`, `footer`, `contents` | 1 each | |

And other constructs:

| Construct | Count |
|---|---|
| Interpreted text with a role (`` :role:`text` ``) | about 700; `name` 198, `skill` 149, `room` 102, `money` 54, ... |
| Substitution definitions (`.. \|x\| ...`) | 70 |
| Substitution references | 438 |
| Footnotes (`.. [#]`, `.. [1]`) | 62 |
| Citations (`.. [Label]`) | 12 |
| Hyperlink targets (`.. _name:`) | 328 |
| Named references (`` `text`_ ``) | 283 |
| Anonymous references (`` `text`__ ``) | 93 |
| Grid table border lines | 922 |
| Simple table border lines | 340 |
| Field list lines at the margin (docinfo) | 90 |
| Comments | about 1,100 |
| Literal blocks (`::`) | 36 |
| Line blocks | many; the pattern also matches grid table rows |

The custom roles and containers are how the user marks up game
content. pandoc reads `` :skill:`Climb` `` as `Span ("",["skill"],[])`
and `.. container:: for-format ms` as a `Div` with the classes
`container`, `for-format` and `ms`. podoc's built-in `general.lua`
already handles `for-format` Divs and Spans, so these need nothing
new after the reader.

## 3. What pandoc's rST reader is

`src/Text/Pandoc/Readers/RST.hs` in pandoc 3.10 is 1,876 lines, with
133 top-level definitions. It uses the shared `Text.Pandoc.Parsing`
code, as the markdown reader does, including `gridTableWith` from
`Parsing/GridTable.hs` (308 lines). The relevant parts:

- **Directives** (`directive'`): `include`, `table`, `list-table`,
  `csv-table`, `line-block`, `raw`, `role`, `container`, `replace`,
  `date`, `unicode`, `compound`, `pull-quote`, `epigraph`,
  `highlights`, `rubric`, `admonition` and the named admonitions,
  `sidebar`, `topic`, `default-role`, `highlight`, `aafig`, `math`,
  `figure`, `image`, `bibliography`, `class`, `code`/`code-block`.
  Unknown directives become a `Div` and a warning.
- **Roles**: `sup`, `superscript`, `sub`, `subscript`, `mark`,
  `emphasis`, `strong`, `rfc-reference`, `pep-reference`, `literal`,
  `math`, `title-reference`, `title`, `t`, `code`, `span`, `raw`. A
  role defined with `.. role::` becomes a `Span` with its name as a
  class, or inherits its base role's behaviour (`ss(emphasis)` gives
  `Emph`).
- **Tables**: grid tables through `gridTableWith`, the same parser
  the markdown reader uses, and simple tables with its own code
  (`simpleTable`, about 120 lines). The `table` directive adds a
  caption and `:widths:`. `list-table` and `csv-table` build tables
  from lists and CSV.
- **After parsing** (`parseRST`):
  - substitutions (`resolveBlockSubstitutions`) and references
    (`resolveReferences`) are resolved over the whole document;
  - citations are gathered into a `Div` with the id `citations`;
  - notes are put back in order.
- **Standalone**: with `-s` (`readerStandalone`), `titleTransform`
  promotes a lone top section title, and a subtitle under it, to
  metadata. A docinfo field list becomes metadata as well. Without
  `-s`, the same input gives a `Header` and a `DefinitionList`. The
  probe below showed it.
- **Extensions**: `pandoc --list-extensions=rst` enables only
  `auto_identifiers`. There are no smart quotes, which is why the
  markdown round trip adds them (§5).
- **Includes** are part of the reader. `include` reads the file
  relative to the including file. It takes `start-line`, `end-line`,
  `literal` and `code`. No `pandoc-include` is involved.

A probe on 2026-11-20 used `.. role:: skill`, `:skill:`,
`.. role:: ss(emphasis)`, `|sub|` with `replace`, an auto-numbered
footnote, a `for-format ms` container holding `raw:: ms`, an include,
a line block, a comment and a docinfo field. `pandoc -f rst -t native`
gave the shapes described above: `Span` with a class, `Emph`, the
replaced text inline, `Note`, `Div` with `container` among its
classes, the included paragraph spliced in, `LineBlock` with leading
spaces as U+00A0, and the comment dropped. With `-s`, the title and
the `author` field moved into the metadata.

pandoc's tests for the reader:

- `test/rst-reader.rst`, 432 non-blank lines, and its `.native`;
- `test/tables.rst`;
- `test/tables-rstsubset.native`;
- 61 command tests in `test/command/*.md` that read rST, for example
  `figures-rst.md`, `rst-links.md`, `rst_block_subst.md`,
  `3533-rst-csv-tables.md` and `10338-rst-multiple-header-rows.md`.

## 4. What podoc would need

- **A reader**: new modules `PdRst` (blocks, directives, the
  post-parse passes) and `PdRstInline` (inline markup, roles,
  references, substitutions). Perhaps also `PdRstTable` for simple,
  list and CSV tables. They would produce the AST `PdAst` already
  defines. Every node kind the user's files need exists:
  - `LineBlock`, `DefinitionList`, `Div`, `Figure`, `Table`;
  - `Note`, `Span`, `RawBlock`, `RawInline`.
- **Reuse**:
  - `PdMdBase`'s text buffer and character classes;
  - `PdMdInline.RealLength` and `CharWidth`;
  - `PdGridTable.Trace`. It reads from `PdMdBase`'s text today, so the
    rST reader would either use the same buffer or the tracer would
    take its text as a parameter.
  - podoc's ColWidth formatting for `:widths:` and simple tables
    (Haskell's `show` for `Double`, e.g. `1.5625e-2`), which the
    markdown tables already need.
- **The command line**: `-f rst` and `-r rst`, and inputs ending in
  `.rst` when there is no `-f`. Today these end podoc with status 21,
  as recorded in differences.md. The reader must see `-s`, because
  `-s` changes what it produces.
- **Includes**: the `include` directive in the reader, relative to the
  including file. It needs `start-line`/`end-line`, `literal`/`code`,
  a guard against recursion, and pandoc's errors and exit statuses
  for a missing file. podoc's `PdInclude` (`pandoc-include`) is a
  markdown filter and does not apply.
- **Nothing else.** The writers, templates, `general.lua`,
  `--toc`, `-N`, `--metadata-file`, variables and PDF output work on
  the AST and are shared.

## 5. Translating with pandoc

docs/user/podoc.md says to translate once:
`pandoc -s -r rst -w markdown-grid_tables --columns=110`. This was
checked on the 526 files, on 2026-11-20:

1. `pandoc -f rst -t json` against
   `pandoc -f rst -t markdown | podoc -f markdown -t json`:
   - 69 the same;
   - 456 different;
   - 1 that pandoc itself did not read (an error or the 60-second
     limit).
2. For the 456:
   - pandoc's own round trip, `pandoc -f rst -t markdown`, then
     `pandoc -f markdown -t json`, matched in none of them;
   - podoc and pandoc read the markdown identically in 447.
3. With `--wrap=preserve`, which keeps pandoc's markdown from moving
   `SoftBreak`s, pandoc's own round trip matched in 158 of the 456.
   The remaining 298 differ because markdown means something else:
   - `Quoted`/`DoubleQuote`, en and em dashes and ellipses: markdown's
     `smart` extension, which pandoc's rST reader does not have;
   - table column widths and alignments (`ColWidthDefault` against
     `ColWidth 1.5625e-2`, `AlignDefault` against `AlignLeft`);
   - `uri` classes on links, and changes in images and `Plain`
     against `Para`.

   These change the output: typographic quotes instead of straight
   ones, and different table layouts. The Mini-Six SRD comparison in
   PLAN.md's State found the same table widths.
4. podoc's 9 differences on the markdown are both already known or
   small:
   - 7 files have raw TeX blocks (`\newpage`, `\clearpage`,
     `\pagebreak`), which podoc reads as a `Para` holding a
     `RawInline`. Raw TeX blocks are in PLAN.md's "Later".
   - 2 files contain a form feed (U+000C). podoc's JSON writer writes
     it as `\f`, where pandoc's (aeson) writes `\u000c`. Backspace
     (U+0008) is the same: podoc writes `\b`, pandoc `\u0008`. Both
     forms are valid JSON with the same meaning, so only a byte for
     byte comparison sees the difference. This is a small, newly found
     bug in `PdJson`, not fixed here.

So translation is a lossy conversion. It is fine once, by hand, for a
finished book. It is no substitute for building the user's rST
projects as pandoc builds them.

## 6. Potential

- **Coverage.** With rST, podoc can stand in for pandoc
  (`make PANDOC=podoc`) in the 50 rST builds as well as the markdown
  ones. These are most of the user's pandoc builds. The goal of the
  proof of concept, building where pandoc cannot be installed, then
  holds for most of the user's writing.
- **The generators.** The user's tools emit rST: BESM, ova_fmt, the
  2ER entity scripts and the Breachworld `*-gen.rst` files. With a
  reader, those pipelines run on podoc unchanged.
- **Little new output work.** The ms, ConTeXt and HTML writers, the
  templates and the `for-format` handling are already checked
  against pandoc. A Div or Span from an rST file is written exactly as
  one from markdown.
- **A clear, measurable target.** The 525 files that pandoc reads give
  a corpus with a byte-for-byte JSON oracle, as the markdown corpus
  did.

## 7. The writer

No makefile writes rST with pandoc. The one place rST is written is
by the user's own generators, which are not pandoc. pandoc's
`Writers/RST.hs` is 990 lines, and 31 of its command tests write rST.
In Oberon it would be about 2,000 lines, with the same wrapping and
table layout work as the markdown writer (`PdLayout`, `PdGridTable`'s
widths, `PdWidth`). It would let podoc convert markdown to rST, which
nothing in the user's builds does.

**Recommendation:** leave `-t rst` to PLAN.md's "Later". It can come
later if the user wants podoc to translate between the two formats.

## 8. Size

| | Haskell | Oberon |
|---|---|---|
| markdown reader | `Markdown.hs` 2,375, plus shared `Parsing/` | `PdMarkdown` 2,325 + `PdMdInline` 1,895 + `PdMdBase` 1,286 = 5,506 |
| rST reader | `RST.hs` 1,876, plus the same `Parsing/` | estimate 3,500 to 4,500 |
| rST writer | `Writers/RST.hs` 990 | estimate 1,800 to 2,200 (not recommended) |

The markdown reader came out at about 2.3 Oberon lines per Haskell
line. The rST estimate applies a little less than that ratio to
`RST.hs`, because the reader can reuse:

- the text buffer;
- character widths;
- grid tables (`PdGridTable`, about 500 lines that need not be
  written again);
- the post-parse passes, modelled on the markdown reader's reference
  resolution.

podoc is 23,665 lines of Oberon today, so the reader would add about
15 to 20%.

## 9. Risks

- **The indentation grammar.**
  - rST nests by indentation relative to the enclosing construct, not
    by markers. Block quotes, list items, definition lists, field
    lists, directive bodies and literal blocks all end where the
    indentation does.
  - pandoc reads each body by cutting it out and parsing it again
    (`parseFromString'`). podoc's reader would do the same on
    sub-ranges of the text, as the markdown reader does for list
    items.
  - Errors here change the AST a long way from where they happen, so
    the tests must be broad.
- **pandoc, not docutils.**
  - pandoc's reader differs from docutils in places: inline markup
    recognition, unknown directives, the `container` class added to
    every container, and the line block U+00A0s.
  - Where the user's documents depend on docutils' behaviour, they
    already get pandoc's, so podoc should match pandoc. As with
    markdown, the rule is to run pandoc 3.10 and do what it does.
- **The post-parse passes.** References, anonymous references,
  substitutions and footnotes can be defined after they are used.
  Substitutions can hold images and other roles. The reader needs a
  resolution pass over the whole AST after parsing, and pandoc's
  ordering of notes and citations must be matched exactly to get its
  JSON.
- **Standalone changes the AST.** `titleTransform` and docinfo depend
  on `-s`. The reader must take the option, and the tests must cover
  both.
- **Includes.**
  - Paths are relative to the including file.
  - Included files can include files of their own.
  - `start-line`/`end-line` count lines.
  - The included text is parsed in the includer's state, sharing its
    roles, substitutions and targets.
  - Errors must give pandoc's exit statuses.
- **Simple tables** have their own column rules: column boundaries
  from the `=` borders, continuation lines, and spans marked by `-`
  underlines. They are a second table parser beside `PdGridTable`.
- **Breadth.** The user's files use 15 directives. Each further
  directive pandoc knows (`csv-table`, `math`, `sidebar`, `topic`, ...)
  is small, but there are many. They should be added only when a
  document needs them, as the scope rule says.
- **Both size models.** rST text is indexed with `LONGINT`, as the
  markdown reader's is. Indentation and table columns fit in
  `INTEGER`, but under `-O2` a long file's offsets do not.
- **Growth.** About 4,000 more lines to keep working under both size
  models and on the BSDs. That is affordable, but it is the largest
  addition since the markdown reader.

## 10. A possible plan

If the user decides to go ahead, the work would be a phase, or a
group of phases, in PLAN.md. Each step is checked against
`pandoc -f rst -t json`, byte for byte, with case tests under
`test/cases/` and the corpus comparison over the user's 525 files
(with `make compare`, which needs pandoc):

1. **Blocks**:
   - sections, with adornment levels in order of first use;
   - paragraphs, transitions and comments;
   - literal blocks and block quotes;
   - bullet, enumerated, definition and field lists;
   - line blocks;
   - `-f rst` and `.rst` on the command line.
2. **Inlines**:
   - emphasis, strong and literals;
   - interpreted text, with the standard roles and `.. role::`;
   - hyperlinks: named, anonymous, embedded and standalone; targets;
   - footnotes and citations;
   - substitutions: `replace`, `unicode`, `date` and images;
   - the post-parse resolution.
3. **Directives** the files use:
   - `raw`, `container`, `include`, `image`, `figure`;
   - the admonitions, `code`, `rubric`, `class`.
4. **Tables**:
   - grid tables through `PdGridTable`;
   - simple tables;
   - `table` with `:widths:`;
   - `list-table`.
5. **Standalone and the corpus**:
   - `titleTransform` and docinfo under `-s`;
   - all 525 files matching pandoc's JSON;
   - PDFs from a few of the user's builds compared with pandoc's,
     as for markdown in Phase 15.

## 11. Questions for the user, and the decisions

The user decided the questions on 2026-11-20; they are recorded in
PLAN.md as decisions 18 to 22.

1. **Should podoc read rST?** Yes (decision 18).
2. **A writer?** Not now: `-t rst` goes to "Later" (decision 19).
3. **How much of rST?** All of pandoc's reader, not only what the
   user's files use (decision 20). This raises the estimate of §8:
   the reader is all of `RST.hs`, about 4,500 lines of Oberon rather
   than 3,500, and the tests must include pandoc's `rst-reader.rst`,
   `tables.rst` and the 61 command tests that read rST.
4. **The docutils projects and the Nikola site?** podoc must read the
   standard rST in those files, as pandoc reads it, but it does not
   replace docutils' writers or Nikola's templates and blog output
   (decision 21). Nikola's own directives and roles come out as
   pandoc gives them. Probed on 2026-11-20 with `.. post-list::`,
   `.. thumbnail::`, `` :doc: `` and `` :abbr: ``:
   - an unknown directive becomes a `Div` with the directive's name
     as a class and its options as attributes, its body read as
     blocks;
   - an unknown role becomes `Code` with the class `interpreted-text`
     and the attribute `role`;
   - pandoc reports the directives only under `--verbose`, as
     `[INFO] Skipped '.. post-list' at n.rst line 6 column 1`, and the
     roles not at all. `--fail-if-warnings` does not stop on them,
     because they are INFO messages, not warnings.
5. **A mode that warns about unknown constructs, and one that makes
   them errors.** Yes, covering anything else pandoc drops, too
   (decision 22, 2026-11-20). Silent by default, as pandoc is;
   `--verbose` prints pandoc's `[INFO] Skipped ...` lines; a podoc
   option, proposed as `--unknown=warn|error`, reports each unknown
   directive, role or dropped construct with its file, line and
   column, as a warning or as an error with status 64.
6. **The form feed bug** in `PdJson` (§5). Fixed on 2026-11-20.

## 12. Sources consulted

- pandoc 3.10 source:
  - `src/Text/Pandoc/Readers/RST.hs`;
  - `src/Text/Pandoc/Writers/RST.hs`;
  - `src/Text/Pandoc/Readers/Markdown.hs`;
  - `src/Text/Pandoc/Parsing/` and `Parsing.hs`;
  - `test/rst-reader.rst`, `test/tables.rst`, `test/command/`.
- `pandoc --list-extensions=rst`, and probes of `pandoc -f rst -t
  native`, with and without `-s`.
- The 50 GNUmakefiles that run pandoc on rST, and the 526 rST source
  files in their directories, under `~/Repos/RPG`, `~/current/RPG` and
  `~/Repos/tkb-notes`. All were read only.
- `~/Repos/tkurtbond.github.io` (`conf.py`, `themes/`), and the
  docutils makefiles in `current/RPG/Campaigns/Possible` and
  `current/RPG/WVHTCF`.
- podoc's sources, PLAN.md, docs/user/podoc.md and
  docs/user/differences.md, at 53c1d65.
