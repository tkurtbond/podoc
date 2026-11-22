# Differences from pandoc

Where podoc deliberately, or for now, does not do what pandoc 3.10
does. Output that differs from pandoc's but is equivalent (decision 3
in PLAN.md) is listed by the writer.

The comparisons were made with pandoc 3.10. pandoc 3.14 became the
reference on 2026-11-22. The entries on highlighted code, and the
markdown writer's escaped colons, have been checked against 3.14;
the rest have not yet been.

## The command line

- An unknown option, or an option missing its argument, ends podoc
  with exit status 2 (ArgParser's), where pandoc's is 6. Every other
  error uses pandoc's exit status: 1 for a file that cannot be read or
  written, 4 for PDF output podoc cannot make or PDF to a terminal,
  6 for a bad `--wrap`, `--unknown` or
  `--pdf-engine`, 21 for an input format other than markdown or rst, 22 for
  an unknown output format, 23 for a markdown extension, 43 and 47
  for a PDF engine that fails or is not there, 64 for a parse error or `--unknown=error`, 83 for a filter.
- `--help` lists podoc's options in ArgParser's form, and error
  messages are podoc's own wording, starting with "podoc: ".
- `-t source` writes the input as the reader would see it (joined,
  CRs removed, tabs expanded); pandoc has no such format.
- podoc reads only `markdown` and `rst`. For `markdown` it turns
  only `grid_tables` and `pandoc_title_block` on or off (`gutenberg`,
  which pandoc's reader ignores, it takes and ignores); for `rst`, only `auto_identifiers`
  and `literate_haskell` (`lhs`). Any other extension, such as
  `-f markdown+smart`, `-f markdown-smart` or `-f rst+smart`, ends
  podoc with exit status 23, and another format, or an input whose
  extension names one (`.tex`, ...) when there is no `-f`, with 21. Inputs
  and `-o` imply formats as in pandoc, with pandoc's warnings when an
  extension names none.
- podoc writes `html` (`html5`), `ms`, `mom`, `context`, `markdown`,
  `plain`, `json` and PDF; pandoc has no `mom` (see The mom writer); `-t latex`, or `-o x.tex` with no `-t`, ends it with exit
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
- `--unknown=warn|error` is podoc's own (see The reStructuredText
  reader). A value other than `warn` or `error` ends podoc with status 6.
- `--reference-location` is used only by the mom writer, where
  `document` makes notes endnotes; the other writers ignore it. A
  value other than `block`, `section` or `document` gives pandoc's
  message and status, 6.
- `--quiet` and `--log` are not taken. `--verbose` gives only the
  reStructuredText reader's `[INFO]` lines, not pandoc's others
  (the files it reads, the template it uses, ...).

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
- raw TeX blocks, LaTeX environments and macros, and the commands
  pandoc's LaTeX reader reads specially (podoc keeps every `\command`
  with its options and arguments as a raw TeX inline);
- citations, example references (`@label`), wikilinks and base64
  data URIs.

## The reStructuredText reader

- `csv-table` takes `:delim:`, `:quote:` and `:escape:` only as one
  ASCII character (or `tab` and `space` for `:delim:`); pandoc takes
  any one character. Otherwise podoc uses the default, as pandoc does
  for a value it cannot use.
- `csv-table`'s `:url:` is read as a local file, relative to the
  working directory, as `:file:` is; pandoc fetches a URL.
- A CSV parse error gives pandoc's message for an unclosed quote, for
  text after a closing quote and for text after blank lines; other
  messages may differ from pandoc's in what they say was expected.
- An anonymous reference (`` `x`__ ``) with no anonymous target left
  gives a warning, "Anonymous reference with no target", and the
  reference is left unresolved; pandoc ends with a parse error,
  status 64.
- Hyperlink references (`` `name`_ ``, `` `name`__ ``) and
  substitutions (`|name|`) in a footnote's text are resolved; pandoc
  leaves them as links to its internal placeholders (`##REF##name`,
  `##SUBST##|name|`). Anonymous references in footnotes take the
  targets left after the rest of the document. A reference to a
  footnote inside a footnote (`[2]_`) is left as pandoc leaves it,
  a link to `##NOTE##2`.
- `--verbose` reports what the reader skips inside list items,
  substitution definitions and notes too. pandoc parses these more
  than once and loses the messages logged there, so it reports only
  those at the top level and in directives' bodies.
- Positions in messages are pandoc's at the top level. Inside nested
  text, pandoc gives "<file>_chunk line N" counted from the nested
  text; podoc gives the position in the file, exactly inside directive
  bodies and included files, and elsewhere the start of the enclosing
  block.
