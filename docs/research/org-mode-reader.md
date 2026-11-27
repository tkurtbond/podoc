# podoc and Org mode: scope, potential, benefits and risks

Status, 2026-11-26: done, as PLAN.md's Phases 26 to 28 (decisions 55
to 59). podoc's `-f org` matches pandoc 3.14 on the user's 663 files
but for decision 57's raw LaTeX; the results are in PLAN.md's State
and the remaining differences in docs/user/differences.md. What
follows is the research as it was done, before the reader existed.

Research done 2026-11-26 on whether podoc should read Emacs Org mode
files as pandoc's `-f org` reads them. podoc reads pandoc markdown and
reStructuredText today. `-f org`, or an input ending in `.org`, ends
podoc with "Unknown input format 'org'" and status 21: `PdOptions`
already deduces `org` from the extension, as pandoc does, but no
reader takes it.

The measurements below were run on 2026-11-26 with pandoc 3.14
(`~/.cabal/bin/pandoc`, the oracle), podoc at 21cc5ee
(`build/OC/podoc`), and the pandoc 3.10 source in
`/usr/local/sw/src/lang/Haskell/pandoc/pandoc-3.10`. The 3.14 source
was unpacked afterwards, into `pandoc-3.14` beside it, and the plan
(PLAN.md, Phases 26 to 28) was checked against it. The user's files were only read, never changed. The
counts over them are aggregate: no file's contents are quoted here.

## 1. Summary

- **The user has many Org files, but no build runs pandoc on them.**
  - 663 `.org` files, 2.6 MB, under `~/Repos` and `~/current`.
  - About 470 of them are in one notes repository, last committed
    2026-11-25; 167 files changed in 2026. They are in active use.
  - No GNUmakefile, script or Nikola configuration runs pandoc with
    `-f org`, and the Emacs configuration sets up no Org export
    (§2.2). Org is where the user writes notes, task lists and
    reference material, read in Emacs, not a source for documents.
  - This differs from rST, which was the user's main pandoc input
    (rst-implementation.md §1). An Org reader would serve a use the
    user does not have yet, not replace one podoc misses.
- **The files use a small part of Org.** Headlines, lists, links,
  emphasis, inactive timestamps and TODO keywords account for almost
  everything. Footnotes, includes, macros, citations, property
  drawers, export blocks and `#+OPTIONS` beyond a handful are absent
  or nearly so (§2.3).
- **pandoc reads all of them.** `pandoc -f org -t json` read all 663
  files without an error or a warning. The largest, 490 KB, took
  0.59 s and 172 MB.
- **Translating to markdown with pandoc is a weak substitute.** The
  round trip org → markdown → AST gives pandoc's own AST for 219 of
  the 663 files, 339 with `--wrap=preserve` (§5). podoc read that
  markdown as pandoc did in 661 of 663.
- **A reader is feasible, but larger than the rST reader.**
  - pandoc's Org reader is 3,694 lines of Haskell in 10 modules, 2,914
    without blank lines and comments, against `RST.hs`'s 1,517.
  - The rST reader came out at 4,717 lines of Oberon, about 3.1 per
    Haskell code line. The same ratio gives 7,000 to 9,000 lines for
    Org (§8): 20 to 27% on podoc's 33,675.
  - It reuses `PdMdBase`'s buffer, `PdMdInline`'s text building,
    `PdShared`, the identifier rules and the post-parse passes, but
    not `PdGridTable`: Org tables are a different, simpler form.
- **The hard parts are not Org's syntax.** They are the parts pandoc
  borrows from elsewhere: its LaTeX reader and texmath for LaTeX
  fragments (`\textbf{x}` becomes `Strong`), the MathML entity table
  for `\alpha`, and the document-tree pass (export settings, TODO
  keywords, tags, archived and `COMMENT` trees) that changes the AST
  after parsing (§3, §9).
- **Recommendation.** Not now, as the scope rule stands: no document
  the user builds needs it. If the user wants to publish notes or
  `README.org` files with podoc, a reader limited to what the files
  use (§4, tier A), about half the size, is the way to start, held to
  pandoc's JSON on the user's 663 files. The decision is the user's
  (§11).

