# Differences from pandoc

Where podoc deliberately, or for now, does not do what pandoc 3.10
does. Output that differs from pandoc's but is equivalent (decision 3
in PLAN.md) is listed by the writer.

## The command line

- An unknown option, or an option missing its argument, ends podoc
  with exit status 2 (ArgParser's), where pandoc's is 6. Every other
  error uses pandoc's exit status: 1 for a file that cannot be read or
  written, 4 for PDF output podoc cannot make, 6 for a bad `--wrap` or
  `--pdf-engine`, 21 for an input format other than markdown, 22 for
  an unknown output format, 23 for a markdown extension, 83 for a
  filter.
- `--help` lists podoc's options in ArgParser's form, and error
  messages are podoc's own wording, starting with "podoc: ".
- `-t source` writes the input as the reader would see it (joined,
  CRs removed, tabs expanded); pandoc has no such format.
- podoc reads only `markdown`, and does not turn its extensions on or
  off: `-f markdown+smart` or `-f markdown-smart` ends podoc with exit
  status 23, and `-f rst`, or an input whose extension names another
  format (`.rst`, `.tex`, ...) when there is no `-f`, with 21. Inputs
  and `-o` imply formats as in pandoc, with pandoc's warnings when an
  extension names none.
- podoc writes `html` (`html5`), `ms`, `context`, `markdown`, `json`
  and PDF; `-t latex`, or `-o x.tex` with no `-t`, ends it with exit
  status 22.
- `--pdf-engine` takes only `groff`, `pdfroff` or `context` (by base
  name, so a path is allowed); anything else ends podoc with status 6,
  and the message lists only those three. PDF output with neither
  `-t` nor `--pdf-engine`, which pandoc makes with LaTeX and
  `pdflatex`, and PDF from html, end podoc with status 4.
- Filters are not run. `--lua-filter` and `-F`/`--filter` name the
  user's filters, by file name (any directory), and podoc runs its
  built-in code in their place: `subs.lua`, `strip-comments.lua`,
  `general.lua`, `toc-columns.lua`, `combine-docs.lua` and
  `pandoc-include` (Phases 12 and 13; until then each ends podoc with
  status 83). `pandoc-mermaid-selenium-filter` is ignored with a
  warning (decision 4). Any other filter ends podoc with status 83.
- A `--wrap` value other than `auto`, `none` or `preserve` gives
  pandoc's message and status, 6.

## Input

- Input that is not valid UTF-8 is read as it is; pandoc reads it as
  Latin-1, with a warning.
- Input file names are not URLs: pandoc fetches `http:` and `https:`
  inputs.

## The markdown reader

podoc reads the markdown the user's documents use. It does not yet
read:

- grid tables, or table cells that hold blank lines;
- the `%` title block;
- raw TeX blocks, LaTeX environments and macros, and the commands
  pandoc's LaTeX reader reads specially (podoc keeps every `\command`
  with its options and arguments as a raw TeX inline);
- citations, example references (`@label`), wikilinks and base64
  data URIs.

A table's column widths count East Asian wide and full-width
characters as two and combining marks as none, which approximates
pandoc's character widths.

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

## The markdown writer

- Tables that pandoc writes as grid or pipe tables (cells holding
  more than one paragraph or other blocks, or tables too wide for a
  multiline table) are written as HTML tables, pandoc's fallback when
  no other table extension fits. Simple and multiline tables are
  written as pandoc writes them.
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
  simple tables' default alignments become left alignments (and
  their column widths change), raw HTML blocks come back as raw
  inlines in a paragraph, an attribute-less span is lost, curly
  quotes in text come back as Quoted, a tight definition's
  paragraphs are joined, metadata numbers and some literal block
  scalars change, and without `--wrap=preserve` line breaks become
  spaces. `make test` checks the round trip on the cases listed in
  `test/roundtrip.txt`; on the user's 49 documents, 40 read back to
  the same AST and the other 9 lose only what pandoc's round trip
  loses.
