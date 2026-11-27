# podoc and BBCode: scope, possibilities and risks of a BBCode writer

Research done 2026-11-26. The question is whether podoc should write
BBCode, the markup of web forums (`-t bbcode` and its variants), as
pandoc does. It covers what pandoc's writer does, whether the user's
documents need it, what it would take in podoc, and what could go
wrong.

Sources:

- pandoc 3.14's source: `src/Text/Pandoc/Writers/BBCode.hs`, read in
  full, `data/templates/default.bbcode`, `src/Text/Pandoc/Extensions.hs`,
  `src/Text/Pandoc/Writers/Shared.hs` (`unsmartify`),
  `src/Text/Pandoc/Logging.hs`, the MANUAL's list of formats, and the
  tests: `test/Tests/Writers/BBCode.hs`, `test/writer.bbcode` and
  `test/tables.bbcode`. pandoc 3.10's writer was compared with 3.14's;
  they are the same.
- The installed pandoc 3.14 (`~/.cabal/bin/pandoc`), run on small
  test inputs, on `test/testsuite.native` and on the user's files.
- The forum documentation the MANUAL links to for each flavour
  (bbcode.org, FluxBB through the web archive, Hubzilla, Steam,
  phpBB and xenForo). These were not fetched; the mappings below are
  read from the writer.
- podoc at 8c04ef8.
- The user's GNUmakefiles under `~/current` that mention BBCode, the
  Perl script one of their rules runs, and the reStructuredText files
  beside them. These were only read.

Section 4 lists the experiments. They were run in
`/usr/local/sw/tmp/claude-podoc-bb`, which has since been removed.

## 1. Summary

- **pandoc has had a BBCode writer since 3.8.3** (2025-12-01, pull
  request #11242). It has six flavours: `bbcode` (the "official"
  one, after bbcode.org), `bbcode_steam`, `bbcode_phpbb`,
  `bbcode_fluxbb`, `bbcode_hubzilla` and `bbcode_xenforo`. Each is a
  record of renderers in one 1,089-line module; the flavours share
  most of them and differ in headers, lists, code, images, links,
  tables, spoilers and the like (section 2.3). The MANUAL lists them
  without a stability note, but the writer is new and its mappings are
  pandoc's own reading of each forum's documentation.
- **It is a simple writer.** There is no wrapping (`--wrap` and
  `--columns` are ignored), no escaping of text, no metadata (the
  default template is `$body$`), and the only extension is
  `east_asian_line_breaks`. Typographic characters are always made
  plain ASCII by `unsmartify`, and `+smart` is refused (exit 23).
- **It drops content quietly.** A table with any cell that is not a
  single plain block, raw content in another format, a block quote
  inside a list for FluxBB, and an image for Steam are not rendered.
  pandoc says so only in INFO messages, which appear only with
  `--verbose`. A title or subtitle in the metadata (an rST document's,
  for one) is lost even with `-s`, because the template has no
  `$title$`.
- **The user's builds do not use pandoc's writer.** Six of the user's
  GNUmakefiles define a list of BBCode output files, and two of them
  have a rule to make one: from docutils' HTML, with a small
  third-party Perl script (section 3). pandoc's writer, from the same
  rST, gives different markup for headings and emphasis, and real
  tables where the script gives `[code]` blocks. Replacing the script
  would be the user's choice; their projects are read only to podoc.