## 2. How the user uses Org

### 2.1 Where

| Area | Files |
|---|---|
| A notes repository in `~/Repos` | 471 |
| `~/current` (RPG campaigns, computing notes, older org notes) | 119 |
| Other repositories in `~/Repos` (RPG, Ada, Oberon, scratch, ...) | 73 |

14 are `README.org` files. Sizes: median 357 bytes, 90th percentile
5.2 KB, largest 490 KB. Six paths ending in `.org` are directories
(mirrored web sites) and were skipped.

### 2.2 How pandoc is called

It is not:

- No makefile or shell script under `~/Repos` or `~/current` passes
  an Org file to pandoc. The only hit for pandoc near `.org` was
  `~/Repos/tkurtbond.github.io/conf.py`, where the pandoc compiler
  line is commented out and `.org` occurs only in URLs.
- `~/.emacs` mentions no `ox-` exporter, `org-export`, `org-publish`
  or pandoc.
- The two `.org` files in the Nikola site are a reference page and a
  pending post, not built.

So nothing in the user's builds needs an Org reader today. The uses
it would open are in §6.

### 2.3 What the files use

Lines matching each construct, by case-insensitive `grep` over the
663 files; the patterns are approximate (a `$...$` match may be a
price, for example).

| Construct | Files | Lines |
|---|---|---|
| Headlines | 650 | 16,550 |
| Inactive timestamps `[2026-01-01 ...]` | 53 | 2,792 |
| Bullet lists `-`/`+` | 56 | 1,461 |
| Links `[[...]]` | 152 | 773 (682 `http`, 93 `file:`, 33 internal) |
| TODO keywords in headlines | 49 | 771 |
| Ordered lists | 36 | 600 |
| Verbatim and code `=...=`, `~...~` | 63 | 595 |
| Table rows | 16 | 520 (one table with `#+TBLFM`) |
| Bold | 47 | 389 |
| Tags on headlines | 15 | 112 |
| Math-like `$...$`, `\(...\)` | 18 | 90 |
| Comment lines `# ` | 13 | 83 |
| Source blocks `#+BEGIN_SRC` | 31 | 83 (bash 40, emacs-lisp 24, a few others) |
| Active timestamps `<2026-01-01 ...>` | 16 | 75 |
| Planning lines `SCHEDULED:` etc. | 8 | 26 |
| `#+STARTUP` | 9 | 23 |
| Dynamic blocks `#+BEGIN:` | 7 | 17 (16 `clocktable`) |
| `#+TAGS`, `#+PROPERTY`, `#+SEQ_TODO`, `#+COLUMNS` | | 14, 13, 7, 7 |
| `#+TITLE`, `#+AUTHOR`, `#+DATE`, `#+OPTIONS` | 10, 3, 3, 4 | |
| `#+CAPTION`, `#+ATTR_LATEX`, `#+LABEL` | 2 | 6 each |
| Example, quote blocks | 3, 1 | |
| Horizontal rules, line breaks `\\`, strikeout | | 8, 7, 5 |

Not used at all: footnotes `[fn:...]`, `#+INCLUDE`, `#+SETUPFILE`,
`#+MACRO`, `{{{macros}}}`, citations `[cite:...]`, property drawers
(`:PROPERTIES:`), `:LOGBOOK:`, `COMMENT` headlines, priorities,
definition lists, export blocks and snippets (`#+BEGIN_EXPORT`,
`@@html:...@@`), verse and centre blocks, LaTeX environments, Org
entities (`\alpha`), inline source (`src_lang{}`), radio targets,
`#+SELECT_TAGS`/`#+EXCLUDE_TAGS`. One checkbox and one `#+RESULTS`.

## 3. What pandoc's Org reader is

`src/Text/Pandoc/Readers/Org.hs` and `Org/`:

| Module | Lines | What |
|---|---|---|
| `Blocks.hs` | 1,002 | blocks: `#+BEGIN_...` blocks, source blocks and their header arguments and switches, dynamic blocks, drawers, figures, tables, lists, `#+INCLUDE`, LaTeX environments, footnote definitions |
| `Inlines.hs` | 950 | emphasis and its border rules, links and images, targets, footnote references, citations (org-cite and org-ref), timestamps, inline source and babel calls, export snippets, macros, LaTeX fragments, entities, sub- and superscripts, smart punctuation |
| `DocumentTree.hs` | 423 | the headline tree: TODO keywords, priorities, tags, properties, planning, archived and `COMMENT` trees, select and exclude tags, headline levels beyond `H:` turned into lists |
| `Meta.hs` | 301 | `#+TITLE` and the other keywords into metadata, `#+MACRO`, `#+TODO`, `#+LINK` abbreviations, `#+OPTIONS`, `#+LATEX_HEADER` etc. |
| `ParserState.hs` | 300 | the state: export settings, notes, macros, link formatters, identifiers |
| `Parsing.hs` | 234 | the parser primitives over Org lines |
| `ExportSettings.hs` | 190 | `#+OPTIONS`: about 35 keys, `toc:`, `H:`, `todo:`, `tags:`, `p:`, `d:`, `^:`, `e:`, `tex:`, ... |
| `BlockStarts.hs` | 159 | what can begin a block, to end paragraphs |
| `Shared.hs` | 90 | link text cleaning, image file names |
| `Org.hs` | 45 | the entry point |

It depends on parts of pandoc outside the Org reader:

- **The LaTeX reader** (`rawLaTeXInline`, `inlineCommand`, and
  `inlineEnvironmentNames`), to find where a LaTeX command or
  environment ends.
- **texmath** (`readTeX`, `writePandoc`), to turn a LaTeX command
  into inlines when it can: `\textbf{x}` comes out as `Strong [Str
  "x"]`, while `\sqrt{2}` and `\frac{1}{2}` stay `RawInline latex`.
- **The MathML entity map** in texmath, for Org entities: `\alpha` is
  `Str "α"`, `\nbsp` is U+00A0.
- **`Text.Pandoc.Parsing`**, shared with the other readers, as for
  markdown and rST: smart punctuation, identifiers, notes.

Its extensions (`pandoc --list-extensions=org`): `+auto_identifiers`,
`+citations`, `+special_strings`, `+task_lists`; `-smart`,
`-smart_quotes`, `-fancy_lists`, `-ascii_identifiers`,
`-gfm_auto_identifiers`, `-east_asian_line_breaks`. Org's own
`#+OPTIONS` (`':`, `-:`, `^:`, `*:`, `e:`, `tex:`) turn several of
these on and off within the file.

Its tests: `test/Tests/Readers/Org/` holds about 2,870 lines, some 420
cases (blocks, code blocks, figures, headers, lists, tables, inlines,
citations, notes, smart punctuation, meta, directives); `test/command`
has 34 files with 53 `-f org` runs; `test/org-select-tags.org` is read
with `-s` against a native file.

What pandoc gives for the constructs the user's files use, checked on
a sample with pandoc 3.14:

- A TODO keyword becomes `Span ("", ["todo", "TODO"], [])`, `DONE`
  `Span ("", ["done", "DONE"], [])`; the keywords come from
  `#+SEQ_TODO`/`#+TODO`.
- Tags become `Span ("", ["tag"], [("tag-name", t)]) [SmallCaps [Str
  t]]`, separated by U+00A0.
- A priority `[#A]` stays text.
- Planning lines, property drawers and `:LOGBOOK:` are dropped by
  default (`p:nil`, `d:` settings); `:CUSTOM_ID:` becomes the
  header's identifier.
- `#+STARTUP` and other keywords pandoc does not know become
  `RawBlock (Format "org")`, which the writers drop.
- A `#+BEGIN: clocktable` dynamic block becomes a `Div` with class
  `clocktable` and its parameters as attributes, around the table.