- `--unknown=warn` and `--unknown=error` are podoc's own: they report
  unknown directives, unknown roles (which pandoc does not report),
  substitution definitions with an unknown directive, table
  directives with no table, and role options pandoc skips. Each is
  reported at its start, where `--verbose`'s `[INFO]` lines, as in
  pandoc, give the position after it.

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

- Code is not highlighted: podoc writes what `pandoc
  --syntax-highlighting=none` writes. By default, pandoc 3.14's ms
  writer highlights code blocks and inline code that name a language,
  writing `\*[KeywordTok "..."]` and the like, and with `-s` defines
  the macros for them. (pandoc 3.10 wrote the tokens even with
  `none`, and without the macros, so its code vanished from the PDF.)
- Code blocks are set in `\f[CR]` (Courier), where pandoc writes
  `\f[C]`. groff 1.25 no longer accepts the font name `C`: it warns
  "font name 'C' is deprecated", fails to open it, and leaves the
  block in the text font, Times-Roman. `\f[CR]` is the font pandoc
  already uses for inline code.
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
- Output is wrapped at `--columns` (72) as pandoc wraps it;
  `--wrap=preserve` keeps the input's line breaks. On the user's 54
  markdown documents, at 40, 72 and 100 columns, with and without
  `-s`, podoc's output is pandoc's except for highlighted code. A
  line holding highlighted inline code or math can wrap at a
  different place, since pandoc's text for them is not podoc's.
- Raw blocks and inlines are passed through for the format `ms`
  only.

## The mom writer

pandoc has no mom writer; `-t mom` (or `-o x.mom`) is podoc's own,
for groff 1.23 and later.

- Notes are footnotes, or endnotes, after the body, with
  `--reference-location=document`. A note in a heading or in a link's
  text is left out, with a warning.
- Links in a heading or in another link's text are written as their
  text.
- mom's block quotes do not nest: a block quote directly inside
  another is written as a quote of its own between the outer one's
  parts, and one further in (in a list in a quote) as its blocks.
- Strikeout is drawn in the colour `strikecolor`, which the template
  defines; subscript is lowered and smaller text.
- TeX math is written as its TeX, as in the ms writer.
- Around each table the hyphenation margin and space are saved and
  restored, as groff 1.23's tbl sets them wrongly after a table.
- Raw blocks and inlines are passed through for the format `mom`
  only.
- Images are `.PDF_IMAGE`, which shows only PDF: an image that is not
  a `.pdf` is left out with a warning, except EPS and PostScript,
  which, as for ms, are converted to PDF with Ghostscript beside the
  output (or with `--extract-media`). A left-out figure keeps its
  caption, and a left-out inline image its description.
- An image's size is its `width` and `height`, where a percentage
  width is of the line length. Without them it is the PDF's page size
  from `pdfinfo`, scaled down to the line length when wider; with
  neither, the image is left out with a warning.
- A figure of one image is centred, with its caption (`CAPTION`) and
  id (`TARGET`); mom puts the caption above the image unless the
  template has `.CAPTION_AFTER_LABEL IMG`. An image in text is set at
  the left margin on a line of its own, since mom floats every image.
- Tables with a header row are `.TS H`, the header repeated on each
  page, and a table's caption is mom's `CAPTION`, above the table and
  no wider than it. A table that ends exactly at the foot of a page
  leaves its header alone at the top of the next (mom's behaviour in
  groff 1.23 to 1.25).