- **On the user's rST files pandoc's writer works.** Of 28 files beside
  those makefiles, pandoc converts 26 cleanly; one warns of a
  reference not found (a reader warning, not the writer's), and one
  has a table the writer drops. podoc's rST reader already gives
  pandoc's JSON for all 28, so a podoc writer that matched pandoc's
  would give the same BBCode.
- **The work is small.** A module of perhaps 500 to 700 lines of
  Oberon, smaller than `PdMs` or `PdMom`, built on what podoc already
  has: `PdLayout` (with no wrapping, it only stacks blocks), `PdShared`'s
  table, list and text helpers, `PdTemplate`, the markdown writer's
  unsmartify, and `PdOptions`' format checks. pandoc's fixtures and
  27 unit cases give the tests. Each flavour adds a little code and
  a little testing; all six are perhaps one and a half times the work
  of the official one alone.
- **The plan does not schedule it,** and no document the user builds
  needs it today. Under AGENTS.md's scope rule it belongs in PLAN.md's
  "Later" unless the user wants it now (section 8).

## 2. pandoc's BBCode writer

### 2.1 Shape

`Writers/BBCode.hs` defines a `FlavorSpec`: one renderer for each
kind of block and inline that differs between forums, and a few
settings (how a horizontal rule is written, whether `mailto:` links
become `[email]`). The six flavours are six values of that record,
mostly the official one with a few fields replaced. The writer builds
a doclayout `Doc` and renders it with `render Nothing`, so lines are
never broken. `SoftBreak` becomes a space and `LineBreak` a new line.

The writer runs in a reader monad that carries the flavour and a
state with the notes collected so far. Notes are numbered when they
are met: the number is taken before the note's own contents are
rendered, so a note inside a note can get the number of its parent's
successor out of order. pandoc's tests do not cover that case.

Text is written as it is: `Str "[b]x[/b]"` comes out as bold markup,
not as the characters. BBCode has no standard escape; some forums
have `[noparse]` or `[plain]`, and the writer uses none of them for
text.

### 2.2 Options, extensions and the template

- `data/templates/default.bbcode` is the single line `$body$`. With
  `-s`, metadata is still not written. A custom template can use
  `$title$` and the rest as with any writer.
- `Extensions.hs` gives the BBCode formats only
  `east_asian_line_breaks`. `-t bbcode+smart` ends with exit 23.
- `unsmartify` is applied always: curly quotes become straight ones,
  the ellipsis three full stops, an en dash `--` and an em dash `---`
  (with `old_dashes`, `-` and `--`).
- `--wrap` and `--columns` are accepted and ignored.
- pandoc does not choose BBCode from an output file's extension:
  `-o x.bbcode` warns and writes HTML. podoc's extension table
  behaves the same way already.
- Content the writer cannot render is reported as `[INFO] Not
  rendering` followed by Haskell's `show` of the element, at INFO
  level, so only with `--verbose`. podoc already documents
  (`docs/user/differences.md`) that it does not print these lines.

### 2.3 From the AST to BBCode

| Element | Official | Differences by flavour |
|---|---|---|
| Header | 1 `[u][b]..[/b][/u]`, 2 `[b]`, 3 `[u]`, 4–6 plain | Steam `[h1]`–`[h3]`; Hubzilla `[h1]`–`[h6]`; xenForo `[heading=n]` |
| Bullet list | `[list]` with `[*]` | Hubzilla `[ul]` |
| Ordered list | `[list=1]`, `=a`, `=A`, `=i`, `=I` by style | Steam `[olist]`; FluxBB `=1` or `=a` only; xenForo `=1` only; Hubzilla `[ol]` for the default and example styles |
| Definition list | the term, then its definitions as a bullet list | Hubzilla `[dl terms="b"]` with `[*= term]` |
| Code block | `[code=lang]` | FluxBB `[code]` without the language |
| Inline code | the text alone | Steam `[noparse]`; Hubzilla `[code]`; xenForo `[icode]` |
| Emphasis, strong, underline | `[i]`, `[b]`, `[u]` | |
| Strikeout | `[s]` | Steam `[strike]` |
| Superscript, subscript, small caps, citation | contents only | |
| Quoted | straight quotes around the contents | |
| Math | as code with the class `latex`: `$..$` inline, `$$..$$` as a block | |
| Link | `[url]` when the text is the URI, else `[url=..]` | `mailto:` becomes `[email]`, except for Steam and Hubzilla |
| Image | `[img alt=.. title=.. width=.. height=..]` with integer sizes | phpBB `[img]`; FluxBB `[img=alt]`; Steam not rendered; xenForo width as a percentage only |
| Table | caption above, `[table][tr][th]`/`[td]` | phpBB and FluxBB: the caption and "(TABLE)"; any flavour: dropped if a cell is not simple |
| Block quote | `[quote]` | FluxBB drops one inside a list |
| Horizontal rule | `* * *` | `[hr]` for Steam, Hubzilla and xenForo |
| Notes | `(n)` in the text, the notes after the body below a rule | |
| Div, Span | classes and attributes `left`, `center`, `right`, `spoiler`, `size`, `color`, `font`, as each forum supports them | e.g. xenForo `[ispoiler]` for a span, `[spoiler=..]` for a div |
| Raw | `bbcode` raw content as it is | other formats dropped, with INFO |

An image size that is not a plain integer number of pixels, such as an
rST `:width: 100` read as a percentage, is dropped for the official
flavour; xenForo keeps only percentages.

## 3. The user's use of BBCode

Under `~/current`, six GNUmakefiles define a `BBCODE_OUTPUT_FILES`
variable: in projects on health, in four game projects, and in a
reStructuredText tooling directory. Only two of them have a rule that
makes `.bbcode` files, and the rule is the same in both: `%.bbcode`
from `%.html` with `./htmltobb.pl`.

`htmltobb.pl` is a third-party Perl script from 2007 under a BSD
licence, 114 lines, the same in both directories. It rewrites HTML to
BBCode with regular expressions. It is applied to docutils' HTML (the
makefiles build HTML with docutils, not pandoc), and it:

- writes every heading as `[b]`, and emphasis as `[b]` too;
- converts unordered lists only;
- writes tables as `[code]` blocks.

One project has 11 `.bbcode` files, all from 2023-12-02; nothing
newer was found. The four game directories together hold 28 `.rst`
files.

So the user has wanted BBCode from their rST, but through docutils and
a script, and not recently. Nothing in their pandoc builds or filters
asks for `-t bbcode`. Which forum the files were for is not recorded
in the makefiles.

## 4. Experiments

All with the installed pandoc 3.14, in
`/usr/local/sw/tmp/claude-podoc-bb`.

1. **The fixtures.** `pandoc -s -f native -t bbcode
   test/testsuite.native` reproduces `test/writer.bbcode` (729
   lines); `test/tables.bbcode` (60 lines) is the official flavour's
   output for `test/tables.native`.
2. **Dropped content in the test suite.** With `--verbose`, the test
   suite gives 24 "Not rendering" messages for each flavour and 25 for
   FluxBB (its extra one a block quote in a list).
3. **Small probes** of each feature in section 2.3: headers, lists,
   code, links, `mailto:`, images with sizes, spans and divs with
   `spoiler`, `color` and `size`, math, notes, horizontal rules, raw
   content and `+smart` (exit 23). An rST document's title was lost
   with `-s`. An rST image `:width: 100` was dropped.
4. **The user's 28 rST files**, `pandoc -f rst -t bbcode --verbose`:
   26 with no message, one with a "Reference not found" warning from
   the reader, one with a table not rendered. Together 163 KB of
   BBCode. The tags used most were `[*]` (199), `[b]` (197),
   `[url=` (189), `[u]` (89), `[td]` (83), `[list]` (71), `[i]` (35)
   and `[tr]` (26); `[quote]`, `[table]`, `[url]` and `[list=` a
   few times each. None of the 28 has a title or subtitle in its
   metadata, so the title loss does not affect them.
5. **podoc's reader on the same files.** `podoc -f rst -t json`
   equals pandoc's JSON for all 28.

## 5. The writer in podoc

### 5.1 Shape

- A module `PdBBCode`, with a flavour record in the style of pandoc's
  (a few procedure variables and settings) or, simpler in Oberon, a
  flavour number and `CASE` in the handful of procedures that differ.