- Timestamps are plain text.
- `=verbatim=` is `Code` with class `verbatim`, `~code~` plain `Code`.
- `[ ]` and `[X]` in lists become ☐ and ☒ (`task_lists`).
- `--` becomes an en dash (`special_strings`), without `smart`.
- `H_2O` is `Str "H", Subscript [Str "2O"]`: Org's rule, not
  markdown's.
- `$x^2$` and `\(y\)` are `Math InlineMath`.
- `#+INCLUDE` is read by the reader itself, relative to the
  including file; an unknown `{{{macro}}}` stays text.

## 4. What podoc would need

Two possible scopes, as for rST (decision 20 chose the larger one
there).

**Tier A: what the user's files use** (§2.3), matched to pandoc's
JSON byte for byte on all 663 files:

- headlines, with identifiers, TODO keywords from `#+SEQ_TODO` and
  `#+TODO`, tags, `:CUSTOM_ID:`, dropped planning lines and drawers;
- paragraphs, line breaks, horizontal rules, comment lines and fixed
  width lines;
- bullet and ordered lists, with checkboxes and alphabetic markers;
- emphasis, verbatim and code, strikeout, underline, sub- and
  superscripts, special strings;
- links: `http`, `file:` (images among them), internal and
  `#custom-id`, targets `<<...>>`;
- source, example and quote blocks;
- Org tables, with alignment cookies and `#+TBLFM` ignored;
- dynamic blocks, `#+CAPTION`, `#+NAME`, `#+ATTR_...`;
- `#+TITLE`, `#+AUTHOR`, `#+DATE` and the keywords that become
  metadata or `RawBlock org`; `#+OPTIONS` as far as the files set it;
- `$...$` and `\(...\)` math, kept as TeX, as the markdown reader
  keeps it.

**Tier B: all of pandoc's Org reader**, held to its unit and command
tests as well: footnotes, includes, macros, citations, export blocks
and snippets, verse, centre and special blocks, drawers, inline source
and babel calls, LaTeX environments and fragments, entities, the
`#+OPTIONS` keys, select and exclude tags, archived trees, `#+LINK`,
headline levels past `H:`, `#+LATEX_HEADER` and the other export
keywords.

Both need, outside the reader:

- `-f org` and `.org` in `PdOptions` (the deduction is there; the
  reader dispatch in `podoc.Mod` is not);
- `-s`: Org's metadata goes into the templates as rST's and
  markdown's does; no new template is needed, since podoc writes no
  Org;
- the writers already handle what the reader makes: `Span` with
  classes, `SmallCaps`, `Div`, `Underline`, tables, `Math`,
  `RawBlock` of a format they drop;
- `docs/user/podoc.md` and `differences.md`, the case tests and the
  `tools/` comparison scripts.

## 5. Translating with pandoc

The alternative to a reader is to translate once, `pandoc -f org -t
markdown`, and build the markdown with podoc. Over the 663 files:

| | Files giving pandoc's own AST |
|---|---|
| org → markdown → AST (default wrapping) | 219 |
| the same with `--wrap=preserve` | 339 |
| podoc reading pandoc's markdown, against pandoc reading it | 661 |

So podoc reads the translated markdown almost exactly as pandoc does;
the losses are in pandoc's markdown writer and reader, not in podoc.
The kinds of change were not classified this time. For rST they were
smart punctuation, table widths and alignments and autolink classes
(rst-implementation.md §5); for Org, the `todo`, `tag` and
`clocktable` spans and divs, verbatim classes and the U+00A0 between
tags are likely candidates, but this is not verified.

Translating also leaves the user writing Org in Emacs while building
from markdown, and the markdown would have to be translated again
after every edit. For notes that keep changing, that is not a real
substitute; for a one-off document it is enough.

## 6. Potential and benefits

- **Publishing notes and READMEs without pandoc.** HTML, ms, mom,
  ConTeXt or PDF from Org files on the small and less common systems
  podoc is for, where neither pandoc nor Emacs's exporters may be
  installed. The 14 `README.org` files and the RPG campaign notes are
  the obvious candidates.
