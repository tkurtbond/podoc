# Differences from pandoc

Where podoc deliberately, or for now, does not do what pandoc 3.10
does. Output that differs from pandoc's but is equivalent (decision 3
in PLAN.md) is listed by the writer.

## The command line

- An unknown option, or an option missing its argument, ends podoc
  with exit status 2 (ArgParser's), where pandoc's is 6. Every other
  error uses pandoc's exit status: 1 for a file that cannot be read or
  written, 4 for PDF output podoc cannot make or PDF to a terminal,
  6 for a bad `--wrap` or
  `--pdf-engine`, 21 for an input format other than markdown, 22 for
  an unknown output format, 23 for a markdown extension, 43 and 47
  for a PDF engine that fails or is not there, 83 for a filter.
- `--help` lists podoc's options in ArgParser's form, and error
  messages are podoc's own wording, starting with "podoc: ".
- `-t source` writes the input as the reader would see it (joined,
  CRs removed, tabs expanded); pandoc has no such format.
- podoc reads only `markdown`, and turns only `grid_tables` on or
  off (`gutenberg`, which pandoc's reader ignores, it takes and
  ignores): any other extension, such as `-f markdown+smart` or
  `-f markdown-smart`, ends podoc with exit status 23, and `-f rst`, or an input whose extension names another
  format (`.rst`, `.tex`, ...) when there is no `-f`, with 21. Inputs
  and `-o` imply formats as in pandoc, with pandoc's warnings when an
  extension names none.
- podoc writes `html` (`html5`), `ms`, `context`, `markdown`,
  `plain`, `json` and PDF; `-t latex`, or `-o x.tex` with no `-t`, ends it with exit
  status 22. The one writer extension podoc takes is `gutenberg`,
  for `plain` (and for `markdown`, where it does nothing, as in
  pandoc); any other, such as `-t markdown-raw_html`, ends podoc with
  exit status 23. As in pandoc, an extension both enabled and disabled
  (`+gutenberg-gutenberg`) is on.
- `--pdf-engine` takes only `groff`, `pdfroff` or `context` (by base
  name, so a path is allowed); anything else ends podoc with status 6,
  and the message lists only those three. PDF output with neither
  `-t` nor `--pdf-engine`, which pandoc makes with LaTeX and
  `pdflatex`, and PDF from html, end podoc with status 4.
- Filters are not run. `--lua-filter` (`-L`) and `-F`/`--filter`
  name the user's filters, by file name (any directory), and podoc
  runs its built-in code in their place (see Filters):
  `pandoc-include`, given with `-F`, and `subs.lua`,
  `strip-comments.lua`, `general.lua`, `toc-columns.lua` and
  `combine-docs.lua`, given with `-L`. Given with the other option,
  each ends podoc with pandoc's message and status 83.
  `pandoc-mermaid-selenium-filter` is ignored with a warning
  (decision 4). Any other filter ends podoc with status 83.
- A `--wrap` value other than `auto`, `none` or `preserve` gives
  pandoc's message and status, 6.

## Input

- Input that is not valid UTF-8 is read as it is; pandoc reads it as
  Latin-1, with a warning.
- Input file names are not URLs: pandoc fetches `http:` and `https:`
  inputs.

## Includes

`-F pandoc-include` runs podoc's own `PdInclude`, which does what
`pandoc-include` 1.4.4 does with the user's documents. It differs in
these ways:

- An include cycle (a file that includes itself, directly or not) ends
  podoc with status 83 and a message naming the file; pandoc-include
  never ends.
- There are no `[INFO] including file` lines. The warnings and errors
  that remain are pandoc-include's, prefixed `podoc: `.
- Only the `incrementSection` key is supported. The others
  (`startLine`, `endLine`, `snippetStart`, `snippetEnd`,
  `includeSnippetDelimiters`, `xslt`, `dedent`, `format`, `raw`) end podoc with status 83 and a message
  naming the key; a key pandoc-include does not know gets its
  `[Warn] Invalid config key` warning, as there.
- `!include-header`, includes in code blocks, and files whose names say
  they are not markdown end podoc with status 83.
- The metadata options (`include-order`, `include-resources`,
  `include-entry`, `rewrite-path`, `process-path`, `pandoc-options`)
  and the `PANDOC_INCLUDE_*` environment variables are ignored: the
  order is always natural, and image paths are always rewritten.
- An include line holding an inline other than text, spaces, code,
  emphasis, strong emphasis or quotes (a link, say) ends podoc with
  status 83, where pandoc-include renders it as markdown first.
  pandoc-include sees the line as `markdown_strict` writes it, with
  only `\*` and `\_` unescaped; podoc copies that for `[` and `]`, so
  a glob's `[...]` set never matches, as there, but not for the
  rarer escapes.
- Globs follow Python's `glob` (hidden names, `**`, `[...]` sets) but
  `**` stops 256 directories deep. Files are sorted as natsort sorts
  them, digit runs by value, except that names natsort holds equal
  (`x01` and `x1`) are ordered by their bytes, and names are not
  normalized to Unicode NFD first.

## Filters

podoc's built-in filters give the user's Lua filters' output. They
differ in these ways:

- `subs.lua` reads its table from the metadata map `substitutions`
  (decision 5), usually given with
  `--metadata-file=substitutions.yaml`, not from `substitutions.lua`;
  `tools/subs2yaml` converts that file once. With no such map podoc
  ends with status 83 and a message saying so. The values are
  metadata, read as markdown and taken as plain text, so an
  apostrophe in one becomes a curly one unless it has a backslash
  before it. The keys are applied in the byte order of the keys, where
  Lua's order is unspecified; it matters only when one key's text
  contains another's.
- `general.lua` writes its messages (the Span classes unimplemented
  for the format, the note on `.color` in ms) to standard output,
  before the document, and some (Divs left out) to standard error.
  podoc writes them all to standard error, those for Spans first.
- A filter's error ends podoc with status 83 and the filter's message,
  without Lua's line numbers and stack traceback (`combine-docs.lua`
  with no `combine` field, or with a file that is not there).