- `-t bbcode`, `bbcode_steam`, `bbcode_phpbb`, `bbcode_fluxbb`,
  `bbcode_hubzilla` and `bbcode_xenforo` in `PdOptions`: the writer
  names, the extension check (only `east_asian_line_breaks`; `+smart`
  refused with 23), and no extension mapping for `-o`.
- `data/templates/default.bbcode`, `$body$`, through `PdTemplate`.
- Output through `PdLayout` with no wrapping: blocks separated by
  blank lines, list items and table rows on their own lines. The
  notes are collected while the body is written, as `PdMs` and the
  markdown writer collect theirs.
- Tables through `PdShared`'s simple-rows view; a table whose cells
  are not all simple is dropped as pandoc drops it.
- `unsmartify` taken from `PdMdWriter`, where it is part of writing a
  `Str` together with markdown's escaping (around line 228), and moved
  to `PdShared` so that both writers use it.
- Strings built with buffers and `Ropes.FromSubchars`, not a character
  at a time (the lesson of change 9 in
  `docs/developer/performance.md`).

### 5.2 Tests

- Case tests in `test/cases`: the test suite and the tables in each
  flavour, from pandoc's fixtures and pandoc 3.14's output.
- Unit or case tests from the 27 cases in `Tests/Writers/BBCode.hs`.
- A corpus check like `tools/orgcorpus`, run where pandoc is
  installed: the user's 28 rST files, byte for byte against pandoc.
- Both size models, as for every writer.

### 5.3 Effort

The official flavour is the bulk of it: perhaps two or three working
sessions, including the tests. The other five flavours are mostly
small replacements, but each needs its own expected output for the
test suite and probes for its special cases (Hubzilla's definition
lists, xenForo's percentages, FluxBB's dropped quotes). Documentation
is a section in `docs/user/podoc.md` and any differences in
`docs/user/differences.md`.

## 6. What a BBCode writer would give

- Forum posts made directly from the user's markdown, rST or Org,
  without docutils and a Perl script, on any system podoc builds on.
- Better markup than `htmltobb.pl`: real headings (for the forums
  that have them), ordered lists, tables as tables, links kept.
- A seventh writer that costs little to keep once its tests exist,
  since pandoc's writer has not changed between 3.10 and 3.14.

## 7. Risks

- **Silent loss of content.** Tables with complex cells, raw content
  in other formats, Steam's images, FluxBB's block quotes in lists and
  the title are dropped, and only `--verbose` says so, in a form podoc
  does not reproduce. Matching pandoc means matching that. podoc
  could warn where pandoc only informs, but that is a difference to
  decide and record.
- **No escaping.** Text that looks like a tag becomes one. In forum
  posts about BBCode, or with square brackets in the text, the output
  may not show what the source says. pandoc does the same.
- **Six flavours.** Each multiplies the expected files and the chance
  of a mismatch, and only pandoc can say what is right for each.
- **An unsettled upstream.** The writer is a year old; its flavours
  are pandoc's reading of six forums' documentation, and a later
  pandoc may change them. Each pandoc upgrade would mean re-checking
  the expected files, as for the other writers.
- **No offline check of the result.** Whether a forum shows the output
  as intended can only be seen by posting it; the tests can only
  compare with pandoc.
- **Not what the user's builds use.** The output is not
  `htmltobb.pl`'s; anyone used to it would see headings as `[u][b]`
  and emphasis as `[i]`. Whether that is better depends on the forum.
- **Scope.** It is not in the plan and no current build needs it; time
  spent on it is not spent on PLAN.md's "Later" items.

## 8. Questions for the user

1. Should a BBCode writer be added now, or recorded in PLAN.md's
   "Later"?
2. Which forum or forums do you post to? That decides which flavours
   matter.
3. All six flavours, as pandoc has, or only the ones you use (an
   unknown flavour then exiting 22, as an unknown format does)?
4. Should podoc warn, rather than stay silent without `--verbose`,
   when it drops a table or other content, as a recorded difference
   from pandoc?
5. Is the aim to replace `htmltobb.pl` in your makefiles (a change you
   would make), or only to have the format available?
