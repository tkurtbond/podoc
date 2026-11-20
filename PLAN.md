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

Not in scope: other input formats, reStructuredText included; grid,
simple and multiline tables; citations; output wrapping; mermaid
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
- **Text is held in Ropes** (`~/Repos/Oberon/Ropes`, §12.1): string
  fields of the AST, and all output. Writers build their output by
  concatenation, templates splice the body in, and the result is
  written leaf by leaf with `Ropes.WriteFile`, never flattened. The
  reader works on the input as one flat `ARRAY OF CHAR`, for speed,
  and makes Ropes only for the text it keeps. Confirmed or revised in
  Phase 2.1.
- **Modules** (names prefixed `Pd` to stay clear of the runtime's
  global module namespace; to be confirmed in Phase 1):
  - `PdAst`: the AST, constructors, a generic walk.
  - `PdJson`: the JSON writer.
  - `PdYaml`: the YAML subset.
  - `PdMdBlocks`, `PdMdInlines`, `PdMarkdown`: the reader.
  - `PdIdent`: automatic identifiers.
  - `PdTemplate`: the doctemplates language.
  - `PdHtml`, `PdMs`, `PdContext`, `PdMdWriter`: the writers, with
    shared helpers in `PdWrite`.
  - `PdInclude`: `!include`.
  - `PdFilters`: the native filters.
  - `PdPdf`, `PdRun`: temporary directories and running engines.
  - `PdOptions`: the pandoc-compatible command line.
  - `podoc`: the main module.
- **Errors** are reported with the file name and line, and the program
  halts with a code in its own range (below).

## Halt codes

podoc is an application, so its codes start at 100, as in the other
Oberon projects: the runtime uses 10..20 and the po* libraries 61..99.
The table is kept in AGENTS.md as codes are assigned.

## Testing

- `make test` builds and runs `test/<Name>.Mod` unit tests, which print
  `ok   - ` and `FAIL - ` lines, and the case tests: each
  `test/cases/<name>.md` is converted by podoc and compared with the
  committed `<name>.json`, `<name>.html`, `<name>.ms`,
  `<name>.context` and `<name>.markdown` that exist beside it.
  `make test` does not need pandoc.
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

## Phase 1: The repository and the skeleton

### Phase 1.1: Repository files and the build

- `README.md`, `LICENSE` (BSD 3-Clause, as the other Oberon projects),
  `.gitattributes`, `.gitignore`.
- `GNUmakefile`: `make` builds `podoc` under `-O2` and `-OC` in
  `build/O2` and `build/OC`; `make test`; `make clean`.
- Check that each dependency (ArgParser, pounicode, Ropes) is installed
  for both size models, and record in AGENTS.md how to install a
  missing one.

### Phase 1.2: A program that runs

- `podoc` reads files named on the command line (or standard input),
  joins them as pandoc does (with a blank line between), and writes
  them unchanged to `-o` or standard output.
- `--version` and `--help`.
- A first case test, to prove the harness.

## Phase 2: The AST and the JSON writer

### Phase 2.1: `PdAst`

- Types for every block and inline constructor of pandoc-types 1.23
  that §3.1 needs, plus the rest as stubs that the JSON writer can
  still print.
- `Attr`, `Meta`, `MetaValue`; lists of blocks and inlines.
- A walk with callbacks for blocks and inlines, in pandoc's order, to
  serve the filters.
- Settle the use of Ropes (Design): measure building and writing a
  document the size of the largest Lost-Worlds build; record the
  result here.

### Phase 2.2: `PdJson` writer

- Write `-t json` exactly as pandoc does: compact, field order, the
  `pandoc-api-version`, string escapes (pandoc escapes only what JSON
  requires), and numbers.
- Unit test by building small ASTs by hand and comparing with
  pandoc's JSON for the same documents.

## Phase 3: The markdown reader, blocks

### Phase 3.1: Lines and the block structure

- Read UTF-8 text into lines, tabs expanded to four columns as pandoc
  does, and keep line numbers for messages.
- Paragraphs, ATX headers, setext headers, horizontal rules, block
  quotes (with laziness), indented and fenced code blocks (with
  attributes and info strings), blank lines.

### Phase 3.2: Lists

- Bullet and ordered lists, with pandoc's rules: the four-space rule
  for continuation, lazy continuation, tight and loose lists, list
  styles and delimiters (`1.`, `1)`, `(1)`, `#.`, `a.`, `i.`), starting
  numbers, nesting.
- Cases for each rule, taken from pandoc's `testsuite.txt` and the
  user's `Includes/` stat blocks.