## The markdown reader

podoc reads the markdown the user's documents use. It does not yet
read:

- table cells that hold blank lines, but for grid tables;
- the `%` title block;
- raw TeX blocks, LaTeX environments and macros, and the commands
  pandoc's LaTeX reader reads specially (podoc keeps every `\command`
  with its options and arguments as a raw TeX inline);
- citations, example references (`@label`), wikilinks and base64
  data URIs.

A table's column widths count characters as pandoc's doclayout does
(its `charWidth` table), but emoji sequences joined by U+200D or
followed by U+FE0F are not counted as one wide character.

## YAML metadata

podoc reads YAML with its own small reader, `PdYaml`, not libyaml.

- Anchors (`&a`), aliases (`*a`), tags (`!x`), directives (`%YAML`)
  and complex keys (`? `) are not read: each is a parse error naming
  the construct.
- A YAML parse error names the file, line and column as pandoc does,
  but the message after that is podoc's own wording, not libyaml's.
  The hint "Consider enclosing the entire field in 'single quotes'"
  is given only for a mapping entry that is badly indented.
- Messages start with "podoc: ".
- `--metadata-file` files are looked for only where named, not also
  in pandoc's data directory.

## Templates

podoc's built-in templates are pandoc 3.10's defaults for `html5`,
`ms`, `context` and `markdown`.

- The pipes `left`, `right` and `center` are not supported: a
  template that uses them does not compile.
- A template that does not compile is reported with the position and
  the unexpected text, as pandoc reports it, but without pandoc's
  "expecting ..." list.
- A template that cannot be found is reported as `Could not find data
  file 'templates/NAME'`; pandoc names the file in its own data
  directory.
- `pandoc-version` is `3.10`, the pandoc that podoc follows.
- The variable `meta-json` is not set, and there is no
  `--variable-json` or `--data-dir`.

## The HTML writer

- Code is not highlighted: podoc writes what `pandoc
  --syntax-highlighting=none` writes.
- TeX math is written as its TeX, escaped, inside `span.math`
  (`\(...\)` and `\[...\]`); pandoc's default output converts it
  with texmath to HTML where it can.
- Output is not wrapped: `--wrap=auto` behaves as `--wrap=none`;
  `--wrap=preserve` keeps the input's soft line breaks.
- The media type of an image or link target (for `video`, `audio` and
  `embed`) comes from podoc's built-in table, made from pandoc's.
- E-mail addresses are not obfuscated (pandoc's default is none too;
  `--email-obfuscation` is not supported).
- The date in `<meta name="dcterms.date">` is normalized with
  pandoc's list of date formats in the C locale (English month
  names), with `%x` and `%D` read as `%m/%d/%y`.
- Raw blocks and inlines are passed through for the formats `html`,
  `html5` and `html4`; every other raw format is dropped.

## The ms writer

- Code is not highlighted. pandoc's ms writer highlights code blocks
  and inline code that name a language even with
  `--syntax-highlighting=none`, writing `\*[NormalTok "..."]`
  strings that are left undefined without the highlighting macros;
  podoc writes the code as plain text.
