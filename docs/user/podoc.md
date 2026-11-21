# podoc

podoc is a small subset of [pandoc](https://pandoc.org) 3.10, written
in Oberon-2 and built with the Peaseblossom Oberon Compiler (`poc`).
It reads pandoc markdown with YAML metadata. It writes HTML, groff
`ms`, ConTeXt, markdown, plain text and pandoc's JSON, and groff `mom`,
which pandoc does not, and it makes PDF with `pdfroff`, `groff`,
ConTeXt or `pdfmom`. It is for systems where pandoc is too
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
    1.19.2, as in NetBSD's base system, does not. groff 1.24.2 and
    1.25.0 work with `--pdf-engine=groff` (with pandoc's ms output,
    1.25.0 prints a stray `.pdfbookmark` line after each heading and
    makes no bookmarks; see differences.md). groff 1.25.0 itself
    repeats a word, and spaces out a line, in an `.SH` or `.NH`
    heading that wraps to a second line, under `-Tpdf` and `-Tps`
    and under `-Tascii`, `-Tutf8` and `-Tlatin1` alike; 1.24.2 and
    1.23.0 do not. From 1.24 on, ms sets the page footer one line
    higher than 1.23.0 did, which moves nothing else. Since groff 1.24,
    `pdfroff` is not part of groff: with the pdfmark macros, it is now
    the separate groff-pdfmark package. An older `pdfroff` left on the
    PATH may then make an empty PDF without reporting an error;
  - for `context`: ConTeXt LMTX;
  - for `mom`: groff 1.23 or later, with `pdfmom`, and `pdfinfo`
    (poppler) for the sizes of images that give none (see "mom");
  - for SVG images in ConTeXt: `rsvg-convert` (optional).
- For images in ms output (see "Images in ms"), optionally:
  `rsvg-convert` for SVG, and `img2pdf` or ImageMagick (`magick`, or
  version 6's `convert` and `identify`) for PNG, JPEG, GIF and other
  bitmaps. groff before 1.25 reads only PDF 1.4, which podoc asks
  `rsvg-convert` for.
- For EPS and PostScript images in PDF made with `groff`, and in mom
  output: Ghostscript (`gs`), optionally.

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
| `-f`, `-r`, `--from`, `--read` | the input format: `markdown` or `rst` |
| `-t`, `-w`, `--to`, `--write` | `html` (`html5`), `ms`, `mom`, `context`, `markdown`, `plain`, `json` or `pdf`; `plain+gutenberg` for Project Gutenberg's conventions |
| `-o FILE` | the output file; with no `-t`, its extension names the format |
| `-s`, `--standalone` | a whole document, through a template |
| `--template FILE` | the template (implies `-s`) |
| `-V KEY[=VALUE]` | a template variable |
| `-M KEY[=VALUE]`, `--metadata-file FILE` | metadata |
| `-H`, `-B`, `-A FILE` | text for the header, before the body, after the body |
| `--toc`, `--toc-depth N`, `-N` | a table of contents; numbered sections |
| `-c URL`, `--id-prefix STRING` | a style sheet and an identifier prefix, for HTML |
| `--pdf-engine PROGRAM`, `--pdf-engine-opt STRING` | how PDF is made |
| `--extract-media DIR` | copy the local images into `DIR` and refer to the copies |
| `-F PROGRAM`, `-L FILE` | the built-in filters (see below) |
| `--wrap auto\|none\|preserve` | wrapping: for `plain`, `markdown`, `ms` and `context`, `auto` (the default) wraps at `--columns`; HTML is not wrapped |
| `--columns N` | the line length, 72 by default; it also sets table column widths, as in pandoc |
| `--tab-stop N`, `-p` | tabs |
| `--verbose` | informative messages: for `rst`, pandoc's `[INFO]` lines for what the reader skips |
| `--unknown warn\|error` | for `rst`, report unknown directives and roles, and options the reader skips, as warnings, or stop at the first with status 64 (podoc's own) |

The formats are inferred from the file names as pandoc infers them:
`-o book.html` writes HTML, and `-o book.pdf` makes PDF. For PDF,
`--pdf-engine` chooses the engine (`pdfroff` or `groff`, which take
ms, `context`, or `pdfmom`, which takes mom), and the engine implies
the writer; `-t ms` alone uses `groff`, as pandoc does, `-t context`
alone uses `context`, and `-t mom` alone uses `pdfmom`.
PDF needs one of these. pandoc's default, LaTeX, is not available.

### Memory

podoc's heap may grow to 1 GB, enough for an input of about 35 MB.
For a larger one, set `PODOC_HEAP_LIMIT` to the limit in megabytes:

    PODOC_HEAP_LIMIT=4096 podoc -o big.html big.md

When the heap is full, podoc stops with "heap exhausted: NEW cannot
allocate the block" and status 11, or, if it ran out inside one of
its libraries, with "NIL pointer dereference". Close to the limit it
can run for minutes before it stops.

### Examples

    podoc -s --toc -o book.html book.md
    podoc -t ms --pdf-engine=pdfroff -V papersize=letter -o book.pdf book.md
    podoc -t context --pdf-engine=context -o book.pdf book.md
    podoc -t mom --toc -V papersize=a4 -o book.pdf book.md
    podoc -F pandoc-include -L subs.lua \
      --metadata-file=substitutions.yaml -o whole.md -t markdown book.md

## The markdown it reads

podoc reads pandoc's markdown with its default extensions, among them:

- paragraphs, ATX and setext headers, block quotes, lists, code
  blocks, horizontal rules, line blocks and definition lists;
- emphasis, links, images with attributes, footnotes, strikeout,
  superscript, subscript, and smart punctuation;
- YAML metadata blocks, pipe, simple, multiline and grid tables
  (with row and column spans), raw blocks
  and inlines, raw HTML, fenced divs, bracketed spans, and automatic
  header identifiers.

The `%` title block at the top of a document gives the title, the
authors (separated by `;` or line ends) and the date, as in pandoc;
a YAML metadata block wins over it. Raw TeX blocks and citations are
not read. Of the extensions, only `grid_tables` and
`pandoc_title_block` can be turned off, with `-f markdown-grid_tables`
or `-f markdown-pandoc_title_block`; as in pandoc, an extension both turned on
and off (`-f markdown-grid_tables+grid_tables`, in either order) is
on. The full list of what is not read is in
[differences.md](differences.md).

podoc's reStructuredText reader, `-f rst` (and `.rst` inputs), reads
what pandoc's does: sections, every kind of block, inline markup and
roles, substitutions, references, footnotes and citations, every
directive pandoc knows (with `include`), grid and simple tables and
the table directives, and `-f rst+lhs`. With `-s` it promotes a lone
top section to the title, and a lone subsection to the subtitle, and
takes the document's first field list as metadata, as pandoc does. On
the user's 73 reStructuredText files its output was pandoc's, byte for
byte, with and without `-s` (2026-11-21).

pandoc passes over unknown directives and some role options in
silence, or reports them only with `--verbose`. podoc's
`--unknown=warn` reports each as a warning, with its position, and
`--unknown=error` stops at the first with status 64, so a document
can be checked for what neither program will render.

## Templates

podoc carries pandoc 3.10's default templates for `html5`, `ms`,
`context`, `markdown` and `plain`, and its own for `mom` (see "mom"). `--template NAME` looks for the name as
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
| `-L general.lua` | the Div and Span classes, for each output format; for mom, as for ms, with `for-format mom` |
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

## mom

`-t mom`, or `-o book.mom`, writes groff's mom macros, for groff 1.23
and later; pandoc has no mom writer. `pdfmom` makes the PDF:

    podoc -t mom -s --toc -o book.mom book.md
    pdfmom -t -KUTF-8 book.mom > book.pdf
    podoc -t mom --toc -o book.pdf book.md

Run `pdfmom` in the output's directory, as converted images' paths
are relative to it (see "Images in ms").

- Notes are footnotes, or endnotes after the body with
  `--reference-location=document`.
- `--toc` puts the contents at the start; `--toc-depth` limits them,
  and `-N` numbers the headings, leaving out those with the class
  `unnumbered`.
- Raw blocks and inlines for `mom` are passed through as they are, so
  they may hold any mom macro or groff request or escape (`.NEWPAGE`,
  say); other raw formats are dropped.
- mom shows only PDF images. EPS and PostScript are converted to PDF
  with Ghostscript, and for PDF output other images are too, as for
  ms. An image's size is its `width` and `height` (a percentage width
  is of the line length), or else its PDF's page size from `pdfinfo`,
  scaled down to the line length when wider; an image with neither is
  left out, with a warning. A figure's caption goes below it.

The default template uses mom's own defaults (TYPESET, letter paper),
with these variables:

| Variable | Gives |
|---|---|
| `title`, `subtitle`, `author`, `date` | `TITLE`, `SUBTITLE`, `AUTHOR` (one or more), `MISC`; mom shows the date only on covers |
| `abstract` | a block quote after the title |
| `toc-title` | the contents' heading |
| `papersize` | `PAPER`: `letter`, `a4`, `statement`, ... |
| `margin-left`, `margin-right`, `margin-top`, `margin-bottom` | the margins (`1i`, `2c`, ...) |
| `fontfamily`, `pointsize`, `lineheight` | `FAMILY`, `PT_SIZE`, `LS` |
| `columns`, `column-gutter` | `COLUMNS`, the gutter 1.5P by default |
| `printstyle` | `TYPESET` (the default) or `TYPEWRITE` |
| `doctype` | `DOCTYPE`: `DEFAULT`, `CHAPTER`, `NAMED "..."`, `LETTER` |
| `linkcolor` | `PDF_LINK_COLOR`: a colour name, `#rrggbb` or three numbers |
| `covers` | a cover page with the title, subtitle, authors and date |
| `header-includes`, `include-before`, `include-after` | as in pandoc's templates |

To write your own, start from the default, `data/templates/default.mom`
in podoc's source, and pass it with `--template`. The setup macros
must stay in mom's order:
the reference macros (`TITLE` ...), `DOCTYPE`, `PAPER` before
`PRINTSTYLE`, then the margins, fonts and `COLUMNS`, then `START`. The
body is `$body$`; with `--toc`, keep `AUTO_RELOCATE_TOC` before
`START` (with `TOP` when there are no covers) and `.TOC` at the end.
The template defines the colour `strikecolor`, which strikeout uses.

`statement.mom`, installed in `$(DOCDIR)/examples`, is an example: a
statement-sized (5.5 by 8.5 inch) document with narrow margins,
Palatino, no running headers, unindented paragraphs and the contents
first. It marks Symbola as a special font, for symbols the text fonts
lack; tell groff where Symbola is with `--pdf-engine-opt`:

    podoc -t mom --template=statement.mom --toc \
      --pdf-engine-opt=-F/usr/local/share/groff/site-font -o book.pdf book.rst

## PDF output

podoc writes the ms, mom or ConTeXt source into a temporary directory under
`TMPDIR` (or `/tmp`) and runs the engine there, with pandoc's
arguments.

- `-V papersize=a4` (or `letter`, and so on) sets the paper size for
  ms; add an `l` (`a4l`) for landscape. For mom the template sets it.
- For mom, podoc runs `pdfmom -t -k -KUTF-8` on the source's path.
- `--pdf-engine-opt` passes an option to the engine.
- An image that cannot be found is replaced by its description, with a
  warning. Images are copied into the temporary directory. For
  ConTeXt, SVG images are converted to PDF with `rsvg-convert`; for
  ms, every image groff cannot show is converted to PDF (see "Images
  in ms").
- When the engine fails, podoc shows its output, or for ConTeXt the
  first `tex error` line of its log, and ends with status 43.

## Images

`--extract-media=DIR` copies each local image into `DIR`, as pandoc
does, and points the image at the copy: `img/map.png` is copied to
`DIR/img/map.png`. An image whose path is absolute or holds `..` or
`%` is named by the SHA-1 of its contents instead, with the extension
of its media type. An image that cannot be read is replaced by its
description, with a warning. URLs and `data:` URIs are left as they
are.

### Images in ms

groff's ms shows only PDF images (`.PDFPIC`), and pandoc writes a
comment in place of any other image, which is then missing from the
PDF. podoc converts such images, local files with the extension of
an image type (`.svg`, `.png`, `.jpg`, `.gif`, ...), to PDF and writes
`.PDFPIC` for them:

- SVG with `rsvg-convert`; other images with the first of `img2pdf`
  and ImageMagick that is found and succeeds. An image with no
  resolution of its own is taken as 96 dpi, pandoc's default.
- The PDF is named for the image, `map.png` giving `map.pdf`, with a
  number added when two would clash (`map-2.pdf`).
- For PDF output, the PDFs go in the temporary directory.
- With `--extract-media=DIR`, they go in `DIR` beside the copies.
- With `-o out.ms`, they go in `out-media/` beside `out.ms`, and the
  paths written are relative to the output's directory: run groff
  there (`cd` to it first), since groff looks for `.PDFPIC` files from
  the directory it runs in. A `.pdf` image keeps the path written in
  the document, relative to podoc's directory, as pandoc writes it.
- Written to standard output, the images are not converted, and podoc
  warns.
- When no converter is found or a conversion fails, podoc warns and
  writes pandoc's comment.
- A width given as a percentage (`{width=50%}`) is written as `0p`,
  as pandoc writes it for a `.pdf` image, and groff then skips the
  image.

EPS and PostScript images (`.eps` and `.ps`, in lower case, as pandoc
matches them) are written as `.PSPIC`, which `groff -Tps` and
`pdfroff` show and `groff -Tpdf` ignores. So for PDF made with
`--pdf-engine=groff`, the default for ms, podoc converts them to PDF
with Ghostscript (`gs`), cropped to their bounding box, and writes
`.PDFPIC`. Without `gs`, or if the conversion fails, podoc warns and
the image is left out, as before. `-t ms` output and `pdfroff` keep
`.PSPIC`.

## Exit statuses

podoc ends with pandoc's exit status for each error:

| Status | Error |
|---|---|
| 1 | a file that cannot be read or written |
| 2 | an unknown option or a missing argument (pandoc: 6) |
| 4 | PDF output podoc cannot make, or PDF to a terminal |
| 5 | a template error |
| 6 | a bad option value, or a `PODOC_HEAP_LIMIT` that is not a positive number |
| 21, 22, 23 | an unknown input format, output format, or extension |
| 43 | a PDF engine that fails |
| 47 | a PDF engine that is not there |
| 64 | a parse error (YAML, reStructuredText), or `--unknown=error` |
| 83 | a filter error |
| 97, 98, 99 | a data file, metadata file, or resource not found |
| 11 | the heap is full (see "Memory") |

## Differences from pandoc

[differences.md](differences.md) lists each known difference.
