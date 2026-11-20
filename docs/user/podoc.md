# podoc

podoc is a small subset of [pandoc](https://pandoc.org) 3.10, written
in Oberon-2 and built with the Peaseblossom Oberon Compiler (`poc`).
It reads pandoc markdown with YAML metadata. It writes HTML, groff
`ms`, ConTeXt, markdown and pandoc's JSON, and it makes PDF with
`pdfroff`, `groff` or ConTeXt. It is for systems where pandoc is too
big to install or will not build, and it runs only the parts of pandoc
that a set of writing builds use. Where it does those things, its
output is pandoc's, or equivalent to it. Where it knowingly differs,
[differences.md](differences.md) says how.

## What it needs

- To build: `poc` and the poc libraries ArgParser, Ropes and
  pounicode, installed under both size models (`-O2` and `-OC`) in
  `~/.local/lib/poc`, and GNU make. podoc has one small C part, for
  globs (`opendir`, `readdir`, `stat`), and needs no other C library.
- To run: a POSIX `/bin/sh`. For PDF output, it also needs `mkdir`,
  `cp` and `rm`, plus the engine:
  - for `ms`: groff with `gropdf` and `-k` (`preconv`). groff 1.23.0
    and 1.22.4 work (1.22.4 numbers the contents page "1", not "i");
    1.19.2, as in NetBSD's base system, does not. With groff 1.25.0,
    `--pdf-engine=groff` works, but each heading in a document made
    with bookmarks is followed by a stray `.pdfbookmark` line, as with
    pandoc's ms output; and groff 1.25.0 no longer includes `pdfroff`,
    which, with the pdfmark macros, is now the separate groff-pdfmark
    package. An older `pdfroff` left on the PATH may then make an
    empty PDF without reporting an error;
  - for `context`: ConTeXt LMTX;
  - for SVG images in ConTeXt: `rsvg-convert` (optional).

podoc is built and tested on Linux (Fedora), FreeBSD, NetBSD and
OpenBSD.

## Building and installing

    make                 # build/O2/podoc and build/OC/podoc
    make test            # the tests, under both size models
    make install         # podoc and subs2yaml in ~/.local/bin

`make install` installs the `-OC` build. `PREFIX` (default `~/.local`),
`BINDIR`, `DOCDIR` and `DESTDIR` choose where it goes. `MODEL=O2`
installs the `-O2` build instead. `make uninstall` removes what
`make install` installed.

## Using it

The command line is pandoc's:

    podoc [OPTIONS] [FILES]

podoc joins its input files, as pandoc does, or reads standard input
when no files are named. `podoc --help` lists the options:

| Option | Meaning |
|---|---|
| `-f`, `-r`, `--from`, `--read` | the input format: `markdown` only |
| `-t`, `-w`, `--to`, `--write` | `html` (`html5`), `ms`, `context`, `markdown`, `json` or `pdf` |
| `-o FILE` | the output file; with no `-t`, its extension names the format |
| `-s`, `--standalone` | a whole document, through a template |
| `--template FILE` | the template (implies `-s`) |
| `-V KEY[=VALUE]` | a template variable |
| `-M KEY[=VALUE]`, `--metadata-file FILE` | metadata |
| `-H`, `-B`, `-A FILE` | text for the header, before the body, after the body |
| `--toc`, `--toc-depth N`, `-N` | a table of contents; numbered sections |
| `-c URL`, `--id-prefix STRING` | a style sheet and an identifier prefix, for HTML |
| `--pdf-engine PROGRAM`, `--pdf-engine-opt STRING` | how PDF is made |
| `-F PROGRAM`, `-L FILE` | the built-in filters (see below) |
| `--wrap auto\|none\|preserve` | accepted; podoc does not wrap lines |
| `--tab-stop N`, `-p` | tabs |

The formats are inferred from the file names as pandoc infers them:
`-o book.html` writes HTML, and `-o book.pdf` makes PDF. For PDF,
`--pdf-engine` chooses the engine (`pdfroff` or `groff`, which take
ms, or `context`), and the engine implies the writer; `-t ms` alone
uses `pdfroff`, and `-t context` alone uses `context`. PDF needs one
of these. pandoc's default, LaTeX, is not available.

### Examples

    podoc -s --toc -o book.html book.md
    podoc -t ms --pdf-engine=pdfroff -V papersize=letter -o book.pdf book.md
    podoc -t context --pdf-engine=context -o book.pdf book.md
    podoc -F pandoc-include -L subs.lua \
      --metadata-file=substitutions.yaml -o whole.md -t markdown book.md

## The markdown it reads

podoc reads pandoc's markdown with its default extensions, among them:

- paragraphs, ATX and setext headers, block quotes, lists, code
  blocks, horizontal rules, line blocks and definition lists;
- emphasis, links, images with attributes, footnotes, strikeout,
  superscript, subscript, and smart punctuation;
- YAML metadata blocks, pipe, simple and multiline tables, raw blocks
  and inlines, raw HTML, fenced divs, bracketed spans, and automatic
  header identifiers.

Grid tables, the `%` title block, raw TeX blocks, and citations are
not read. Extensions cannot be turned on or off. The full list of what
is not read is in [differences.md](differences.md).

## Templates

podoc carries pandoc 3.10's default templates for `html5`, `ms`,
`context` and `markdown`. `--template NAME` looks for the name as
given, then with the format's extension added, then in pandoc's user
data directory (`$XDG_DATA_HOME/pandoc/templates`, or
`~/.pandoc/templates`). Templates use pandoc's template language, with
its variables, conditionals, loops, partials and pipes. The `left`,
`right` and `center` pipes are not supported.

## Filters

podoc runs no external filters. In their place it has built-in code,
chosen by the filter's file name (in any directory). Each name must be
given with the option pandoc uses for that filter:

| Given as | What podoc does |
|---|---|
| `-F pandoc-include` | `!include` lines, with globs, `incrementSection`, and image paths rewritten |
| `-L subs.lua` | replaces text using the `substitutions` map in the metadata |
| `-L strip-comments.lua` | removes every paragraph that starts with `%` |
| `-L general.lua` | the Div and Span classes, for each output format |
| `-L toc-columns.lua` | a two-column table of contents, for ConTeXt |
| `-L combine-docs.lua` | the files listed in `combine` metadata, combined as one digest |
| `-F pandoc-mermaid-selenium-filter` | ignored, with a warning |

Any other filter ends podoc with status 83.

### Substitutions

`subs.lua` keeps its table in a Lua file. podoc reads the table from
metadata instead, usually kept in its own YAML file:

```yaml
substitutions:
  "|SCA|": Seltroti
  "|PKA|": Bayhang Avirang
```

Give it with `--metadata-file=substitutions.yaml`. Each key is replaced
in the text by its value. The keys are literal text. The values are
metadata, so they are read as markdown and taken as plain text: put a
backslash before `*`, `_` or a backquote, and before an apostrophe
that should stay straight. `subs2yaml` converts a `substitutions.lua`
file:

    subs2yaml substitutions.lua > substitutions.yaml

## PDF output

podoc writes the ms or ConTeXt source into a temporary directory under
`TMPDIR` (or `/tmp`) and runs the engine there, with pandoc's
arguments.

- `-V papersize=a4` (or `letter`, and so on) sets the paper size for
  ms; add an `l` (`a4l`) for landscape.
- `--pdf-engine-opt` passes an option to the engine.
- An image that cannot be found is replaced by its description, with a
  warning. For ConTeXt, images are copied into the temporary
  directory, and SVG images are converted to PDF with `rsvg-convert`.
- When the engine fails, podoc shows its output, or for ConTeXt the
  first `tex error` line of its log, and ends with status 43.

## Exit statuses

podoc ends with pandoc's exit status for each error:

| Status | Error |
|---|---|
| 1 | a file that cannot be read or written |
| 2 | an unknown option or a missing argument (pandoc: 6) |
| 4 | PDF output podoc cannot make, or PDF to a terminal |
| 5 | a template error |
| 6 | a bad option value |
| 21, 22, 23 | an unknown input format, output format, or extension |
| 43 | a PDF engine that fails |
| 47 | a PDF engine that is not there |
| 64 | a parse error (YAML) |
| 83 | a filter error |
| 97, 98, 99 | a data file, metadata file, or resource not found |

## Differences from pandoc

[differences.md](differences.md) lists each known difference.