- TeX math is written as its TeX: `$...$` inline, and `$$...$$`
  inside `.RS 3` ... `.RE` for display math (pandoc's fallback when
  it cannot convert a formula). pandoc converts math with texmath to
  `eqn`: `@...@` inline and `.EQ` ... `.EN`.
- The plain text of a heading in its PDF bookmark (`.pdfhref O`)
  comes from podoc's own approximation of pandoc's plain writer.
- When it writes bookmarks (a PDF engine is set), podoc writes `.br`
  after a heading's text, before its `.pdfhref` lines; pandoc does
  not. groff 1.25's `.SH` and `.NH` hold the heading in a box until
  its line is output, so without the `.br` the `.pdfhref` lines are
  caught in it: each heading is followed by a printed
  `.pdfbookmark ...` line, and no bookmarks are made. The `.br`
  changes nothing with groff 1.23 or 1.24.
- Small caps use Unicode's simple upper-case mapping, one character
  for one.
- Output is not wrapped, as for HTML.
- Raw blocks and inlines are passed through for the format `ms`
  only.

## The ConTeXt writer

- Code is not highlighted. pandoc's ConTeXt writer highlights code
  blocks that name a language even with `--syntax-highlighting=none`,
  writing `\starthighlighting` ... `\stophighlighting`; podoc writes
  `\starttyping` ... `\stoptyping`, as pandoc does for code with no
  language.
- Output is not wrapped, as for HTML.
- Raw blocks and inlines are passed through for the formats `context`
  and `tex` only.

## PDF output

podoc makes PDF as pandoc 3.10 does with `pdfroff`, `groff` and
`context`: the same arguments, `--pdf-engine-opt` and `-V papersize`,
the same messages and exit statuses (43 when the engine fails, 47 when
it is not there, 4 for PDF to a terminal). It differs in these ways.

- The programs run through `/bin/sh`, each argument quoted, so podoc
  needs a POSIX shell, `mkdir`, `cp` and `rm`. The temporary directory
  is `podoc<pid>-<n>` under `TMPDIR`, or `/tmp`.
- Images are copied into the temporary directory as `img<n>` with
  their extension, where pandoc names them by the SHA1 of their
  contents, or keeps a relative path.
- Images are found relative to the working directory only (pandoc's
  default `--resource-path`); `%`-escapes in their paths are not
  decoded. An image with a URL (`http:`, `data:`, ...) is not fetched
  and is left for the engine.
- For ConTeXt, SVG images are converted to PDF with `rsvg-convert`, as
  pandoc does; images in other formats than PNG, JPEG, PDF, EPS and
  SVG (GIF, BMP, ...), which pandoc converts to PNG itself, are left
  as they are.
- The engine's log is not shown with `--verbose`, which podoc does not
  have.

## The markdown writer

- A run of colons that would start a fenced div is escaped as `\`
  and the same colons. pandoc 3.10 writes one colon too many (`::::`
  becomes `\:::::`), so its output does not read back as its input.
- Citations, which podoc's reader does not read, are written as their
  text.
- An autolink is written as `<...>` when its scheme is in podoc's
  list of URI schemes (the reader's, from pandoc's), which may differ
  from pandoc's own list for a rare scheme.
- Output is not wrapped, as for HTML; `--wrap=preserve` keeps the
  input's line breaks.
- The round trip is not exact, in pandoc either: markdown cannot hold
  everything the AST can. Written and read again, consecutive lists
  gain `<!-- -->` separators, an example list becomes a decimal list,
  simple and pipe tables' default alignments become left alignments,
  tables' column widths change, raw HTML blocks come back as raw
  inlines in a paragraph, an attribute-less span is lost, curly
  quotes in text come back as Quoted, a tight definition's
  paragraphs are joined, metadata numbers and some literal block
  scalars change, and without `--wrap=preserve` line breaks become
  spaces. `make test` checks the round trip on the cases listed in
  `test/roundtrip.txt`; on the user's 49 documents, 40 read back to
  the same AST and the other 9 lose only what pandoc's round trip
  loses.

## The plain writer

- TeX math is written as its TeX between dollars, `$...$` inline and
  `$$...$$` on a line of its own for display math, as pandoc writes
  the math texmath cannot convert. pandoc converts what it can into
  Unicode text (`$x^2$` becomes `x²`, `$\alpha$` becomes `α`); podoc
  has no TeX math parser.
- Output is not wrapped; `--wrap=preserve` keeps the input's line
  breaks.