- **Org to markdown and plain text.** `-t markdown` and `-t plain`
  would let notes move into the markdown projects, or be read and
  mailed as text, with podoc's grid and pipe tables and wrapping.
- **The rest of podoc applies.** Templates, `--code-style`
  highlighting (the files' languages are mostly bash and Emacs Lisp:
  `PdCode` knows bash; Emacs Lisp would need a list, or a user's
  `--code-keywords` file), mermaid
  blocks if any appear, images in ms, the native filters.
- **A third reader tests the design.** A third input syntax over the
  same AST, writers and passes would show what `PdMdBase` and
  `PdShared` should really hold, and may find writer bugs that
  markdown and rST input never reach (`SmallCaps` in headings, `Div`
  around tables).
- **Completeness against pandoc.** Org would be podoc's third
  reader, after markdown and rST.

## 7. The writer

pandoc also writes Org (`Writers/Org.hs`, 676 lines). No build of the
user's writes Org, and the user edits Org in Emacs, so an Org writer
is not proposed. It would go to "Later", as the rST writer did
(decision 19).

## 8. Size

| | Haskell (code lines) | Oberon |
|---|---|---|
| markdown reader | `Markdown.hs` 2,375 (all lines) | 5,506 |
| rST reader | `RST.hs` 1,876; 1,517 code | `PdRst` + `PdRstInline` 4,717 (3.1 per code line) |
| Org reader, tier B | 3,694 in 10 modules; 2,914 code | estimate 7,000 to 9,000 |
| Org reader, tier A | about half of `Org/` | estimate 3,500 to 4,500 |

The tier B estimate applies a little less than rST's ratio, for the
same reuse (the buffer, text building, identifiers, the post-parse
passes). Against that, Org needs parts rST did not: the document-tree
pass, the export settings, and whatever of the LaTeX reader and
texmath it must imitate (§9). podoc is 33,675 lines of Oberon today:
tier B adds 20 to 27%, the largest addition yet; tier A 10 to 13%.

## 9. Risks

- **The LaTeX and texmath dependency.**
  - To match pandoc, the reader must know where a LaTeX command or
    environment ends, as pandoc's LaTeX reader decides it, and which
    commands texmath turns into inlines (`\textbf`, `\emph`, ... into
    `Strong`, `Emph`) and which it leaves raw (`\sqrt`, `\frac`).
  - podoc's markdown reader already reads raw TeX in its general form
    only, and docs/user/differences.md lists the commands pandoc's
    LaTeX reader reads specially as a difference. Org would need
    more of that, or more listed differences.
  - The user's files use no LaTeX commands and no entities (§2.3), so
    tier A avoids this; tier B cannot.
- **Entities.** Org entities come from texmath's MathML entity map,
  a different and larger table than podoc's HTML entities
  (`PdEntities`). It is data, but it must be copied exactly.
- **The document-tree pass.** TODO keywords, tags, priorities,
  planning, drawers, archived and `COMMENT` trees, select and exclude
  tags and `H:` all act after the headlines are parsed, and
  `#+OPTIONS` can appear anywhere in the file yet govern all of it.
  The reader needs a pass over the whole tree, with pandoc's order of
  effects; mistakes show far from their cause.
- **Emphasis.** Org's emphasis has its own pre- and post-character
  rules, one-line limits and no nesting of the same marker, unlike
  markdown's delimiter runs. pandoc's rules approximate Emacs's
  `org-emphasis-regexp-components`; podoc must follow pandoc's, not
  Emacs's, and the user's notes (389 lines of bold, 595 of verbatim)
  will exercise them heavily.
- **pandoc, not Emacs.** pandoc's reader differs from Org's own
  exporter in many places (timestamps as text, clocktables as divs,
  what is dropped). The user reads these files in Emacs, so pandoc's
  output may surprise them. As with rST, the rule would be to match
  pandoc 3.14.
- **3.14, not 3.10.** The oracle is pandoc 3.14; this research read
  the 3.10 source, and the 3.14 source is now beside it. The
  fixtures must come from running 3.14. The rST reader met this already
  (5957da0).