### Phase 3.3: Raw blocks, HTML blocks and line blocks

- ```` ```{=format} ```` raw blocks.
- HTML blocks kept as `RawBlock "html"`.
- Line blocks (`| `).

## Phase 4: The markdown reader, inlines

### Phase 4.1: Text, escapes and code

- `Str`, `Space`, `SoftBreak`, `LineBreak` (two spaces and backslash
  newline), backslash escapes, entities, inline code with attributes,
  raw inlines `` `x`{=ms} ``.

### Phase 4.2: Emphasis

- `*` and `_` emphasis and strong emphasis, with pandoc's rules for
  intraword underscores and for nesting, and `~~` strikeout, `^`
  superscript and `~` subscript.

### Phase 4.3: Links and images

- Inline links and images, reference links and images (definitions
  collected in a first pass over the whole document), autolinks,
  `{width=...}` attributes, implicit header references.
- An image alone in a paragraph becomes a `Figure`, as pandoc 3 does.

### Phase 4.4: Smart punctuation

- Curly single and double quotes (`Quoted`), apostrophes, `--`, `---`,
  `...`, with pandoc's rules for contractions and for quotes next to
  punctuation. `test/command/smart.md` is the reference.

### Phase 4.5: Identifiers

- `PdIdent`: pandoc's `auto_identifiers` with Unicode letters (using
  pounicode), duplicates numbered `-1`, `-2`, and explicit `{#id}`
  header attributes.

### Phase 4.6: The rest of the extensions

- Pipe tables, with alignment, captions and inline content in cells.
- Footnotes, inline and by reference.
- Fenced divs (`:::`) and bracketed spans (`[text]{.class}`), with
  attributes, nesting, and the setext and fenced-div interaction
  (`test/command/setext-fenced-div.md`).
- Definition lists.
- Header attributes (`{#id .class key=val}`).
- TeX math passed through as `Math` (no parsing of its content).
- Acceptance: every markdown file of Lost-Worlds and
  Galactic-Bounty-Hunters gives the same JSON as pandoc.

## Phase 5: YAML metadata

### Phase 5.1: `PdYaml`

- The subset of §9: block maps and sequences, flow collections of
  scalars, plain, quoted and block scalars, comments. Anything else is
  an error naming the construct and the line, and suggesting the
  libfyaml build once it exists.
- Unit tests against cases from `yaml-metadata-blocks.md` and the
  user's metadata.

### Phase 5.2: Metadata in the document

- YAML blocks anywhere pandoc accepts them, merged in order.
- String values parsed as markdown (`MetaInlines` or `MetaBlocks`),
  booleans as `MetaBool`, as pandoc does.
- `-M key=value` (repeatable, building lists) and `--metadata-file`.

## Phase 6: Templates

### Phase 6.1: `PdTemplate`

- The language of §6: variables and fields, conditionals, loops with
  separators, comments, `$$`, partials, the pipes needed, and
  indentation of multi-line values.
- Unit tests from doctemplates' own test cases, where they fit.

### Phase 6.2: Template lookup and variables

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

## Phase 7: The HTML writer

### Phase 7.1: Blocks and inlines

- Every element of §3.3, escaping, attributes, figures, tables with
  alignment, footnotes at the end.
- Raw `html` passed through; other raw formats dropped.

### Phase 7.2: Standalone HTML

- `-s` with the default template and `--css`; `--toc` (and
  `--toc-depth`); `--number-sections`.
- Acceptance: the user's HTML targets are equivalent to pandoc's.

## Phase 8: The ms writer

### Phase 8.1: Blocks and inlines

- Every element of §3.3: escapes (`\&` before `.` and `'`, `\e`), the
  special characters, smart quotes and dashes, font changes, lists,
  block quotes, rules, line blocks, footnotes, images.
- Tables through `tbl`.

### Phase 8.2: Standalone ms

- The default template and the user's `tkb.ms` and `statement.ms`.
- The title block, authors, abstract, date; `--toc` (`.TC`);
  `--number-sections` (`.NH`).
- Acceptance: the ms for the user's documents is equivalent to
  pandoc's.

## Phase 9: The ConTeXt writer

### Phase 9.1: Blocks and inlines

- Every element of §3.3: escapes, sections, lists, tables
  (`xtable`), block quotes, line blocks, images, footnotes, links.

### Phase 9.2: Standalone ConTeXt

- The default template and the user's `tkb.context` and
  `statement.context`, with their variables.
- Acceptance: the ConTeXt for the user's documents is equivalent to
  pandoc's.

## Phase 10: The markdown writer

pandoc's is 1,928 lines of Haskell (`Writers/Markdown.hs` and
`Writers/Markdown/`); podoc's should be 1,200 to 1,500 lines of
Oberon (decision 7).

