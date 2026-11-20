# Differences from pandoc

Where podoc deliberately, or for now, does not do what pandoc 3.10
does. Output that differs from pandoc's but is equivalent (decision 3
in PLAN.md) is listed by the writer.

## The command line

- An unknown option, or an option missing its argument, ends podoc
  with exit status 2 (ArgParser's), where pandoc's is 6. Every other
  error uses pandoc's exit status: 1 for a file that cannot be read or
  written, 22 for an unknown output format.
- `--help` lists podoc's options in ArgParser's form, and error
  messages are podoc's own wording.
- `-t source` writes the input as the reader would see it (joined,
  CRs removed, tabs expanded); pandoc has no such format.

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
  `--wrap=preserve` keeps the input's soft line breaks. A `--wrap`
  value other than `auto`, `none` or `preserve` ends podoc with exit
  status 2.
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
