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
- Output: HTML5, `ms`, ConTeXt, markdown, and JSON (pandoc's AST, as
  the test oracle) (§3.2).
- PDF through `pdfroff`, `groff` or `context` (§7).
- The command-line options the user's GNUmakefiles pass to pandoc, so
  that `make PANDOC=podoc` works (§2, §4).
- Built-in equivalents of `subs.lua`, `strip-comments.lua`,
  `general.lua`, `toc-columns.lua`, `combine-docs.lua` and
  `pandoc-include` (§4, §5).
- Output equivalent to pandoc 3.10's (decision 3): the same AST, and
  writer output that gives the same PDF or rendered HTML.

Not in scope: other input formats, reStructuredText included; grid
tables; citations; output wrapping; mermaid
(decision 4); Lua filters (decision 6); VAX/VMS (decision 1).

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

## Phase 11: The command line

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

## Phase 12: Includes

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

## Phase 13: Native filters

### Phase 13.1: The filter mechanism

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

### Phase 13.2: `subs` and `strip-comments`

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

### Phase 13.3: `general`

- The Div and Span rules of §4.3 for HTML, ms and ConTeXt, written as
  raw blocks and inlines, with the same warnings on standard error.
  For the markdown writer, Divs and Spans are left alone.

As done: for the markdown writer too, `general` does what general.lua
does there (pandoc runs it for every writer): `for-format` Divs
without `markdown` are dropped, and the Span messages are printed.
All its messages go to standard error, the Spans' first
(docs/user/differences.md).

### Phase 13.4: `toc-columns` and `combine-docs`

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

## Phase 14: PDF output

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

## Phase 15: The proof of concept, finished

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

## Later, not scheduled

- Full YAML through polibfyaml, as `make YAML=libfyaml` (decision 2).
- Embedded Lua 5.4 and a `pandoc` module written in Lua (§8), if a
  filter appears that native code does not cover (decision 6).
- JSON filters: a JSON reader for the AST and `--filter prog` over
  standard input and output (§8.4).
- Output wrapping at `--columns` as pandoc's `doclayout` does.
- Grid tables, in the reader and the markdown writer; pipe tables in
  the markdown writer (written as HTML for now).
- The markdown reader, not needed by the user's documents so far:
  the `%` title block; raw TeX blocks, environments, macros and the
  commands pandoc's LaTeX reader reads specially; citations and
  example references; wikilinks and base64 data URIs; table cells
  that hold blank lines.
- Known gaps in the markdown reader: a note referenced twice shares
  its blocks (only the JSON writer reads them so far, so nothing
  shows); compactify runs before implicit figures exist; the
  contents of Strikeout, Quoted and Link are not trimmed again after
  resolving; character widths for tables (`realLength`) are an
  approximation of pandoc's `charWidth` (2 for East Asian wide and
  full-width, 0 for combining marks, 1 otherwise).
- Citations, `--citeproc`.
- Image conversion for ConTeXt beyond SVG.
- The ms writer: TeX math to `eqn` (texmath's `writeEqn`), and
  syntax highlighting.
- Templates: the pipes `left`, `right` and `center` (block layout);
  the `meta-json` variable; `--variable-json`; `--data-dir`; the
  "expecting ..." part of template error messages.

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