### Phase 10.1: Blocks and inlines

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

### Phase 10.2: Standalone markdown and the round trip

- `-s` writes the metadata as a YAML block (so `PdYaml` gains a
  writer), with the default markdown template.
- The round-trip test: for every case and every user document, the
  JSON of podoc's markdown, read again, equals the JSON of the
  original, both by podoc and by pandoc.
- Acceptance: the `-whole.md` targets of Lost-Worlds and
  Galactic-Bounty-Hunters (after Phase 12) read back to the same AST
  as pandoc's `-whole.md`.

## Phase 11: The command line

### Phase 11.1: `PdOptions`

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

## Phase 12: Includes

### Phase 12.1: `PdInclude`

- `!include path` and `` !include`incrementSection=n` path ``, as §5:
  globs in sorted order, recursion, paths relative to the including
  file, metadata merged with the outer keys winning, header levels
  shifted, relative image paths rewritten, cycles detected.
- The other `pandoc-include` keys rejected with a message.
- Run when `-F pandoc-include` (or `--filter pandoc-include`) is given,
  so that output without it still matches pandoc's.
- Acceptance: the user's `-whole.md` targets (Phase 10.2).

## Phase 13: Native filters

### Phase 13.1: The filter mechanism

- `--lua-filter` and `-F` options become a list of passes, run in
  command-line order; a pass is chosen by the filter's base name.
  `pandoc-mermaid-selenium-filter` warns and does nothing
  (decision 4). Any other filter is an error naming it.

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

### Phase 13.3: `general`

- The Div and Span rules of §4.3 for HTML, ms and ConTeXt, written as
  raw blocks and inlines, with the same warnings on standard error.
  For the markdown writer, Divs and Spans are left alone.

### Phase 13.4: `toc-columns` and `combine-docs`

- `toc-columns`: the raw ConTeXt block, placed as §2.1 says.
- `combine-docs`: the digest of §2.1, reading each file with the
  reader.
- Acceptance: the Lost-Worlds GNUmakefile's targets, run with
  `PANDOC=podoc`, produce intermediate HTML, ms and ConTeXt equivalent
  to pandoc's.

## Phase 14: PDF output

### Phase 14.1: `PdRun`

- Make and remove a temporary directory under `TMPDIR`.
- Run a program with arguments, standard input from a file or buffer,
  standard output to a file; report its exit status. Through pounix
  without a shell; `Platform.System` with quoting only if pounix is
  missing on a BSD.

### Phase 14.2: The engines

- `pdfroff`, `groff` and `context` with the arguments of §7, plus
  `--pdf-engine-opt` and `papersize`.
- For ConTeXt: images copied into the temporary directory, SVGs
  converted with `rsvg-convert` when it is present.
- Engine errors shown with the engine's log.
- Acceptance: every PDF target of Lost-Worlds and
  Galactic-Bounty-Hunters builds with `PANDOC=podoc`, and its
  `pdftotext` matches that of pandoc's PDF.

## Phase 15: The proof of concept, finished

### Phase 15.1: Portability

- Build and test on at least one BSD.
- Record what a minimal system needs: poc, the libraries, groff
  and/or ConTeXt.

### Phase 15.2: Installing and documenting

- `make install` (`PREFIX`, as the other projects), and
  `docs/user/podoc.md`: the supported subset, the options, the
  substitutions format, and `docs/user/differences.md`.
- README and AGENTS.md updated.

## Later, not scheduled

- Full YAML through polibfyaml, as `make YAML=libfyaml` (decision 2).
- Embedded Lua 5.4 and a `pandoc` module written in Lua (§8), if a
  filter appears that native code does not cover (decision 6).
- JSON filters: a JSON reader for the AST and `--filter prog` over
  standard input and output (§8.4).
- Output wrapping at `--columns` as pandoc's `doclayout` does.
- Grid, simple and multiline tables.
- Citations, `--citeproc`.
- Image conversion for ConTeXt beyond SVG.

## State

- 2026-11-19: Research done and recorded in
  `docs/research/podoc-scope.md`; this plan written. No code yet.
- 2026-11-20: The user decided the open questions (Decisions). The
  markdown writer became Phase 10, Lua went to "Later", and
  substitutions moved to YAML metadata. Ropes checked: installed for
  poc under `-O2` and `-OC`; a test program built on it ran under
  both (200,000 appends, 600,003 characters, depth 34, written with
  `WriteFile`, in 0.04 s). Phase 1 next.