- **Private test data.** The best corpus is the user's notes, which
  must not be copied into the repository. Case tests would have to be
  written fresh, from pandoc's test files and from constructs, not
  from the notes; the corpus comparison stays a local script, as
  `tools/bench` is.
- **Large files.** A 490 KB file, at pandoc's 172 MB, would test
  podoc's memory use (docs/developer/memory-use-problem.md) and the
  `LONGINT` indexing under `-O2`.
- **No user to drive it.** With no build needing Org, there is no
  document to say when the reader is good enough, and the scope rule
  says features come from the user's documents. Tier B in particular
  would be built for pandoc's tests alone.
- **Growth.** 7,000 to 9,000 more lines to keep working under both
  size models and on the BSDs, for an unused input.

## 10. A possible plan

If the user wants the reader, as a Phase 26:

1. **26.1, blocks:** headlines, paragraphs, lists with checkboxes,
   comment and fixed-width lines, rules, source, example and quote
   blocks; `-f org` in `PdOptions` and `podoc.Mod`.
2. **26.2, inlines:** emphasis, verbatim and code, links and images,
   targets, sub- and superscripts, special strings, math.
3. **26.3, tables and dynamic blocks:** Org tables with alignment
   cookies, `#+TBLFM`, `#+CAPTION`, `#+NAME`, figures, clocktables.
4. **26.4, the tree and metadata:** TODO keywords, tags, drawers,
   planning, `:CUSTOM_ID:`, the keywords, `#+OPTIONS` as the files use
   it, `-s`. At this point tier A is done: the 663 files match
   pandoc's JSON, checked by a local script.
5. **26.5 onward, tier B, only if decided:** footnotes, includes,
   macros, citations, export blocks and snippets, the remaining
   blocks, LaTeX fragments and entities, the rest of `#+OPTIONS` and
   the tree options, held to pandoc's Org tests.

Each step with case tests in `test/cases`, under both models, and the
differences in docs/user/differences.md.

## 11. Questions for the user

Answered on 2026-11-26 (PLAN.md's decisions 55 to 59): 1, yes;
2, all of pandoc's reader (tier B); 3, LaTeX commands kept raw and
listed as a difference, entities read as pandoc reads them (from
`PdEntities`, the same 2,125 names as texmath's table, six of them
taken from texmath); 4, yes; 5, Later.

1. **Should podoc read Org at all?** Nothing the user builds needs
   it (§2.2). Is publishing notes or READMEs with podoc wanted
   enough to add 10 to 27% to podoc?
2. **If so, which tier?** A, what the 663 files use, or B, all of
   pandoc's reader with its tests, as decision 20 chose for rST?
3. **LaTeX fragments and entities.** In tier B, imitate pandoc's LaTeX
   reader and texmath for them, or keep every command raw and list
   the difference?
4. **`--unknown=warn|error` for Org.** Should podoc report what the
   Org reader drops (drawers, planning, unknown keywords), as decision
   22 does for rST?
5. **An Org writer** stays in "Later" (§7)?

## 12. Sources consulted

- pandoc 3.10 source: `src/Text/Pandoc/Readers/Org.hs` and `Org/*.hs`,
  `test/Tests/Readers/Org/`, `test/command/*.md`,
  `test/org-select-tags.org`, `test/Tests/Old.hs`.
- pandoc 3.14 (`~/.cabal/bin/pandoc`): `--list-extensions=org`, and
  runs on sample files and the user's 663 files.
- podoc at 21cc5ee: `src/PdOptions.Mod`, `src/podoc.Mod`,
  `src/PdRst.Mod`, `src/PdMdInline.Mod`, docs/user/differences.md,
  docs/research/rst-implementation.md, PLAN.md's decisions.
- The user's `.org` files under `~/Repos` and `~/current`, makefiles
  and scripts, `~/Repos/tkurtbond.github.io/conf.py` and `~/.emacs`,
  searched with `grep`, never changed.