- The default template, `default.mom`, is podoc's own. Its variables
  are `title`, `subtitle`, `author`, `date`, `abstract`, `toc-title`,
  `papersize`, the four margins, `fontfamily`, `pointsize`,
  `lineheight`, and mom's own `columns` (with `column-gutter`, 1.5P by
  default), `printstyle` (TYPESET by default), `doctype`, `linkcolor`,
  `covers` and `code-indent` (code blocks' indent, 0 by default). mom
  shows `date` only on covers.
- `--toc` puts the contents first. mom has no contents depth;
  `--toc-depth` and unnumbered headings under `--number-sections` are
  written with mom's internal macros and registers.
- `statement.mom`, installed with the documentation's examples, sets
  statement paper (5.5 by 8.5 inches), the contents first and
  `.special S Symbola`; groff finds Symbola with
  `--pdf-engine-opt=-F<directory>`.

## The ConTeXt writer

- Code is not highlighted: podoc writes what `pandoc
  --syntax-highlighting=none` writes, `\starttyping` ... `\stoptyping`
  and `\type{...}`. By default, pandoc 3.14's ConTeXt writer
  highlights code blocks and inline code that name a language, writing
  `\starthighlighting` ... `\stophighlighting` and `\highlight{...}`.
  (pandoc 3.10 highlighted code blocks only when no style was named,
  and then `context` failed on an undefined control sequence.)
- Output is wrapped at `--columns` (72) as pandoc wraps it;
  `--wrap=preserve` keeps the input's line breaks. On the user's 54
  markdown documents, at 40, 72 and 100 columns, with and without
  `-s`, podoc's output is pandoc's except for highlighted code. As
  in pandoc, a line block's long lines are wrapped too, and since
  `\startlines` keeps line breaks, they break in the PDF.
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
- `--pdf-engine=pdfmom`, the default for `-t mom`, is podoc's own
  (groff 1.23 and later). podoc runs `pdfmom -t -k -KUTF-8`, with `-e`
  when the source has `.EQ`, and the `--pdf-engine-opt` options, on
  the source's path in the temporary directory; `-V papersize` gives
  no `-dpaper`, as the template's `.PAPER` sets the page. Images are
  converted to PDF as for `groff`. pdfmom of groff 1.23 exits 0 when
  mom aborts (a missing font, say), so podoc then writes the PDF
  pdfmom made; from 1.24, pdfmom fails and podoc exits 43.

## Images

- For ms, and for PDF made with `pdfroff` or `groff`, podoc converts
  local images groff cannot show (SVG, PNG, JPEG, GIF, ...) to PDF and
  writes `.PDFPIC` for them, where pandoc writes a groff comment and
  leaves the image out (decision 23 in PLAN.md; see "Images in ms" in
  podoc.md). For `-t ms -o out.ms` the PDFs go in `out-media/`; with
  `--extract-media=DIR`, beside the copies in `DIR`. To standard
  output, without `--extract-media`, podoc writes pandoc's output and
  warns. pandoc converts images only for its TeX engines.
- For PDF made with `groff` (`groff -Tpdf`), podoc also converts local
  EPS and PostScript images (`.eps`, `.ps`) to PDF with Ghostscript
  and writes `.PDFPIC` for them (decision 26). pandoc writes `.PSPIC`,
  which gropdf ignores, so the images are missing from its PDF.
- `--extract-media` copies local images only, where pandoc also
  fetches URLs and decodes `data:` URIs; podoc leaves those images as
  they are. As for PDF output, images are found relative to the
  working directory only, and `%`-escapes are not decoded; an image
  whose path holds `%` is named by its SHA-1, as in pandoc. For local
  images, podoc's names and output are pandoc's.
- An image that cannot be read is replaced by its description after
  the images found have been copied, so podoc's warning for it comes
  after any warnings about conversion.

## The markdown writer

- A run of colons that would start a fenced div is escaped as `\`
  and the same colons. pandoc (3.10 and 3.14) writes one colon too many (`::::`
  becomes `\:::::`), so its output does not read back as its input.
- Citations, which podoc's reader does not read, are written as their
  text.
- An autolink is written as `<...>` when its scheme is in podoc's
  list of URI schemes (the reader's, from pandoc's), which may differ
  from pandoc's own list for a rare scheme.
- Output is wrapped at `--columns` (72) as pandoc wraps it, the
  YAML metadata block too; `--wrap=preserve` keeps the input's line
  breaks. On the user's 54 markdown documents, at 40, 72 and 100
  columns, with and without `-s`, podoc's output is pandoc's, byte
  for byte.
- The round trip is not exact, in pandoc either: markdown cannot hold
  everything the AST can. Written and read again, consecutive lists
  gain `<!-- -->` separators, an example list becomes a decimal list,
  simple and pipe tables' default alignments become left alignments,
  tables' column widths change, raw HTML blocks come back as raw
  inlines in a paragraph, an attribute-less span is lost, curly
  quotes in text come back as Quoted, a tight definition's
  paragraphs are joined, metadata numbers and some literal block
  scalars change, and without `--wrap=preserve` line breaks become
  spaces and wrapping turns spaces into line breaks. At 10 columns or
  fewer a task list item's `[x]` can wrap away from its marker and
  read back as text, in pandoc too. `make test` checks the round trip on the cases listed in
  `test/roundtrip.txt`; on the user's 49 documents, 40 read back to
  the same AST and the other 9 lose only what pandoc's round trip
  loses.

## The plain writer

- TeX math is written as its TeX between dollars, `$...$` inline and
  `$$...$$` on a line of its own for display math, as pandoc writes
  the math texmath cannot convert. pandoc converts what it can into
  Unicode text (`$x^2$` becomes `x²`, `$\alpha$` becomes `α`); podoc
  has no TeX math parser.
- Output is wrapped at `--columns` (72) as pandoc wraps it; on the
  user's 54 markdown documents, at 40, 72 and 100 columns, podoc's
  output is pandoc's, byte for byte.
